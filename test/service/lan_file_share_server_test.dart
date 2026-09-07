import 'package:vertree/foundation/app_events.dart';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vertree/service/lan_file_share_server.dart';
import 'package:vertree/service/lan_share_payload_codec.dart';

void main() {
  group('LanFileShareServer', () {
    late Directory tempDir;
    late File file;
    late LanFileShareServer server;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vertree_share_test_');
      file = File('${tempDir.path}\\story.0.1.txt');
      await file.writeAsString('hello vertree');
      server = LanFileShareServer(
        events: AppEvents(),
        sharePageBaseUrl: 'https://vertree.w0fv1.dev/f',
        addressResolver: () async => ['192.168.10.8', '10.0.0.6'],
        wifiNameResolver: () async => 'Office WiFi',
      );
    });

    tearDown(() async {
      await server.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'createShare returns compact route link and shorter direct downloads',
      () async {
        final result = await server.createShare(
          file.path,
          expiresInMinutes: 15,
        );

        expect(result.isOk, isTrue);
        final share = result.unwrap();
        final sharePageUrl = share['sharePageUrl'] as String?;
        final shareCode = share['shareCode'] as String?;
        final shareKey = share['shareKey'] as String?;
        final directDownloads = share['directDownloads'] as List<dynamic>;
        final token = share['token'] as String;

        expect(share['fileName'], 'story.0.1.txt');
        expect(share['fileSize'], greaterThan(0));
        expect(share['networkName'], 'Office WiFi');
        expect(sharePageUrl, isNotNull);
        expect(shareCode, isNotNull);
        expect(shareKey, '1');
        expect(sharePageUrl, 'https://vertree.w0fv1.dev/f#$shareCode');

        final decodedCompactRoute = LanSharePayloadCodec.decodeCompactRoute(
          shareCode!,
        );
        expect(decodedCompactRoute['shareKey'], shareKey);
        expect(decodedCompactRoute['lanIps'], ['192.168.10.8', '10.0.0.6']);
        expect(shareCode, '01hxRistOgxdL');
        expect(
          sharePageUrl!.length,
          lessThanOrEqualTo((shareCode.length) + 30),
        );

        expect(directDownloads, hasLength(2));
        expect(
          (directDownloads.first as Map<String, dynamic>)['pageUrl'],
          'http://192.168.10.8:${server.port}/file-share/page/$shareKey',
        );
        expect(
          (directDownloads.first as Map<String, dynamic>)['infoUrl'],
          'http://192.168.10.8:${server.port}/file-share/info/$shareKey',
        );
        expect(
          (directDownloads.first as Map<String, dynamic>)['downloadUrl'],
          'http://192.168.10.8:${server.port}/file-share/download/$shareKey',
        );
        expect(
          ((directDownloads.first as Map<String, dynamic>)['downloadUrl']
                  as String)
              .length,
          lessThan(
            'http://192.168.10.8:${server.port}/file-share/download/$token'
                .length,
          ),
        );
      },
    );

    test('compact route uses optimal RFC1918 token lengths', () {
      final compactRoute = LanSharePayloadCodec.encodeCompactRoute(
        shareKey: 'z',
        lanIps: [
          '192.168.0.0',
          '192.168.255.255',
          '172.16.0.0',
          '10.0.0.0',
          '10.255.255.255',
        ],
      );

      expect(compactRoute, '0zFaCdleipq5iEQnM4bMocHX');

      final decoded = LanSharePayloadCodec.decodeCompactRoute(compactRoute);
      expect(decoded['shareKey'], 'z');
      expect(decoded['lanIps'], [
        '192.168.0.0',
        '192.168.255.255',
        '172.16.0.0',
        '10.0.0.0',
        '10.255.255.255',
      ]);
    });

    test('shareKey sequence uses Base62', () async {
      String? lastShareKey;
      for (var index = 0; index < 61; index += 1) {
        final created = await server.createShare(file.path);
        lastShareKey = created.unwrap()['shareKey'] as String;
      }

      expect(lastShareKey, 'z');
      final next = await server.createShare(file.path);
      expect(next.unwrap()['shareKey'], '10');
    });

    test('revokeShare removes the share from subsequent reads', () async {
      final created = await server.createShare(file.path);
      final token = created.unwrap()['token'] as String;
      final shareKey = created.unwrap()['shareKey'] as String;

      final revoke = server.revokeShare(shareKey);
      final afterRevoke = await server.getShare(token);

      expect(revoke.isOk, isTrue);
      expect(afterRevoke.isErr, isTrue);
    });
  });
}
