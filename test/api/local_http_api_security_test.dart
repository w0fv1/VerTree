import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vertree/api/local_http_api_security.dart';

void main() {
  const token = 'test-token';
  final security = LocalHttpApiSecurity(accessToken: token);

  LocalHttpApiRequestContext request({
    String host = '127.0.0.1:31414',
    String? origin,
    String? fetchSite,
    String? authorization = 'Bearer $token',
    String method = 'POST',
    String? contentType = 'application/json; charset=utf-8',
  }) {
    return LocalHttpApiRequestContext(
      host: host,
      origin: origin,
      fetchSite: fetchSite,
      authorization: authorization,
      method: method,
      contentType: contentType,
    );
  }

  test('generates a 256-bit URL-safe access token', () {
    final generated = LocalHttpApiSecurity.generateAccessToken();
    final decoded = base64Url.decode(base64Url.normalize(generated));

    expect(decoded, hasLength(32));
  });

  test('replaces an empty configured token with a generated token', () {
    final generated = LocalHttpApiSecurity.fromOptionalAccessToken('   ');

    expect(generated.accessToken, isNotEmpty);
  });

  test('allows an authenticated non-browser client', () {
    final result = security.authorize(
      request(),
      port: 31414,
      requiresAuthentication: true,
      requiresJsonBody: true,
    );

    expect(result.isAllowed, isTrue);
  });

  test('rejects a missing bearer token', () {
    final result = security.authorize(
      request(authorization: null),
      port: 31414,
      requiresAuthentication: true,
      requiresJsonBody: false,
    );

    expect(result.statusCode, HttpStatus.unauthorized);
    expect(result.code, 'UNAUTHORIZED');
  });

  test('rejects a cross-origin browser request before authentication', () {
    final result = security.authorize(
      request(origin: 'https://attacker.example'),
      port: 31414,
      requiresAuthentication: true,
      requiresJsonBody: true,
    );

    expect(result.statusCode, HttpStatus.forbidden);
    expect(result.code, 'FORBIDDEN_ORIGIN');
  });

  test('rejects a DNS rebinding host', () {
    final result = security.authorize(
      request(host: 'attacker.example:31414'),
      port: 31414,
      requiresAuthentication: true,
      requiresJsonBody: true,
    );

    expect(result.statusCode, HttpStatus.misdirectedRequest);
    expect(result.code, 'INVALID_HOST');
  });

  test('rejects cross-site fetch metadata', () {
    final result = security.authorize(
      request(fetchSite: 'cross-site'),
      port: 31414,
      requiresAuthentication: true,
      requiresJsonBody: true,
    );

    expect(result.statusCode, HttpStatus.forbidden);
    expect(result.code, 'CROSS_SITE_REQUEST');
  });

  test('rejects a simple text request for a JSON route', () {
    final result = security.authorize(
      request(contentType: 'text/plain'),
      port: 31414,
      requiresAuthentication: true,
      requiresJsonBody: true,
    );

    expect(result.statusCode, HttpStatus.unsupportedMediaType);
    expect(result.code, 'UNSUPPORTED_MEDIA_TYPE');
  });

  test('allows public metadata without authentication', () {
    final result = security.authorize(
      request(method: 'GET', authorization: null, contentType: null),
      port: 31414,
      requiresAuthentication: false,
      requiresJsonBody: false,
    );

    expect(result.isAllowed, isTrue);
  });
}
