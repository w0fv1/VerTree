import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'file_preview_session.dart';
import 'preview_webview_environment.dart';
import 'chromium_preview_renderer.dart';
import '../foundation/operation_failure.dart';

class PreviewImageRequest {
  PreviewImageRequest.fromJson(Map<String, dynamic> json)
    : path = json['path'] as String? ?? '',
      width = (json['width'] as num?)?.toDouble() ?? 1200,
      height = (json['height'] as num?)?.toDouble() ?? 1600,
      page = (json['page'] as num?)?.toDouble() ?? 1,
      timeSeconds = (json['timeSeconds'] as num?)?.toDouble() ?? 0 {
    if (!p.isAbsolute(path) ||
        [
          width,
          height,
          page,
        ].any((n) => !n.isFinite || n < 1 || n != n.truncateToDouble()) ||
        width > 4096 ||
        height > 4096 ||
        !timeSeconds.isFinite ||
        timeSeconds < 0) {
      throw const FormatException(
        'Expected an absolute file path, dimensions 1–4096, positive integer page and nonnegative timeSeconds',
      );
    }
  }
  final String path;
  final double width, height, page, timeSeconds;
  Map<String, dynamic> get options => {
    'width': width,
    'height': height,
    'page': page,
    'timeSeconds': timeSeconds,
  };
}

class PreviewRenderException extends OperationFailure {
  const PreviewRenderException(super.code, super.message);
}

class FilePreviewImageService {
  bool _busy = false;

  static Future<bool> available() async =>
      Platform.isWindows ||
      Platform.isMacOS ||
      (Platform.isLinux && await ChromiumPreviewRenderer.executable() != null);
  Future<Uint8List> render(PreviewImageRequest request) async {
    final bytes = base64Decode(await _execute(request, 'render') as String);
    const magic = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8 ||
        List.generate(
          8,
          (index) => bytes[index] == magic[index],
        ).contains(false)) {
      throw PreviewRenderException('RENDER_FAILED', 'Invalid PNG response');
    }
    return bytes;
  }

  Future<Map<String, dynamic>> inspect(String path) async =>
      Map<String, dynamic>.from(
        await _execute(PreviewImageRequest.fromJson({'path': path}), 'inspect')
            as Map,
      );
  Future<Object?> _execute(PreviewImageRequest request, String method) async {
    if (_busy) {
      throw PreviewRenderException(
        'RENDER_BUSY',
        'Another preview image is being rendered',
      );
    }
    _busy = true;
    FilePreviewSession? session;
    HeadlessInAppWebView? view;
    try {
      session = await FilePreviewSession.open(request.path);
      final script =
          'try { return {data: await window.officePreviewImages.$method(options)}; } catch(error) { return {error: {code: error.code || "RENDER_FAILED", message: error.message || String(error)}}; }';
      late Map value;
      if (Platform.isLinux) {
        value = await ChromiumPreviewRenderer.execute(
          session.uri.replace(query: 'image=1'),
          '(async () => { const options = ${jsonEncode(request.options)}; $script })()',
        );
      } else {
        final loaded = Completer<InAppWebViewController>();
        view = HeadlessInAppWebView(
          initialSize: Size(request.width, request.height),
          webViewEnvironment: Platform.isWindows
              ? await PreviewWebViewEnvironment.shared
              : null,
          initialUrlRequest: URLRequest(
            url: WebUri.uri(session.uri.replace(query: 'image=1')),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            isInspectable: false,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
          ),
          onPermissionRequest: (_, request) async => PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.DENY,
          ),
          onLoadStop: (controller, url) {
            if (!loaded.isCompleted) loaded.complete(controller);
          },
          onReceivedError: (controller, resource, error) {
            if (resource.isForMainFrame == true && !loaded.isCompleted) {
              loaded.completeError(StateError(error.description));
            }
          },
        );
        await view.run();
        final controller = await loaded.future.timeout(
          const Duration(seconds: 15),
        );
        final result = await controller
            .callAsyncJavaScript(
              functionBody: script,
              arguments: {'options': request.options},
            )
            .timeout(const Duration(seconds: 35));
        final returned = result?.value;
        if (result?.error != null || returned is! Map) {
          throw StateError(
            result?.error ?? 'RENDER_FAILED: empty rendering result',
          );
        }
        value = returned;
      }
      if (value['error'] is Map) {
        final error = value['error'] as Map;
        throw PreviewRenderException(
          error['code'] as String,
          error['message'] as String,
        );
      }
      return value['data'];
    } finally {
      try {
        await view?.dispose();
      } finally {
        try {
          await session?.close();
        } finally {
          _busy = false;
        }
      }
    }
  }
}
