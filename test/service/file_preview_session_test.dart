import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/service/file_preview_session.dart';

void main() {
  late Directory directory;
  late File file;
  late HttpClient client;
  final sessions = <FilePreviewSession>[];

  Future<ByteData> loadAsset(String path) async {
    if (![
      'assets/office_viewer/index.html',
      'assets/office_viewer/assets/pdf.worker.min-test.mjs',
    ].contains(path)) {
      throw StateError('Missing asset');
    }
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode('bundled asset')),
    );
  }

  Future<FilePreviewSession> open() async {
    final session = await FilePreviewSession.open(
      file.path,
      loadAsset: loadAsset,
    );
    sessions.add(session);
    return session;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vertree-preview-');
    file = await File(
      '${directory.path}/中文 # review.0.1.txt',
    ).writeAsString('original 文本');
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  tearDown(() async {
    client.close(force: true);
    for (final session in sessions) {
      await session.close();
    }
    sessions.clear();
    await directory.delete(recursive: true);
  });

  test(
    'serves an immutable snapshot and Unicode metadata without exposing full path',
    () async {
      final session = await open();
      await file.writeAsString('changed');
      final response = await (await client.getUrl(
        session.uri.resolve('file'),
      )).close();
      expect(await utf8.decoder.bind(response).join(), 'original 文本');
      final metadata = await (await client.getUrl(
        session.uri.resolve('metadata'),
      )).close();
      final body = jsonDecode(await utf8.decoder.bind(metadata).join()) as Map;
      expect(body['name'], '中文 # review.0.1.txt');
      expect(body['path'], body['name']);
      expect(body['mime'], 'text/plain');
      expect(response.headers.value('cache-control'), 'no-store');
      expect(
        response.headers.value('content-security-policy'),
        contains("default-src 'none'"),
      );
      expect(
        response.headers.value('content-security-policy'),
        contains("media-src 'self' blob:"),
      );
    },
  );

  test(
    'rejects unknown tokens, cross-origin requests, writes and traversal',
    () async {
      final session = await open();
      for (final uri in [
        session.uri.resolve('/file'),
        session.uri.resolve('/wrong/file'),
      ]) {
        final response = await (await client.getUrl(uri)).close();
        expect(response.statusCode, HttpStatus.forbidden);
        await response.drain<void>();
      }
      final crossOrigin = await client.getUrl(session.uri.resolve('file'));
      crossOrigin.headers.set('Origin', 'https://example.com');
      expect((await crossOrigin.close()).statusCode, HttpStatus.forbidden);
      final badHost = await client.getUrl(session.uri.resolve('file'));
      badHost.headers.set('Host', 'attacker.example');
      expect((await badHost.close()).statusCode, HttpStatus.forbidden);
      final write = await client.postUrl(session.uri.resolve('file'));
      expect((await write.close()).statusCode, HttpStatus.methodNotAllowed);
      final traversal = await client.getUrl(
        Uri.parse('${session.uri}assets/%2e%2e%2ffile'),
      );
      expect((await traversal.close()).statusCode, HttpStatus.notFound);
      expect(await file.readAsString(), 'original 文本');
    },
  );

  test('serves worker MIME types, handles missing assets and HEAD', () async {
    final session = await open();
    final worker = await (await client.getUrl(
      session.uri.resolve('assets/pdf.worker.min-test.mjs'),
    )).close();
    expect(worker.headers.contentType?.mimeType, 'text/javascript');
    await worker.drain<void>();
    final missing = await (await client.getUrl(
      session.uri.resolve('assets/missing.js'),
    )).close();
    expect(missing.statusCode, 404);
    final head = await (await client.openUrl(
      'HEAD',
      session.uri.resolve('file'),
    )).close();
    expect(head.contentLength, await file.length());
    expect(await head.toList(), isEmpty);
  });

  test('rejects missing files and closes its listener', () async {
    final session = await open();
    await session.close();
    sessions.clear();
    await expectLater(
      client.getUrl(session.uri),
      throwsA(isA<SocketException>()),
    );
    await file.delete();
    await expectLater(open(), throwsA(isA<FileSystemException>()));
  });

  test(
    'accepts a file larger than 64 MiB and reads only its requested tail',
    () async {
      const length = 80 * 1024 * 1024;
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(length);
      await handle.setPosition(length - 4);
      await handle.writeFrom([1, 2, 3, 4]);
      await handle.close();
      final session = await open();
      final request = await client.getUrl(session.uri.resolve('file'));
      request.headers.set('Range', 'bytes=-4');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value('content-range'),
        'bytes ${length - 4}-${length - 1}/$length',
      );
      expect(response.contentLength, 4);
      expect(await response.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
    },
  );

  test(
    'supports seeking, clamped ranges and concurrent range requests',
    () async {
      await file.writeAsString('0123456789');
      final session = await open();
      await Future.wait([
        for (final entry in {
          'bytes=2-4': '234',
          'bytes=7-': '789',
          'bytes=8-99': '89',
          'bytes=-3': '789',
        }.entries)
          () async {
            final request = await client.getUrl(session.uri.resolve('file'));
            request.headers.set('Range', entry.key);
            final response = await request.close();
            expect(response.statusCode, HttpStatus.partialContent);
            expect(response.headers.value('accept-ranges'), 'bytes');
            expect(await utf8.decoder.bind(response).join(), entry.value);
          }(),
      ]);
      for (final range in ['bytes=10-', 'bytes=5-2', 'bytes=-0']) {
        final request = await client.getUrl(session.uri.resolve('file'));
        request.headers.set('Range', range);
        final response = await request.close();
        expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
        expect(response.headers.value('content-range'), 'bytes */10');
        await response.drain<void>();
      }
    },
  );

  test(
    'HEAD and malformed ranges return the complete representation headers',
    () async {
      final session = await open();
      for (final range in ['bytes=0-1,3-4', 'nonsense']) {
        final request = await client.getUrl(session.uri.resolve('file'));
        request.headers.set('Range', range);
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(response.contentLength, await file.length());
        await response.drain<void>();
      }
      final request = await client.openUrl('HEAD', session.uri.resolve('file'));
      request.headers.set('Range', 'bytes=0-1');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, await file.length());
      expect(await response.toList(), isEmpty);
    },
  );

  test(
    'empty files and stale If-Range validators are handled correctly',
    () async {
      await file.writeAsString('');
      final empty = await open();
      final request = await client.getUrl(empty.uri.resolve('file'));
      request.headers.set('Range', 'bytes=0-');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      await response.drain<void>();
      await file.writeAsString('full content');
      final session = await open();
      final stale = await client.getUrl(session.uri.resolve('file'));
      stale.headers.set('Range', 'bytes=0-1');
      stale.headers.set('If-Range', '"old-version"');
      final full = await stale.close();
      expect(full.statusCode, HttpStatus.ok);
      expect(await utf8.decoder.bind(full).join(), 'full content');
      await session.close();
      await session.close();
    },
  );
}
