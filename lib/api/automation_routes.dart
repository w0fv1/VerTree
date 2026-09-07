import 'dart:io';
import 'dart:typed_data';
import 'local_http_api_contract.dart';
import 'api_protocol.dart';
import '../service/file_preview_image_service.dart';

typedef PreviewImageRenderer =
    Future<Uint8List> Function(PreviewImageRequest request);

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
