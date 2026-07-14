import 'dart:io';

import 'package:test/test.dart';
import 'package:vertree/api/local_http_api_server.dart';
import 'package:vertree/service/local_http_api_service.dart';

void main() {
  test('enforces security before dispatching protected routes', () async {
    final server = LocalHttpApiServer(
      apiService: _UnusedApiService(),
      accessToken: 'test-token',
      onLogInfo: (_) {},
      onLogError: (_) {},
    );
    final client = HttpClient();

    try {
      await server.start();
      final baseUrl = server.baseUrl!;

      final pingRequest = await client.getUrl(Uri.parse('$baseUrl/ping'));
      final pingResponse = await pingRequest.close();
      await pingResponse.drain<void>();
      expect(pingResponse.statusCode, HttpStatus.ok);

      final healthRequest = await client.getUrl(Uri.parse('$baseUrl/health'));
      final healthResponse = await healthRequest.close();
      await healthResponse.drain<void>();
      expect(healthResponse.statusCode, HttpStatus.unauthorized);

      final authorizedHealthRequest = await client.getUrl(
        Uri.parse('$baseUrl/health'),
      );
      authorizedHealthRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer test-token',
      );
      final authorizedHealthResponse = await authorizedHealthRequest.close();
      await authorizedHealthResponse.drain<void>();
      expect(authorizedHealthResponse.statusCode, HttpStatus.ok);

      final textRequest = await client.postUrl(
        Uri.parse('$baseUrl/ui/navigation'),
      );
      textRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer test-token',
      );
      textRequest.headers.contentType = ContentType.text;
      textRequest.write('{"page":"brand"}');
      final textResponse = await textRequest.close();
      await textResponse.drain<void>();
      expect(textResponse.statusCode, HttpStatus.unsupportedMediaType);

      final quitRequest = await client.postUrl(Uri.parse('$baseUrl/app/quit'));
      quitRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer test-token',
      );
      quitRequest.headers.set('Origin', 'https://attacker.example');
      final quitResponse = await quitRequest.close();
      await quitResponse.drain<void>();
      expect(quitResponse.statusCode, HttpStatus.forbidden);
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });
}

class _UnusedApiService implements LocalHttpApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #health) {
      return <String, dynamic>{'status': 'ok'};
    }
    throw StateError('Protected route reached the API service.');
  }
}
