import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/api/extended_automation_api.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/service/local_http_api_service.dart';
import 'package:vertree/component/configer.dart';
import 'package:vertree/service/app_events.dart';

class _Service implements LocalHttpApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'SSE promptly replays and streams events while other requests remain available',
    () async {
      final api = ExtendedAutomationApi(
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
      final cursor = AppEvents.instance.lastId;
      AppEvents.instance.emit('test.replay', {});
      final request = await client.getUrl(
        Uri.parse('${server.baseUrl}/events'),
      );
      request.headers.set('Authorization', 'Bearer test-token');
      request.headers.set('Last-Event-ID', '$cursor');
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
      AppEvents.instance.emit('test.live', {});
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
