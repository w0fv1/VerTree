import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vertree/core/result.dart';

class AppVersionInfo {
  final String currentVersion;
  final String releaseApiUrl;
  final Future<http.Response> Function(Uri uri) _httpGet;
  final String Function(String key, String defaultValue)? _readConfigString;
  final void Function(String key, String value)? _writeConfigString;
  final void Function(String message)? _onLogInfo;
  final void Function(String message)? _onLogError;

  static const String _lastUpdateCheckKey = 'lastUpdateCheckDate';
  List<Map<String, dynamic>>? _cachedReleaseFeed;
  String? _cachedReleaseDate;

  AppVersionInfo({
    required this.currentVersion,
    required this.releaseApiUrl,
    Future<http.Response> Function(Uri uri)? httpGet,
    String Function(String key, String defaultValue)? readConfigString,
    void Function(String key, String value)? writeConfigString,
    void Function(String message)? onLogInfo,
    void Function(String message)? onLogError,
  }) : _httpGet = httpGet ?? http.get,
       _readConfigString = readConfigString,
       _writeConfigString = writeConfigString,
       _onLogInfo = onLogInfo,
       _onLogError = onLogError;

  factory AppVersionInfo.fromPackageVersion({
    required String packageVersion,
    required String releaseApiUrl,
    Future<http.Response> Function(Uri uri)? httpGet,
    String Function(String key, String defaultValue)? readConfigString,
    void Function(String key, String value)? writeConfigString,
    void Function(String message)? onLogInfo,
    void Function(String message)? onLogError,
  }) {
    return AppVersionInfo(
      currentVersion: 'V$packageVersion',
      releaseApiUrl: releaseApiUrl,
      httpGet: httpGet,
      readConfigString: readConfigString,
      writeConfigString: writeConfigString,
      onLogInfo: onLogInfo,
      onLogError: onLogError,
    );
  }

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isSkipTodayError(String? msg) {
    return msg != null && msg.startsWith('今日已检查更新');
  }

  String _readStoredCheckDate() {
    return _readConfigString?.call(_lastUpdateCheckKey, '') ?? '';
  }

  void _writeStoredCheckDate(String value) {
    _writeConfigString?.call(_lastUpdateCheckKey, value);
  }

  void _logInfo(String message) {
    _onLogInfo?.call(message);
  }

  void _logError(String message) {
    _onLogError?.call(message);
  }

  static int compareVersions(String version1, String version2) {
    return _VersionIdentifier.parse(
      version1,
    ).compareTo(_VersionIdentifier.parse(version2));
  }

  Future<Result<List<Map<String, dynamic>>, String>> _fetchReleaseFeed() async {
    final today = _todayKey();
    if (_cachedReleaseFeed != null && _cachedReleaseDate == today) {
      return Result.ok(List<Map<String, dynamic>>.from(_cachedReleaseFeed!));
    }

    final lastCheck = _readStoredCheckDate();
    if (lastCheck == today) {
      return Result.err('今日已检查更新，跳过网络请求');
    }

    try {
      _logInfo('正在从 $releaseApiUrl 获取版本信息...');
      final response = await _httpGet(Uri.parse(releaseApiUrl));
      if (response.statusCode != 200) {
        _logInfo('获取版本信息失败，HTTP 状态码: ${response.statusCode}');
        _logInfo('响应体: ${response.body}');
        return Result.err('HTTP 请求失败，状态码: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final releases = <Map<String, dynamic>>[];
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            releases.add(item);
          } else if (item is Map) {
            releases.add(Map<String, dynamic>.from(item));
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        releases.add(decoded);
      } else if (decoded is Map) {
        releases.add(Map<String, dynamic>.from(decoded));
      } else {
        return Result.err('GitHub Release API 响应格式不正确');
      }

      _cachedReleaseFeed = releases;
      _cachedReleaseDate = today;
      _writeStoredCheckDate(today);
      return Result.ok(List<Map<String, dynamic>>.from(releases));
    } catch (e, stackTrace) {
      _logError('获取版本信息时发生异常: $e');
      _logError('堆栈跟踪: $stackTrace');
      return Result.err('获取版本信息时发生异常: $e');
    }
  }

  Future<Result<_ReleaseCandidate?, String>> _resolveNewestRelease() async {
    final releaseFeedResult = await _fetchReleaseFeed();
    if (releaseFeedResult.isErr) {
      if (_isSkipTodayError(releaseFeedResult.msg)) {
        return Result.ok(null);
      }
      return Result.err(releaseFeedResult.msg);
    }

    final current = _VersionIdentifier.parse(currentVersion);
    final allowPrerelease = current.isPrerelease;
    final candidates = <_ReleaseCandidate>[];

    for (final release in releaseFeedResult.unwrap()) {
      if (release['draft'] == true) {
        continue;
      }

      final tagName = release['tag_name'];
      if (tagName is! String || tagName.trim().isEmpty) {
        continue;
      }

      final version = _VersionIdentifier.parse(tagName);
      final isPrerelease =
          release['prerelease'] == true || version.isPrerelease;
      if (!allowPrerelease && isPrerelease) {
        continue;
      }

      candidates.add(
        _ReleaseCandidate(tagName: tagName, version: version, release: release),
      );
    }

    if (candidates.isEmpty) {
      return Result.ok(null);
    }

    candidates.sort((a, b) => b.version.compareTo(a.version));
    return Result.ok(candidates.first);
  }

  Future<Result<UpdateInfo, String>> checkUpdate() async {
    final releaseResult = await _resolveNewestRelease();
    if (releaseResult.isErr) {
      _logInfo('未能获取最新版本信息，无法检查更新。错误信息: ${releaseResult.msg}');
      return Result.err(releaseResult.msg);
    }

    final candidate = releaseResult.unwrap();
    if (candidate == null) {
      return Result.ok(UpdateInfo(hasUpdate: false));
    }

    final comparisonResult = candidate.version.compareTo(
      _VersionIdentifier.parse(currentVersion),
    );
    if (comparisonResult <= 0) {
      _logInfo('当前版本 ($currentVersion) 已是最新。');
      return Result.ok(UpdateInfo(hasUpdate: false));
    }

    final preferredAsset = selectPreferredAsset(candidate.release);
    return Result.ok(
      UpdateInfo(
        hasUpdate: true,
        latestVersionTag: candidate.tagName,
        latestHtmlUrl: candidate.release['html_url'] as String?,
        downloadUrl:
            preferredAsset?.downloadUrl ??
            candidate.release['html_url'] as String?,
        downloadAssetName: preferredAsset?.name,
      ),
    );
  }

  Future<Result<String?, String>> getLatestVersionTag() async {
    final releaseResult = await _resolveNewestRelease();
    if (releaseResult.isErr) {
      if (_isSkipTodayError(releaseResult.msg)) {
        return Result.ok(null);
      }
      return Result.err(releaseResult.msg);
    }
    return Result.ok(releaseResult.unwrap()?.tagName);
  }

  Future<Result<String?, String>> getLatestReleaseUrl() async {
    final releaseResult = await _resolveNewestRelease();
    if (releaseResult.isErr) {
      if (_isSkipTodayError(releaseResult.msg)) {
        return Result.ok(null);
      }
      return Result.err(releaseResult.msg);
    }
    return Result.ok(releaseResult.unwrap()?.release['html_url'] as String?);
  }

  Future<Result<String?, String>> getPreferredDownloadUrl() async {
    final releaseResult = await _resolveNewestRelease();
    if (releaseResult.isErr) {
      if (_isSkipTodayError(releaseResult.msg)) {
        return Result.ok(null);
      }
      return Result.err(releaseResult.msg);
    }

    final release = releaseResult.unwrap()?.release;
    if (release == null) {
      return Result.ok(null);
    }

    final asset = selectPreferredAsset(release);
    return Result.ok(asset?.downloadUrl ?? release['html_url'] as String?);
  }

  static ReleaseAssetInfo? selectPreferredAsset(
    Map<String, dynamic> releaseInfo, {
    String? platformOverride,
    String? linuxOsReleaseOverride,
  }) {
    final rawAssets = releaseInfo['assets'];
    if (rawAssets is! List) {
      return null;
    }

    final assets = <Map<String, dynamic>>[];
    for (final asset in rawAssets) {
      if (asset is Map<String, dynamic>) {
        assets.add(asset);
      } else if (asset is Map) {
        assets.add(Map<String, dynamic>.from(asset));
      }
    }

    if (assets.isEmpty) {
      return null;
    }

    final platform = _resolvePlatform(platformOverride);
    final linuxOsRelease = linuxOsReleaseOverride ?? _readLinuxOsRelease();

    Map<String, dynamic>? bestAsset;
    var bestScore = -1;

    for (final asset in assets) {
      final score = _scoreAsset(
        asset,
        platform: platform,
        linuxOsRelease: linuxOsRelease,
      );
      if (score > bestScore) {
        bestScore = score;
        bestAsset = asset;
      }
    }

    if (bestAsset == null || bestScore < 0) {
      return null;
    }

    final name = bestAsset['name'];
    final url = bestAsset['browser_download_url'];
    if (name is! String || url is! String || name.isEmpty || url.isEmpty) {
      return null;
    }
    return ReleaseAssetInfo(name: name, downloadUrl: url);
  }

  static String _resolvePlatform(String? override) {
    if (override != null && override.trim().isNotEmpty) {
      return override.trim().toLowerCase();
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    return 'other';
  }

  static String? _readLinuxOsRelease() {
    if (!Platform.isLinux) {
      return null;
    }
    try {
      final file = File('/etc/os-release');
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    } catch (_) {}
    return null;
  }

  static int _scoreAsset(
    Map<String, dynamic> asset, {
    required String platform,
    required String? linuxOsRelease,
  }) {
    final rawName = asset['name'];
    if (rawName is! String || rawName.trim().isEmpty) {
      return -1;
    }

    final name = rawName.toLowerCase();
    if (_isDeveloperOnlyArtifact(name)) {
      return -1;
    }
    final containsWindows = name.contains('windows') || name.contains('win');
    final containsMac =
        name.contains('macos') || name.contains('mac') || name.contains('dmg');
    final containsLinux =
        name.contains('linux') || name.contains('rpm') || name.endsWith('.deb');

    if (platform == 'windows') {
      if (name.endsWith('.exe')) {
        return 100 +
            (containsWindows ? 10 : 0) +
            (name.contains('setup') ? 6 : 0);
      }
      if (name.endsWith('.msi')) {
        return 96 + (containsWindows ? 10 : 0);
      }
      if (name.endsWith('.zip')) {
        return 70 + (containsWindows ? 12 : 0);
      }
      return -1;
    }

    if (platform == 'macos') {
      if (name.endsWith('.dmg')) {
        return 100 + (containsMac ? 10 : 0);
      }
      if (name.endsWith('.zip')) {
        return 82 + (containsMac ? 10 : 0);
      }
      return -1;
    }

    if (platform == 'linux') {
      final preferRpm = _preferRpmPackage(linuxOsRelease);
      final preferDeb = _preferDebPackage(linuxOsRelease);
      if (name.endsWith('.deb')) {
        return (preferDeb ? 100 : 80) + (containsLinux ? 10 : 0);
      }
      if (name.endsWith('.rpm')) {
        return (preferRpm ? 100 : (preferDeb ? 72 : 84)) +
            (containsLinux ? 10 : 0);
      }
      if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
        return (preferRpm ? 86 : (preferDeb ? 88 : 100)) +
            (containsLinux ? 10 : 0);
      }
      return -1;
    }

    if (name.endsWith('.zip') ||
        name.endsWith('.tar.gz') ||
        name.endsWith('.tgz') ||
        name.endsWith('.dmg') ||
        name.endsWith('.exe') ||
        name.endsWith('.msi') ||
        name.endsWith('.rpm') ||
        name.endsWith('.deb')) {
      return 1;
    }
    return -1;
  }

  static bool _isDeveloperOnlyArtifact(String name) {
    return name.contains('symbols') ||
        name.contains('dsym') ||
        name.contains('sha256') ||
        name.contains('checksums') ||
        name.contains('win11-dev') ||
        name.endsWith('.msix');
  }

  static bool _preferRpmPackage(String? linuxOsRelease) {
    if (linuxOsRelease == null || linuxOsRelease.trim().isEmpty) {
      return false;
    }
    final normalized = linuxOsRelease.toLowerCase();
    return normalized.contains('fedora') ||
        normalized.contains('rhel') ||
        normalized.contains('centos') ||
        normalized.contains('rocky') ||
        normalized.contains('almalinux') ||
        normalized.contains('opensuse') ||
        normalized.contains('sles') ||
        normalized.contains('suse');
  }

  static bool _preferDebPackage(String? linuxOsRelease) {
    if (linuxOsRelease == null || linuxOsRelease.trim().isEmpty) {
      return false;
    }
    final normalized = linuxOsRelease.toLowerCase();
    return normalized.contains('ubuntu') ||
        normalized.contains('debian') ||
        normalized.contains('mint') ||
        normalized.contains('pop') ||
        normalized.contains('elementary') ||
        normalized.contains('kali') ||
        normalized.contains('zorin') ||
        normalized.contains('raspbian');
  }
}

class UpdateInfo {
  final bool hasUpdate;
  final String? latestVersionTag;
  final String? latestHtmlUrl;
  final String? downloadUrl;
  final String? downloadAssetName;

  UpdateInfo({
    required this.hasUpdate,
    this.latestVersionTag,
    this.latestHtmlUrl,
    this.downloadUrl,
    this.downloadAssetName,
  });
}

class ReleaseAssetInfo {
  final String name;
  final String downloadUrl;

  const ReleaseAssetInfo({required this.name, required this.downloadUrl});
}

class _ReleaseCandidate {
  final String tagName;
  final _VersionIdentifier version;
  final Map<String, dynamic> release;

  const _ReleaseCandidate({
    required this.tagName,
    required this.version,
    required this.release,
  });
}

class _VersionIdentifier implements Comparable<_VersionIdentifier> {
  final List<int> core;
  final List<_PrereleasePart> prerelease;

  const _VersionIdentifier({required this.core, required this.prerelease});

  bool get isPrerelease => prerelease.isNotEmpty;

  static _VersionIdentifier parse(String raw) {
    final normalized = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final withoutBuild = normalized.split('+').first;
    final dashIndex = withoutBuild.indexOf('-');
    final coreText = dashIndex == -1
        ? withoutBuild
        : withoutBuild.substring(0, dashIndex);
    final prereleaseText = dashIndex == -1
        ? ''
        : withoutBuild.substring(dashIndex + 1);

    final core = coreText
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
    final prerelease = _parsePrerelease(prereleaseText);
    return _VersionIdentifier(core: core, prerelease: prerelease);
  }

  static List<_PrereleasePart> _parsePrerelease(String text) {
    if (text.trim().isEmpty) {
      return const [];
    }

    final parts = <_PrereleasePart>[];
    for (final segment in text.split('.')) {
      final matches = RegExp(r'[A-Za-z-]+|\d+').allMatches(segment);
      if (matches.isEmpty) {
        parts.add(_PrereleasePart.text(segment.toLowerCase()));
        continue;
      }
      for (final match in matches) {
        final token = match.group(0) ?? '';
        final number = int.tryParse(token);
        if (number != null) {
          parts.add(_PrereleasePart.number(number));
        } else {
          parts.add(_PrereleasePart.text(token.toLowerCase()));
        }
      }
    }
    return parts;
  }

  @override
  int compareTo(_VersionIdentifier other) {
    final length = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var index = 0; index < length; index++) {
      final left = index < core.length ? core[index] : 0;
      final right = index < other.core.length ? other.core[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }

    if (!isPrerelease && !other.isPrerelease) {
      return 0;
    }
    if (!isPrerelease) {
      return 1;
    }
    if (!other.isPrerelease) {
      return -1;
    }

    final prereleaseLength = prerelease.length > other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < prereleaseLength; index++) {
      if (index >= prerelease.length) {
        return -1;
      }
      if (index >= other.prerelease.length) {
        return 1;
      }
      final comparison = prerelease[index].compareTo(other.prerelease[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }
}

class _PrereleasePart implements Comparable<_PrereleasePart> {
  final int? numberValue;
  final String? textValue;

  const _PrereleasePart.number(this.numberValue) : textValue = null;
  const _PrereleasePart.text(this.textValue) : numberValue = null;

  bool get isNumeric => numberValue != null;

  @override
  int compareTo(_PrereleasePart other) {
    if (isNumeric && other.isNumeric) {
      return numberValue!.compareTo(other.numberValue!);
    }
    if (isNumeric && !other.isNumeric) {
      return -1;
    }
    if (!isNumeric && other.isNumeric) {
      return 1;
    }
    return textValue!.compareTo(other.textValue!);
  }
}
