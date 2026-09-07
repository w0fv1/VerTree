import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'local_http_api_contract.dart';
import '../service/file_preview_image_service.dart';

typedef PreviewImageRenderer =
    Future<Uint8List> Function(PreviewImageRequest request);

class ApiFailure implements Exception {
  ApiFailure(this.status, this.code, this.message);
  final int status;
  final String code, message;
}

Future<Map<String, dynamic>> apiBody(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
    if (bytes.length > 1024 * 1024) {
      throw ApiFailure(
        413,
        'BODY_TOO_LARGE',
        'Maximum JSON body size is 1 MiB',
      );
    }
  }
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

Future<void> apiJson(
  HttpRequest request,
  Object? data, {
  int status = 200,
}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({'success': true, 'code': 'OK', 'data': data}),
  );
  await request.response.close();
}

LocalHttpApiHandler apiGuard(
  LocalHttpApiHandler handler,
) => (request, parameters, start) async {
  try {
    await handler(request, parameters, start);
  } catch (error) {
    final failure = switch (error) {
      ApiFailure e => e,
      PreviewRenderException e => ApiFailure(
        e.code == 'RENDER_BUSY'
            ? 409
            : e.code == 'RENDER_TIMEOUT'
            ? 504
            : 422,
        e.code,
        e.message,
      ),
      FormatException() ||
      TypeError() => ApiFailure(400, 'INVALID_REQUEST', error.toString()),
      FileSystemException() => ApiFailure(404, 'FILE_ERROR', error.toString()),
      UnsupportedError() => ApiFailure(422, 'UNSUPPORTED', error.toString()),
      TimeoutException() => ApiFailure(504, 'RENDER_TIMEOUT', error.toString()),
      _ => ApiFailure(
        error.toString().contains('RENDER_BUSY') ? 409 : 422,
        'OPERATION_FAILED',
        error.toString(),
      ),
    };
    request.response.statusCode = failure.status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'success': false,
        'code': failure.code,
        'message': failure.message,
      }),
    );
    await request.response.close();
  }
};

List<LocalHttpApiRoute> previewImageRoutes(PreviewImageRenderer render) => [
  LocalHttpApiRoute(
    method: 'POST',
    pathTemplate: '/preview-images',
    summary: 'Render file contents as a PNG',
    description:
        'Renders independently of the interactive preview. PDF/slides use a 1-based page, spreadsheets a worksheet, video timeSeconds; continuous documents use their first viewport. Output dimensions are 1–4096 pixels.',
    tags: const ['preview'],
    responseContentType: 'image/png',
    requestBody: const LocalHttpApiRequestBody(
      description: 'Local file and PNG options',
      fields: [
        LocalHttpApiField(
          name: 'path',
          type: 'string',
          description: 'Absolute local file path',
          required: true,
        ),
        LocalHttpApiField(
          name: 'width',
          type: 'integer',
          description: 'Output pixels, default 1200',
        ),
        LocalHttpApiField(
          name: 'height',
          type: 'integer',
          description: 'Output pixels, default 1600',
        ),
        LocalHttpApiField(
          name: 'page',
          type: 'integer',
          description: '1-based page or worksheet, default 1',
        ),
        LocalHttpApiField(
          name: 'timeSeconds',
          type: 'number',
          description: 'Video frame time, default 0',
        ),
      ],
    ),
    handler: apiGuard((request, parameters, start) async {
      final image = await render(
        PreviewImageRequest.fromJson(await apiBody(request)),
      );
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.contentLength = image.length;
      request.response.add(image);
      await request.response.close();
    }),
  ),
];
