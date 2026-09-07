import 'package:vertree/modules/automation/automation.dart';
import 'package:vertree/modules/preview/preview.dart';
import 'package:vertree/service/file_preview_image_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/api/extended_automation_api.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/service/local_http_api_service.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/foundation/app_events.dart';
import 'package:vertree/modules/versions/versions.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/file_access/infrastructure/local_file_access.dart';

class _Service implements LocalHttpApiService {
  @override
  final versions = VersionCommands(
    files: LocalFileAccess(),
    writes: FileMutationCoordinator(),
    emit: AppEvents().emit,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'SSE promptly replays and streams events while other requests remain available',
    () async {
      final events = AppEvents();
      final api = ExtendedAutomationApi(
        events: events,
        preview: PreviewActivity(events),
        jobs: AutomationJobs(events),
        images: FilePreviewImageService(),
        service: _Service(),
        config: Configer(),
        openPreview: (_) async {},
        closePreview: () async {},
        diagnostics: () => {},
      );
      final server = LocalHttpApiServer(
        apiService: _Service(),
        accessToken: 'test-token',
        onLogInfo: (_) {},
        onLogError: (_) {},
        additionalRoutes: api.routes,
      );
      final client = HttpClient();
      await server.start();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
      });
      final cursor = events.lastId;
      events.emit('test.replay', {});
      final request = await client.getUrl(
        Uri.parse('${server.baseUrl}/events'),
      );
      request.headers.set('Authorization', 'Bearer test-token');
      request.headers.set('Last-Event-ID', '${events.sessionId}:$cursor');
      final response = await request.close();
      expect(response.statusCode, 200);
      final replay = Completer<void>(), live = Completer<void>();
      final subscription = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line == 'event: test.replay' && !replay.isCompleted) {
              replay.complete();
            }
            if (line == 'event: test.live' && !live.isCompleted) {
              live.complete();
            }
          });
      await replay.future.timeout(const Duration(seconds: 2));
      events.emit('test.live', {});
      await live.future.timeout(const Duration(seconds: 2));
      final ping = await client.getUrl(Uri.parse('${server.baseUrl}/ping'));
      final pong = await (await ping.close())
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      expect(pong, contains('success'));
      await subscription.cancel();
    },
  );
}
