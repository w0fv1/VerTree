import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vertree/api/automation_routes.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/service/local_http_api_service.dart';

class _Service implements LocalHttpApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'PNG endpoint authenticates, validates and returns raw image bytes',
    () async {
      var renders = 0;
      final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final server = LocalHttpApiServer(
        apiService: _Service(),
        accessToken: 'test-token',
        onLogInfo: (_) {},
        onLogError: (_) {},
        additionalRoutes: previewImageRoutes((request) async {
          renders++;
          return png;
        }),
      );
      final client = HttpClient();
      await server.start();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
      });
      Future<HttpClientResponse> post(
        Object body, {
        bool authenticated = true,
      }) async {
        final request = await client.postUrl(
          Uri.parse('${server.baseUrl}/preview-images'),
        );
        request.headers.contentType = ContentType.json;
        if (authenticated) {
          request.headers.set('Authorization', 'Bearer test-token');
        }
        request.write(jsonEncode(body));
        return request.close();
      }

      var response = await post({
        'path': p.absolute('sample.pdf'),
      }, authenticated: false);
      expect(response.statusCode, 401);
      await response.drain<void>();
      expect(renders, 0);
      response = await post({'path': p.absolute('sample.pdf'), 'width': -1});
      expect(response.statusCode, 400);
      await response.drain<void>();
      expect(renders, 0);
      response = await post({'path': p.absolute('sample.pdf'), 'page': 2});
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'image/png');
      expect(
        await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
        png,
      );
      expect(renders, 1);
    },
  );
}
