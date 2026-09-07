import 'dart:async';
import 'app_events.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:vertree/core/result.dart';
import 'package:vertree/service/lan_share_payload_codec.dart';

class LanFileShareServer {
  LanFileShareServer({
    this.sharePageBaseUrl = defaultSharePageBaseUrl,
    Future<List<String>> Function()? addressResolver,
    Future<String?> Function()? wifiNameResolver,
    void Function(String message)? onLogInfo,
    void Function(String message)? onLogError,
  }) : _addressResolver = addressResolver ?? _discoverLanIpv4Addresses,
       _wifiNameResolver = wifiNameResolver ?? _discoverWifiName,
       _onLogInfo = onLogInfo,
       _onLogError = onLogError {
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _purgeExpiredShares(),
    );
  }

  static const int defaultPort = 31424;
  static const int maxPortSearchSpan = 100;
  static const int defaultExpiryMinutes = 30;
  static const String defaultSharePageBaseUrl = 'https://vertree.w0fv1.dev/f';

  final String sharePageBaseUrl;
  final Future<List<String>> Function() _addressResolver;
  final Future<String?> Function() _wifiNameResolver;
  final void Function(String message)? _onLogInfo;
  final void Function(String message)? _onLogError;

  late final Timer _cleanupTimer;
  final Map<String, _LanFileShareEntry> _sharesByToken =
      <String, _LanFileShareEntry>{};
  final Map<String, _LanFileShareEntry> _sharesByKey =
      <String, _LanFileShareEntry>{};
  final Random _random = Random.secure();

  HttpServer? _server;
  int? _port;
  List<String> _lastKnownLanIps = const <String>[];
  String? _lastKnownWifiName;
  int _nextShareSequence = 1;

  bool get isRunning => _server != null;
  int? get port => _port;

  Map<String, dynamic> status() {
    _purgeExpiredShares();
    return {
      'running': isRunning,
      'port': _port,
      'defaultPort': defaultPort,
      'maxPortSearchSpan': maxPortSearchSpan,
      'sharePageBaseUrl': sharePageBaseUrl,
      'activeShareCount': _sharesByToken.length,
      'lastKnownLanIps': _lastKnownLanIps,
      'lastKnownWifiName': _lastKnownWifiName,
    };
  }

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    for (
      var candidate = defaultPort;
      candidate < defaultPort + maxPortSearchSpan;
      candidate++
    ) {
      try {
        final server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          candidate,
        );
        _server = server;
        _port = candidate;
        unawaited(_listen(server));
        _logInfo('LAN file share server started at 0.0.0.0:$candidate');
        return;
      } on SocketException catch (error) {
        _logInfo(
          'Port $candidate unavailable for LAN file share server: $error',
        );
      }
    }

    throw Exception(
      'Unable to bind LAN file share server after trying ports '
      '$defaultPort-${defaultPort + maxPortSearchSpan - 1}',
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    if (server != null) {
      await server.close(force: true);
      _logInfo('LAN file share server stopped');
    }
  }

  Future<void> dispose() async {
    _cleanupTimer.cancel();
    await stop();
  }

  Future<Result<Map<String, dynamic>, String>> createShare(
    String filePath, {
    int expiresInMinutes = defaultExpiryMinutes,
  }) async {
    _purgeExpiredShares();
    if (expiresInMinutes < 1) {
      return Result.eMsg('expiresInMinutes must be greater than 0');
    }

    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);
    if (!file.existsSync()) {
      return Result.eMsg('File does not exist: $normalizedPath');
    }

    await start();
    final lanIps = await _resolveLanIps();
    final wifiName = await _resolveWifiName();
    if (lanIps.isEmpty || _port == null) {
      return Result.eMsg(
        'No reachable RFC1918 LAN IPv4 address was detected for this machine.',
      );
    }

    final stat = file.statSync();
    final now = DateTime.now();
    final entry = _LanFileShareEntry(
      shareKey: _generateShareKey(),
      token: _generateToken(),
      filePath: normalizedPath,
      fileName: p.basename(normalizedPath),
      fileSize: stat.size,
      createdAt: now,
      expiresAt: now.add(Duration(minutes: expiresInMinutes)),
    );
    _sharesByToken[entry.token] = entry;
    _sharesByKey[entry.shareKey] = entry;
    AppEvents.instance.emit('share.created', {'token': entry.token, 'path': entry.filePath, 'expiresAt': entry.expiresAt.toIso8601String()});

    return Result.ok(_shareToMap(entry, lanIps, wifiName: wifiName));
  }

  Future<Map<String, dynamic>> listShares() async {
    _purgeExpiredShares();
    final lanIps = await _resolveLanIps();
    final wifiName = await _resolveWifiName();
    final items = _sharesByToken.values
        .map((entry) => _shareToMap(entry, lanIps, wifiName: wifiName))
        .toList(growable: false);
    items.sort(
      (left, right) => ((right['createdAt'] as String?) ?? '').compareTo(
        ((left['createdAt'] as String?) ?? ''),
      ),
    );
    return {'count': items.length, 'items': items};
  }

  Future<Result<Map<String, dynamic>, String>> getShare(String token) async {
    _purgeExpiredShares();
    final entry = _findActiveShare(token);
    if (entry == null) {
      return Result.eMsg('LAN file share not found: $token');
    }
    final lanIps = await _resolveLanIps();
    final wifiName = await _resolveWifiName();
    return Result.ok(_shareToMap(entry, lanIps, wifiName: wifiName));
  }

  Result<Map<String, dynamic>, String> revokeShare(String token) {
    _purgeExpiredShares();
    final entry = _findActiveShare(token);
    if (entry == null) {
      return Result.eMsg('LAN file share not found: $token');
    }
    _removeShare(entry);
    AppEvents.instance.emit('share.revoked', {'token': entry.token, 'path': entry.filePath});
    return Result.ok({
      'shareRef': token,
      'token': entry.token,
      'shareKey': entry.shareKey,
      'revoked': true,
      'fileName': entry.fileName,
    });
  }

  Future<void> _listen(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (error) {
      _logError('LAN file share listen loop failed: $error');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      _purgeExpiredShares();
      final segments = request.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);

      if (request.method == 'OPTIONS') {
        await _writeOptionsResponse(request);
        return;
      }

      if (segments.isEmpty || segments.first != 'file-share') {
        await _writeText(
          request,
          statusCode: HttpStatus.notFound,
          body: 'Not found',
        );
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[1] == 'probe') {
        await _handleProbe(request, segments[2]);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[1] == 'pixel') {
        await _handlePixelProbe(request, segments[2]);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[1] == 'download') {
        await _handleDownload(request, segments[2]);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[1] == 'page') {
        await _handleLandingPage(request, segments[2]);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[1] == 'preview') {
        await _handlePreview(request, segments[2]);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[1] == 'info') {
        await _handleInfo(request, segments[2]);
        return;
      }

      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Not found',
      );
    } catch (error) {
      _logError('LAN file share request failed: $error');
      try {
        await _writeText(
          request,
          statusCode: HttpStatus.internalServerError,
          body: 'Internal server error',
        );
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Future<void> _handleProbe(HttpRequest request, String token) async {
    final entry = _findActiveShare(token);
    if (entry == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Share not found',
      );
      return;
    }

    await _writeText(request, statusCode: HttpStatus.ok, body: 'ok');
  }

  Future<void> _handlePixelProbe(HttpRequest request, String token) async {
    final entry = _findActiveShare(token);
    if (entry == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Share not found',
      );
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    _setCommonHeaders(request.response);
    request.response.headers.contentType = ContentType('image', 'gif');
    request.response.add(
      base64Decode(
        'R0lGODlhAQABAPAAAAAAAAAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==',
      ),
    );
    await request.response.close();
  }

  Future<void> _handleInfo(HttpRequest request, String token) async {
    final entry = _findActiveShare(token);
    if (entry == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.notFound,
        body: const {'success': false, 'message': 'Share not found'},
      );
      return;
    }

    await _writeJson(
      request,
      statusCode: HttpStatus.ok,
      body: {
        'success': true,
        'data': {
          'shareKey': entry.shareKey,
          'token': entry.token,
          'fileName': entry.fileName,
          'fileSize': entry.fileSize,
          'createdAt': entry.createdAt.toIso8601String(),
          'expiresAt': entry.expiresAt.toIso8601String(),
          'downloadCount': entry.downloadCount,
          'lastDownloadedAt': entry.lastDownloadedAt?.toIso8601String(),
        },
      },
    );
  }

  Future<void> _handleLandingPage(HttpRequest request, String token) async {
    final entry = _findActiveShare(token);
    if (entry == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Share not found',
      );
      return;
    }

    final currentPort = _port;
    if (currentPort == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.serviceUnavailable,
        body: 'LAN file share server is not ready',
      );
      return;
    }

    final hostHeader = request.headers.value(HttpHeaders.hostHeader) ?? '';
    final host = request.requestedUri.host.isNotEmpty
        ? request.requestedUri.host
        : (hostHeader.contains(':')
              ? hostHeader.split(':').first
              : hostHeader.isNotEmpty
              ? hostHeader
              : '127.0.0.1');
    final downloadUrl =
        'http://$host:$currentPort/file-share/download/${entry.shareKey}';
    final previewUrl =
        'http://$host:$currentPort/file-share/preview/${entry.shareKey}';

    request.response.statusCode = HttpStatus.ok;
    _setCommonHeaders(request.response);
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      _buildLandingPageHtml(
        entry,
        downloadUrl: downloadUrl,
        previewUrl: previewUrl,
      ),
    );
    await request.response.close();
  }

  Future<void> _handlePreview(HttpRequest request, String token) async {
    final entry = _findActiveShare(token);
    if (entry == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Share not found',
      );
      return;
    }

    final file = File(entry.filePath);
    if (!file.existsSync()) {
      _removeShare(entry);
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Source file no longer exists',
      );
      return;
    }

    final contentType = _previewContentTypeForFile(entry.fileName);
    if (contentType == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.unsupportedMediaType,
        body: 'Preview is not available for this file type',
      );
      return;
    }

    final stat = file.statSync();
    request.response.statusCode = HttpStatus.ok;
    _setCommonHeaders(request.response);
    request.response.headers.contentType = contentType;
    request.response.headers.set(HttpHeaders.contentLengthHeader, stat.size);
    request.response.headers.set(
      'content-disposition',
      'inline; filename="${entry.fileName.replaceAll('"', '')}"',
    );
    await file.openRead().pipe(request.response);
  }

  Future<void> _handleDownload(HttpRequest request, String token) async {
    final entry = _findActiveShare(token);
    if (entry == null) {
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Share not found',
      );
      return;
    }

    final file = File(entry.filePath);
    if (!file.existsSync()) {
      _removeShare(entry);
      await _writeText(
        request,
        statusCode: HttpStatus.notFound,
        body: 'Source file no longer exists',
      );
      return;
    }

    final stat = file.statSync();
    request.response.statusCode = HttpStatus.ok;
    _setCommonHeaders(request.response);
    request.response.headers.contentType = ContentType.binary;
    request.response.headers.set(HttpHeaders.contentLengthHeader, stat.size);
    request.response.headers.set(
      'content-disposition',
      _contentDisposition(entry.fileName),
    );
    await file.openRead().pipe(request.response);

    entry.downloadCount += 1;
    entry.lastDownloadedAt = DateTime.now();
  }

  _LanFileShareEntry? _findActiveShare(String token) {
    final normalizedRef = token.trim();
    if (normalizedRef.isEmpty) {
      return null;
    }

    final entry = _sharesByToken[normalizedRef] ?? _sharesByKey[normalizedRef];
    if (entry == null) {
      return null;
    }
    if (entry.isExpired) {
      _removeShare(entry);
      return null;
    }
    return entry;
  }

  void _purgeExpiredShares() {
    final expiredEntries = _sharesByToken.values
        .where((entry) => entry.isExpired)
        .toList(growable: false);
    for (final entry in expiredEntries) {
      _removeShare(entry);
      AppEvents.instance.emit('share.expired', {'token': entry.token, 'path': entry.filePath});
    }
  }

  Future<List<String>> _resolveLanIps() async {
    final addresses = await _addressResolver();
    _lastKnownLanIps = addresses;
    return addresses;
  }

  Future<String?> _resolveWifiName() async {
    final wifiName = _normalizeWifiName(await _wifiNameResolver());
    _lastKnownWifiName = wifiName;
    return wifiName;
  }

  Map<String, dynamic> _shareToMap(
    _LanFileShareEntry entry,
    List<String> lanIps, {
    String? wifiName,
  }) {
    final currentPort = _port;
    final compactShareCode = currentPort == null
        ? null
        : LanSharePayloadCodec.encodeCompactRoute(
            shareKey: entry.shareKey,
            lanIps: lanIps,
          );
    final directDownloads = currentPort == null
        ? const <Map<String, dynamic>>[]
        : lanIps
              .map(
                (ip) => {
                  'ip': ip,
                  'pageUrl':
                      'http://$ip:$currentPort/file-share/page/${entry.shareKey}',
                  'infoUrl':
                      'http://$ip:$currentPort/file-share/info/${entry.shareKey}',
                  'downloadUrl':
                      'http://$ip:$currentPort/file-share/download/${entry.shareKey}',
                  'probeUrl':
                      'http://$ip:$currentPort/file-share/probe/${entry.shareKey}',
                  'pixelProbeUrl':
                      'http://$ip:$currentPort/file-share/pixel/${entry.shareKey}',
                },
              )
              .toList(growable: false);

    return {
      'token': entry.token,
      'shareKey': entry.shareKey,
      'fileName': entry.fileName,
      'fileSize': entry.fileSize,
      'createdAt': entry.createdAt.toIso8601String(),
      'expiresAt': entry.expiresAt.toIso8601String(),
      'downloadCount': entry.downloadCount,
      'lastDownloadedAt': entry.lastDownloadedAt?.toIso8601String(),
      'networkName': wifiName,
      'shareCode': compactShareCode,
      'sharePageUrl': currentPort == null
          ? null
          : _buildSharePageUrl(compactShareCode: compactShareCode!),
      'server': {
        'port': currentPort,
        'defaultPort': defaultPort,
        'maxPortSearchSpan': maxPortSearchSpan,
        'running': isRunning,
        'sharePageBaseUrl': sharePageBaseUrl,
      },
      'lanIps': lanIps,
      'directDownloads': directDownloads,
    };
  }

  String _buildSharePageUrl({required String compactShareCode}) {
    return '$sharePageBaseUrl#$compactShareCode';
  }

  String _generateToken() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateShareKey() {
    final shareKey = LanSharePayloadCodec.encodeBase62(_nextShareSequence);
    _nextShareSequence += 1;
    return shareKey;
  }

  void _removeShare(_LanFileShareEntry entry) {
    _sharesByToken.remove(entry.token);
    _sharesByKey.remove(entry.shareKey);
  }

  String _contentDisposition(String fileName) {
    final ascii = fileName
        .replaceAll(RegExp(r'[^ -~]'), '_')
        .replaceAll('"', '');
    final encoded = Uri.encodeComponent(fileName);
    return 'attachment; filename="$ascii"; filename*=UTF-8\'\'$encoded';
  }

  String _buildLandingPageHtml(
    _LanFileShareEntry entry, {
    required String downloadUrl,
    required String previewUrl,
  }) {
    final title = '${entry.fileName} - Vertree LAN Share';
    final safeTitle = htmlEscape.convert(title);
    final safeFileName = htmlEscape.convert(entry.fileName);
    final safeFileSize = htmlEscape.convert(_formatBytes(entry.fileSize));
    final safeExpiresAt = htmlEscape.convert(
      _formatLocalDateTime(entry.expiresAt),
    );
    final safeDownloadUrl = htmlEscape.convert(downloadUrl);
    final downloadUrlJson = jsonEncode(downloadUrl);
    final previewSection = _buildPreviewSection(entry, previewUrl: previewUrl);

    return '''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$safeTitle</title>
  <style>
    :root {
      color-scheme: light;
      font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
      --page-bg: #f3f6f1;
      --surface: #fbfcfa;
      --surface-soft: #f6f8f4;
      --border: rgba(23, 59, 36, 0.08);
      --text-primary: #173b24;
      --text-secondary: #52705f;
      --accent: #2f6b42;
    }
    body {
      margin: 0;
      background:
        radial-gradient(circle at top left, rgba(70, 125, 86, 0.08), transparent 28%),
        linear-gradient(180deg, var(--page-bg) 0%, #f7faf6 100%);
      color: var(--text-primary);
    }
    main {
      max-width: 860px;
      margin: 0 auto;
      padding: 40px 20px 56px;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 28px;
      box-shadow: 0 20px 50px rgba(50, 78, 58, 0.08);
      padding: 30px;
    }
    h1 {
      font-size: 34px;
      line-height: 1.15;
      margin: 0 0 12px;
    }
    p {
      margin: 0 0 16px;
      color: var(--text-secondary);
      line-height: 1.7;
      font-size: 16px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin: 24px 0;
    }
    .meta {
      border-radius: 20px;
      background: var(--surface-soft);
      border: 1px solid var(--border);
      padding: 16px;
    }
    .label {
      color: #647c6d;
      font-size: 13px;
      margin-bottom: 6px;
    }
    .value {
      font-size: 20px;
      font-weight: 700;
      word-break: break-word;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 24px;
    }
    .section {
      margin-top: 24px;
      padding: 20px;
      border-radius: 24px;
      background: var(--surface-soft);
      border: 1px solid var(--border);
    }
    .section h2 {
      margin: 0 0 10px;
      font-size: 20px;
      line-height: 1.2;
    }
    .button {
      appearance: none;
      border: 0;
      border-radius: 999px;
      padding: 14px 22px;
      cursor: pointer;
      text-decoration: none;
      font-size: 15px;
      font-weight: 700;
    }
    .button-primary {
      background: var(--accent);
      color: white;
    }
    .hint {
      margin-top: 18px;
      font-size: 14px;
      color: #607565;
    }
    code {
      display: block;
      margin-top: 10px;
      padding: 14px;
      border-radius: 16px;
      background: #f0f4ef;
      color: #325240;
      word-break: break-all;
      font-size: 13px;
    }
    .previewFrame {
      margin-top: 14px;
      border-radius: 20px;
      overflow: hidden;
      border: 1px solid var(--border);
      background: white;
    }
    .previewImage,
    .previewPdf {
      display: block;
      width: 100%;
      border: 0;
      background: white;
    }
    .previewImage {
      max-height: 420px;
      object-fit: contain;
    }
    .previewPdf {
      min-height: 480px;
    }
    .previewText {
      margin-top: 14px;
      padding: 16px;
      border-radius: 20px;
      border: 1px solid var(--border);
      background: #f0f4ef;
      color: #274636;
      font-size: 13px;
      line-height: 1.65;
      white-space: pre-wrap;
      word-break: break-word;
      max-height: 420px;
      overflow: auto;
    }
    .previewTag {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 6px 10px;
      border-radius: 999px;
      background: rgba(47, 107, 66, 0.1);
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.02em;
    }
  </style>
</head>
<body>
  <main>
    <section class="card">
      <h1>准备下载 $safeFileName</h1>
      <p>你已经进入分享者电脑提供的局域网下载页。下载会从当前这个本地 HTTP 页面发起，比直接从公网分享页跳转到下载更稳定。</p>
      <div class="grid">
        <div class="meta">
          <div class="label">文件名</div>
          <div class="value">$safeFileName</div>
        </div>
        <div class="meta">
          <div class="label">文件大小</div>
          <div class="value">$safeFileSize</div>
        </div>
        <div class="meta">
          <div class="label">失效时间</div>
          <div class="value">$safeExpiresAt</div>
        </div>
      </div>
$previewSection
      <div class="actions">
        <a id="downloadLink" class="button button-primary" href="$safeDownloadUrl">立即下载</a>
      </div>
      <p class="hint">如果浏览器没有自动开始下载，可以点击上面的按钮。下载地址：</p>
      <code>$safeDownloadUrl</code>
    </section>
  </main>
  <script>
    const downloadUrl = $downloadUrlJson;
    const triggerDownload = () => {
      window.location.assign(downloadUrl);
    };
    window.setTimeout(triggerDownload, 320);
  </script>
</body>
</html>
''';
  }

  String _buildPreviewSection(
    _LanFileShareEntry entry, {
    required String previewUrl,
  }) {
    final file = File(entry.filePath);
    if (!file.existsSync()) {
      return '';
    }

    final safePreviewUrl = htmlEscape.convert(previewUrl);
    final fileName = htmlEscape.convert(entry.fileName);

    if (_isImagePreviewFile(entry.fileName)) {
      return '''
      <section class="section">
        <span class="previewTag">图片预览</span>
        <h2>文件预览</h2>
        <p>这是浏览器可直接展示的图片预览，完整文件仍以下载结果为准。</p>
        <div class="previewFrame">
          <img class="previewImage" src="$safePreviewUrl" alt="$fileName" loading="eager">
        </div>
      </section>
''';
    }

    if (_isPdfPreviewFile(entry.fileName)) {
      return '''
      <section class="section">
        <span class="previewTag">PDF 预览</span>
        <h2>文件预览</h2>
        <p>浏览器支持时会直接内嵌 PDF 预览；如果未显示，仍可以直接下载原文件。</p>
        <div class="previewFrame">
          <iframe class="previewPdf" src="$safePreviewUrl" title="$fileName"></iframe>
        </div>
      </section>
''';
    }

    if (_isTextPreviewFile(entry.fileName)) {
      final textPreview = htmlEscape.convert(_readTextPreview(file));
      return '''
      <section class="section">
        <span class="previewTag">文本预览</span>
        <h2>文件预览</h2>
        <p>这里展示的是文件开头的一部分内容，适合快速确认文本、代码、配置或日志文件。</p>
        <pre class="previewText">$textPreview</pre>
      </section>
''';
    }

    return '';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatLocalDateTime(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  static String _readTextPreview(File file) {
    const maxBytes = 24 * 1024;
    const maxChars = 5000;
    RandomAccessFile? handle;
    try {
      handle = file.openSync(mode: FileMode.read);
      final bytes = handle.readSync(maxBytes);
      var text = utf8
          .decode(bytes, allowMalformed: true)
          .replaceAll('\r\n', '\n');
      final wasTrimmedByBytes = handle.positionSync() < handle.lengthSync();
      if (text.length > maxChars) {
        text = text.substring(0, maxChars);
      }
      if (wasTrimmedByBytes || text.length >= maxChars) {
        text = '$text\n\n... 仅显示前部内容，完整内容请下载原文件查看。';
      }
      return text.trimRight();
    } catch (_) {
      return '当前文件无法生成文本预览，请直接下载查看。';
    } finally {
      handle?.closeSync();
    }
  }

  static bool _isImagePreviewFile(String fileName) {
    const imageExtensions = <String>{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.svg',
    };
    return imageExtensions.contains(p.extension(fileName).toLowerCase());
  }

  static bool _isPdfPreviewFile(String fileName) {
    return p.extension(fileName).toLowerCase() == '.pdf';
  }

  static bool _isTextPreviewFile(String fileName) {
    const textExtensions = <String>{
      '.txt',
      '.md',
      '.markdown',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.css',
      '.js',
      '.ts',
      '.tsx',
      '.jsx',
      '.dart',
      '.java',
      '.kt',
      '.py',
      '.sh',
      '.bat',
      '.ps1',
      '.csv',
      '.log',
      '.ini',
      '.toml',
      '.sql',
      '.conf',
    };
    return textExtensions.contains(p.extension(fileName).toLowerCase());
  }

  static ContentType? _previewContentTypeForFile(String fileName) {
    switch (p.extension(fileName).toLowerCase()) {
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.webp':
        return ContentType('image', 'webp');
      case '.bmp':
        return ContentType('image', 'bmp');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.pdf':
        return ContentType('application', 'pdf');
      default:
        return null;
    }
  }

  Future<void> _writeOptionsResponse(HttpRequest request) async {
    request.response.statusCode = HttpStatus.noContent;
    _setCommonHeaders(request.response);
    request.response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, HEAD, OPTIONS',
    );
    request.response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type',
    );
    request.response.headers.set(
      'Access-Control-Allow-Private-Network',
      'true',
    );
    await request.response.close();
  }

  Future<void> _writeText(
    HttpRequest request, {
    required int statusCode,
    required String body,
  }) async {
    request.response.statusCode = statusCode;
    _setCommonHeaders(request.response);
    request.response.headers.contentType = ContentType.text;
    request.response.write(body);
    await request.response.close();
  }

  Future<void> _writeJson(
    HttpRequest request, {
    required int statusCode,
    required Map<String, dynamic> body,
  }) async {
    request.response.statusCode = statusCode;
    _setCommonHeaders(request.response);
    request.response.headers.contentType = ContentType.json;
    request.response.write(const JsonEncoder.withIndent('  ').convert(body));
    await request.response.close();
  }

  void _setCommonHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set('Access-Control-Allow-Private-Network', 'true');
  }

  void _logInfo(String message) {
    _onLogInfo?.call(message);
  }

  void _logError(String message) {
    _onLogError?.call(message);
  }

  static Future<List<String>> _discoverLanIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    final results = <String>{};
    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
          continue;
        }
        final raw = address.address.trim();
        if (raw.isEmpty || raw == '0.0.0.0') {
          continue;
        }
        if (!_isRfc1918Ipv4(raw)) {
          continue;
        }
        results.add(raw);
      }
    }

    final sorted = results.toList(growable: false)..sort();
    return sorted;
  }

  static String? _normalizeWifiName(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static bool _isRfc1918Ipv4(String ip) {
    final segments = ip.split('.');
    if (segments.length != 4) {
      return false;
    }

    final numbers = segments
        .map((segment) => int.tryParse(segment))
        .toList(growable: false);
    if (numbers.any((value) => value == null || value < 0 || value > 255)) {
      return false;
    }

    final first = numbers[0]!;
    final second = numbers[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static Future<String?> _discoverWifiName() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('netsh', [
          'wlan',
          'show',
          'interfaces',
        ]);
        if (result.exitCode == 0) {
          return _parseNetshWifiName(result.stdout.toString());
        }
      } else if (Platform.isMacOS) {
        const airportPath =
            '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport';
        final result = await Process.run(airportPath, ['-I']);
        if (result.exitCode == 0) {
          return _parseColonDelimitedValue(result.stdout.toString(), 'SSID');
        }
      } else if (Platform.isLinux) {
        final nmcliResult = await Process.run('nmcli', [
          '-t',
          '-f',
          'active,ssid',
          'dev',
          'wifi',
        ]);
        if (nmcliResult.exitCode == 0) {
          final wifiName = _parseNmcliWifiName(nmcliResult.stdout.toString());
          if (wifiName != null) {
            return wifiName;
          }
        }

        final iwgetidResult = await Process.run('iwgetid', ['-r']);
        if (iwgetidResult.exitCode == 0) {
          return _normalizeWifiName(iwgetidResult.stdout.toString());
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _parseNetshWifiName(String output) {
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^\s*SSID\s*:\s*(.+)$').firstMatch(line);
      if (match == null) {
        continue;
      }
      return _normalizeWifiName(match.group(1));
    }
    return null;
  }

  static String? _parseColonDelimitedValue(String output, String key) {
    final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*:\\s*(.+)\$');
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = pattern.firstMatch(line);
      if (match == null) {
        continue;
      }
      return _normalizeWifiName(match.group(1));
    }
    return null;
  }

  static String? _parseNmcliWifiName(String output) {
    for (final line in output.split(RegExp(r'\r?\n'))) {
      if (!line.startsWith('yes:')) {
        continue;
      }
      return _normalizeWifiName(line.substring(4));
    }
    return null;
  }
}

class _LanFileShareEntry {
  _LanFileShareEntry({
    required this.shareKey,
    required this.token,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
    required this.expiresAt,
  });

  final String shareKey;
  final String token;
  final String filePath;
  final String fileName;
  final int fileSize;
  final DateTime createdAt;
  final DateTime expiresAt;
  int downloadCount = 0;
  DateTime? lastDownloadedAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
