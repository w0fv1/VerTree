import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

/// A read-only snapshot, served only for the lifetime of its preview dialog.
class FilePreviewSession {
  FilePreviewSession._(this._server, String token)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/$token/');

  static const maxFileBytes = 64 * 1024 * 1024;
  final HttpServer _server;
  final Uri uri;

  static Future<FilePreviewSession> open(
    String path, {
    Future<ByteData> Function(String)? loadAsset,
  }) async {
    final loader = loadAsset ?? rootBundle.load;
    await loader('assets/office_viewer/index.html');
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FileSystemException(
        'File does not exist or is not a regular file',
      );
    }
    if (stat.size > maxFileBytes) {
      throw const FileSystemException('Preview supports files up to 64 MiB');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (builder.length + chunk.length > maxFileBytes) {
        throw const FileSystemException('Preview supports files up to 64 MiB');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final token = base64Url.encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final session = FilePreviewSession._(server, token);
    final metadata = utf8.encode(
      jsonEncode({
        'path': p.basename(path),
        'name': p.basename(path),
        'size': bytes.length,
        'mime':
            lookupMimeType(path, headerBytes: bytes.take(32).toList()) ??
            'application/octet-stream',
        'modified': stat.modified.millisecondsSinceEpoch ~/ 1000,
      }),
    );
    server.listen((request) async {
      final response = request.response;
      response.headers
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Referrer-Policy', 'no-referrer')
        ..set(
          'Content-Security-Policy',
          "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; "
              "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
              "font-src 'self' data: blob:; connect-src 'self' blob:; "
              "worker-src 'self' blob:; frame-src blob:; media-src blob:; object-src 'none'; "
              "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        );
      try {
        final origin = request.headers.value('origin');
        final segments = request.uri.pathSegments;
        if (request.headers.value('host') != session.uri.authority ||
            (origin != null && origin != session.uri.origin) ||
            request.headers.value('sec-fetch-site') == 'cross-site' ||
            segments.isEmpty ||
            segments.first != token) {
          response.statusCode = HttpStatus.forbidden;
        } else if (request.method != 'GET' && request.method != 'HEAD') {
          response.statusCode = HttpStatus.methodNotAllowed;
        } else {
          final resource = segments.skip(1).join('/');
          List<int>? body;
          if (resource == 'metadata') {
            response.headers.contentType = ContentType.json;
            body = metadata;
          } else if (resource == 'file') {
            response.headers.contentType = ContentType.binary;
            body = bytes;
          } else if (resource.isEmpty ||
              resource == 'index.html' ||
              RegExp(
                r'^assets/[a-zA-Z0-9_.-]+\.(js|mjs|css|wasm|png|svg|woff2?)$',
              ).hasMatch(resource)) {
            final asset = resource.isEmpty ? 'index.html' : resource;
            try {
              final data = await loader('assets/office_viewer/$asset');
              body = data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              );
              final extension = p.extension(asset);
              response.headers.contentType = switch (extension) {
                '.html' => ContentType.html,
                '.js' || '.mjs' => ContentType('text', 'javascript'),
                '.css' => ContentType('text', 'css'),
                '.wasm' => ContentType('application', 'wasm'),
                '.png' => ContentType('image', 'png'),
                '.svg' => ContentType('image', 'svg+xml'),
                _ => ContentType.binary,
              };
            } catch (_) {
              response.statusCode = HttpStatus.notFound;
            }
          } else {
            response.statusCode = HttpStatus.notFound;
          }
          if (body != null) {
            response.contentLength = body.length;
            if (request.method == 'GET') response.add(body);
          }
        }
      } catch (_) {
        response.statusCode = HttpStatus.internalServerError;
      } finally {
        try {
          await response.close();
        } on IOException {
          // Closing the preview can cancel an in-flight asset response.
        }
      }
    });
    return session;
  }

  Future<void> close() => _server.close(force: true);
}
