import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

/// A disk-backed snapshot, served only for the lifetime of its preview dialog.
class FilePreviewSession {
  FilePreviewSession._(this._server, this._directory, String token)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/$token/');

  final HttpServer _server;
  final Directory _directory;
  final _requests = <Future<void>>{};
  Future<void>? _closing;
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
    final directory = await Directory.systemTemp.createTemp('vertree-preview-');
    HttpServer? server;
    try {
      final snapshot = await file.copy(p.join(directory.path, 'snapshot'));
      final size = await snapshot.length();
      final handle = await snapshot.open();
      late List<int> header;
      try {
        header = await handle.read(32);
      } finally {
        await handle.close();
      }
      final mime =
          lookupMimeType(path, headerBytes: header) ??
          'application/octet-stream';
      final token = base64Url.encode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final session = FilePreviewSession._(server, directory, token);
      final metadata = utf8.encode(
        jsonEncode({
          'path': p.basename(path),
          'name': p.basename(path),
          'size': size,
          'mime': mime,
          'modified': stat.modified.millisecondsSinceEpoch ~/ 1000,
        }),
      );
      Future<void> serve(HttpRequest request) async {
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
                "worker-src 'self' blob:; frame-src 'self' blob:; media-src 'self' blob:; object-src 'none'; "
                "base-uri 'none'; form-action 'none'; frame-ancestors 'self'",
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
              await _serveFile(request, snapshot, size, mime, '"$token"');
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
          try {
            response.statusCode = HttpStatus.internalServerError;
          } catch (_) {
            // A disconnected client may already have received its headers.
          }
        } finally {
          try {
            await response.close();
          } catch (_) {
            // Closing the preview can cancel an in-flight asset response.
          }
        }
      }

      server.listen((request) {
        final pending = serve(request);
        session._requests.add(pending);
        unawaited(
          pending.whenComplete(() => session._requests.remove(pending)),
        );
      });
      return session;
    } catch (_) {
      await server?.close(force: true);
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  static Future<void> _serveFile(
    HttpRequest request,
    File file,
    int size,
    String mime,
    String etag,
  ) async {
    final response = request.response;
    response.headers
      ..contentType = ContentType.parse(mime)
      ..set('Accept-Ranges', 'bytes')
      ..set('ETag', etag);
    var start = 0;
    var end = size;
    final range = request.headers.value('range');
    final ifRange = request.headers.value('if-range');
    if (request.method == 'GET' &&
        range != null &&
        (ifRange == null || ifRange == etag)) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (match != null && (match[1]!.isNotEmpty || match[2]!.isNotEmpty)) {
        final first = int.tryParse(match[1]!);
        final last = int.tryParse(match[2]!);
        if (match[1]!.isEmpty) {
          start = size - min(last ?? size, size);
        } else {
          start = first ?? size;
          end = last == null ? size : min(last, size - 1) + 1;
        }
        if (start >= size || start >= end) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set('Content-Range', 'bytes */$size');
          response.contentLength = 0;
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set('Content-Range', 'bytes $start-${end - 1}/$size');
      }
    }
    response.contentLength = end - start;
    if (request.method == 'GET' && end > start) {
      await response.addStream(file.openRead(start, end));
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await _server.close(force: true);
    await Future.wait(_requests.toList());
    await _directory.delete(recursive: true);
  }
}
