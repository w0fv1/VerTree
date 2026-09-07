import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../foundation/operation_failure.dart';
import 'local_http_api_contract.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.code, this.message);
  final int status;
  final String code, message;
}

ApiFailure apiFailure(Object error) => switch (error) {
  ApiFailure failure => failure,
  OperationFailure failure => ApiFailure(
    switch (failure.code) {
      'INVALID_LABEL' ||
      'INVALID_PATH' ||
      'INVALID_SETTING' ||
      'SAME_FILE' => 400,
      'NOT_FOUND' => 404,
      'VERSION_EXISTS' ||
      'FILE_BUSY' ||
      'SOURCE_CHANGED' ||
      'TARGET_CHANGED' ||
      'RENDER_BUSY' => 409,
      'RENDER_TIMEOUT' => 504,
      'RECOVERY_REQUIRED' => 500,
      _ => 422,
    },
    failure.code,
    failure.message,
  ),
  FormatException() ||
  TypeError() => ApiFailure(400, 'INVALID_REQUEST', error.toString()),
  FileSystemException failure => ApiFailure(
    switch (failure.osError?.errorCode) {
      2 || 3 => 404,
      5 || 13 => 403,
      28 || 112 => 507,
      _ => 500,
    },
    'FILE_ERROR',
    failure.toString(),
  ),
  UnsupportedError() => ApiFailure(422, 'UNSUPPORTED', error.toString()),
  TimeoutException() => ApiFailure(504, 'TIMEOUT', error.toString()),
  _ => ApiFailure(500, 'INTERNAL_ERROR', error.toString()),
};

Future<Map<String, dynamic>> apiBody(HttpRequest request) async {
  final bytes = <int>[];
  var tooLarge = false;
  await for (final chunk in request) {
    if (tooLarge || bytes.length + chunk.length > 1024 * 1024) {
      tooLarge = true;
      // Drain without retaining excess bytes. Cancelling HttpRequest's stream
      // here closes the socket before the caller can send its 413 response.
      continue;
    }
    bytes.addAll(chunk);
  }
  if (tooLarge) {
    throw const ApiFailure(
      413,
      'BODY_TOO_LARGE',
      'Maximum JSON body size is 1 MiB',
    );
  }
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

Map<String, dynamic> successBody(Object? data) => {
  'success': true,
  'code': 'OK',
  'data': data,
};
Map<String, dynamic> failureBody(String code, String message) => {
  'success': false,
  'code': code,
  'message': message,
};

Future<void> apiJson(
  HttpRequest request,
  Object? data, {
  int status = 200,
}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(successBody(data)));
  await request.response.close();
}

LocalHttpApiHandler apiGuard(LocalHttpApiHandler handler) =>
    (request, parameters, start) async {
      try {
        await handler(request, parameters, start);
      } catch (error) {
        final failure = apiFailure(error);
        request.response.statusCode = failure.status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(failureBody(failure.code, failure.message)),
        );
        await request.response.close();
      }
    };
