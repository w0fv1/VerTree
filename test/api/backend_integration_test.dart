import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vertree/app/composition_root.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/foundation/app_events.dart';
import 'package:vertree/service/lan_file_share_server.dart';
import 'package:vertree/service/local_http_api_service.dart';

void main() {
  test(
    'HTTP uses the shared backend and exposes only the new version and snapshot contracts',
    () async {
      final directory = await Directory.systemTemp.createTemp('vertree-api-');
      final config = Configer(directoryResolver: () async => directory);
      await config.init();
      final events = AppEvents();
      final backend = AppBackend(config: config, events: events);
      await backend.monitors.init();
      final sharing = LanFileShareServer(events: events);
      final service = LocalHttpApiService(
        configer: config,
        versions: backend.versions,
        comparator: backend.comparator,
        catalog: backend.catalog,
        monitManager: backend.monitors,
        lanFileShareServer: sharing,
        currentVersion: 'test',
        startedAt: DateTime.now(),
        currentPortResolver: () => null,
        currentUiStateResolver: () => {},
        navigateUiHandler:
            ({
              required page,
              path,
              waitMilliseconds = 0,
              ensureWindowVisible = false,
              windowMode,
              windowWidth,
              windowHeight,
              showInitialSetupDialog = false,
              fileTreeScale,
              fitFileTreeToViewport = false,
            }) => throw UnimplementedError(),
        captureUiScreenshotHandler:
            ({
              required outputPath,
              pixelRatio = 1,
              waitMilliseconds = 0,
              ensureWindowVisible = false,
            }) => throw UnimplementedError(),
        setWindowStateHandler: ({mode = '', width, height, focus = false}) =>
            throw UnimplementedError(),
        setThemeModeHandler: (_) => throw UnimplementedError(),
        setFileTreeViewportHandler: ({scale, fitToViewport = false}) =>
            throw UnimplementedError(),
        quitAppHandler: () async {},
      );
      final server = LocalHttpApiServer(
        apiService: service,
        accessToken: 'test-token',
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      await server.start();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await backend.monitors.dispose();
        await backend.writes.close();
        await sharing.dispose();
        await config.dispose();
        await events.dispose();
        await directory.delete(recursive: true);
      });
      Future<(int, Map<String, dynamic>)> request(
        String method,
        String route, [
        Object? body,
      ]) async {
        final request = await client.openUrl(
          method,
          Uri.parse('${server.baseUrl}$route'),
        );
        request.headers.set('Authorization', 'Bearer test-token');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final data =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        return (response.statusCode, data);
      }

      final source = await File(
        p.join(directory.path, 'report.txt'),
      ).writeAsString('original');
      final created = await request('POST', '/versions', {
        'path': source.path,
        'label': 'review',
      });
      expect(created.$1, 201);
      final versionPath = created.$2['data']['backup']['path'] as String;
      expect(await File(versionPath).readAsString(), 'original');
      final query = '?path=${Uri.encodeQueryComponent(source.path)}';
      final versions = await request('GET', '/versions$query');
      expect(versions.$2['data']['count'], 2);
      final graph = await request('GET', '/version-trees$query');
      expect(graph.$2['data']['entries'], hasLength(2));
      expect(graph.$2['data']['parents'][versionPath], source.path);
      final invalid = await request('POST', '/versions', {
        'path': source.path,
        'label': '../bad',
      });
      expect(invalid.$1, 400);
      expect(invalid.$2['code'], 'INVALID_LABEL');
      expect(
        (await request('POST', '/backups', {'path': source.path})).$1,
        404,
      );
      expect((await request('GET', '/version-files$query')).$1, 404);
      expect(
        (await request('POST', '/versions', {'path': 'x' * (1024 * 1024)})).$1,
        413,
      );

      final task = await request('POST', '/monitor-tasks', {
        'path': source.path,
      });
      expect(task.$1, 201);
      final id = task.$2['data']['id'] as String;
      expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(task.$2['data']['enabled'], isTrue);
      final stopped = await request('PATCH', '/monitor-tasks/$id', {
        'enabled': false,
      });
      expect(stopped.$1, 200);
      final snapshot = await backend.snapshots.create(source.path, id, keep: 2);
      final listed = await request('GET', '/snapshots$query');
      expect(listed.$2['data']['count'], 1);
      expect(listed.$2['data']['items'][0]['snapshotId'], snapshot.id);
      expect(
        (await request(
          'GET',
          '/monitor-tasks/$id/snapshots',
        )).$2['data']['count'],
        1,
      );
    },
  );
}
