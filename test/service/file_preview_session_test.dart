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
        contains('media-src blob:'),
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

  test('rejects missing and oversized files and closes its listener', () async {
    final session = await open();
    await session.close();
    sessions.clear();
    await expectLater(
      client.getUrl(session.uri),
      throwsA(isA<SocketException>()),
    );
    await file.delete();
    await expectLater(open(), throwsA(isA<FileSystemException>()));
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(FilePreviewSession.maxFileBytes + 1);
    await handle.close();
    await expectLater(open(), throwsA(isA<FileSystemException>()));
  });
}
