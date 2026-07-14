import 'dart:convert';
import 'dart:io';
import 'dart:math';

class LocalHttpApiRequestContext {
  const LocalHttpApiRequestContext({
    required this.host,
    required this.origin,
    required this.fetchSite,
    required this.authorization,
    required this.method,
    required this.contentType,
  });

  final String? host;
  final String? origin;
  final String? fetchSite;
  final String? authorization;
  final String method;
  final String? contentType;
}

class LocalHttpApiAuthorizationResult {
  const LocalHttpApiAuthorizationResult._({
    required this.isAllowed,
    required this.statusCode,
    required this.code,
    required this.message,
  });

  const LocalHttpApiAuthorizationResult.allowed()
    : this._(isAllowed: true, statusCode: 200, code: 'OK', message: 'ok');

  const LocalHttpApiAuthorizationResult.denied({
    required int statusCode,
    required String code,
    required String message,
  }) : this._(
         isAllowed: false,
         statusCode: statusCode,
         code: code,
         message: message,
       );

  final bool isAllowed;
  final int statusCode;
  final String code;
  final String message;
}

class LocalHttpApiSecurity {
  LocalHttpApiSecurity({required String accessToken})
    : accessToken = _validateAccessToken(accessToken);

  factory LocalHttpApiSecurity.fromOptionalAccessToken(String? accessToken) {
    final normalized = accessToken?.trim();
    return LocalHttpApiSecurity(
      accessToken: normalized == null || normalized.isEmpty
          ? generateAccessToken()
          : normalized,
    );
  }

  final String accessToken;

  static String generateAccessToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _validateAccessToken(String accessToken) {
    final normalized = accessToken.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken');
    }
    return normalized;
  }

  LocalHttpApiAuthorizationResult authorize(
    LocalHttpApiRequestContext request, {
    required int port,
    required bool requiresAuthentication,
    required bool requiresJsonBody,
  }) {
    final allowedHosts = {'127.0.0.1:$port', 'localhost:$port'};
    final host = request.host?.trim().toLowerCase();
    if (host == null || !allowedHosts.contains(host)) {
      return const LocalHttpApiAuthorizationResult.denied(
        statusCode: HttpStatus.misdirectedRequest,
        code: 'INVALID_HOST',
        message: 'The Host header does not match the local API endpoint.',
      );
    }

    final origin = request.origin?.trim().toLowerCase();
    if (origin != null &&
        !allowedHosts.map((host) => 'http://$host').contains(origin)) {
      return const LocalHttpApiAuthorizationResult.denied(
        statusCode: HttpStatus.forbidden,
        code: 'FORBIDDEN_ORIGIN',
        message: 'Cross-origin browser requests are not allowed.',
      );
    }

    if (request.fetchSite?.trim().toLowerCase() == 'cross-site') {
      return const LocalHttpApiAuthorizationResult.denied(
        statusCode: HttpStatus.forbidden,
        code: 'CROSS_SITE_REQUEST',
        message: 'Cross-site browser requests are not allowed.',
      );
    }

    if (requiresAuthentication && !_matchesBearerToken(request.authorization)) {
      return const LocalHttpApiAuthorizationResult.denied(
        statusCode: HttpStatus.unauthorized,
        code: 'UNAUTHORIZED',
        message: 'A valid Bearer access token is required.',
      );
    }

    if (requiresJsonBody && !_isJsonContentType(request.contentType)) {
      return const LocalHttpApiAuthorizationResult.denied(
        statusCode: HttpStatus.unsupportedMediaType,
        code: 'UNSUPPORTED_MEDIA_TYPE',
        message: 'This endpoint requires an application/json request body.',
      );
    }

    return const LocalHttpApiAuthorizationResult.allowed();
  }

  bool _matchesBearerToken(String? authorization) {
    if (authorization == null) {
      return false;
    }
    final separator = authorization.indexOf(' ');
    if (separator <= 0 ||
        authorization.substring(0, separator).toLowerCase() != 'bearer') {
      return false;
    }
    final candidate = authorization.substring(separator + 1).trim();
    if (candidate.length != accessToken.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < accessToken.length; index++) {
      difference |= candidate.codeUnitAt(index) ^ accessToken.codeUnitAt(index);
    }
    return difference == 0;
  }

  bool _isJsonContentType(String? contentType) {
    return contentType?.split(';').first.trim().toLowerCase() ==
        ContentType.json.mimeType;
  }
}
