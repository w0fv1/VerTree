import 'dart:io';

import 'package:test/test.dart';
import 'package:vertree/api/local_http_api_contract.dart';
import 'package:vertree/api/local_http_api_documentation.dart';

void main() {
  group('LocalHttpApiDocumentation', () {
    final routes = [
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/health',
        summary: 'Health',
        description: 'Health endpoint',
        tags: const ['system'],
        queryParameters: const [
          LocalHttpApiField(
            name: 'verbose',
            type: 'boolean',
            description: 'Whether to include extra details.',
            required: false,
          ),
        ],
        handler: (request, pathParameters, startedAt) async {},
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/monitor-tasks',
        summary: 'Create task',
        description: 'Create one monitor task',
        tags: const ['monitoring'],
        successStatusCode: HttpStatus.created,
        requestBody: const LocalHttpApiRequestBody(
          description: 'Create request body',
          fields: [
            LocalHttpApiField(
              name: 'path',
              type: 'string',
              description: 'Absolute file path',
              required: true,
            ),
          ],
        ),
        handler: (request, pathParameters, startedAt) async {},
      ),
    ];

    final documentation = LocalHttpApiDocumentation(
      title: 'Vertree Local HTTP API',
      appVersion: 'V0.9.0',
      serverUrl: 'http://127.0.0.1:31414/api/v1',
      routes: routes,
    );

    test('buildIndex returns endpoint list and docs links', () {
      final index = documentation.buildIndex();

      expect(index['docsUrl'], 'http://127.0.0.1:31414/api/v1/docs');
      expect(index['openApiUrl'], 'http://127.0.0.1:31414/api/v1/openapi.json');
      expect((index['endpoints'] as List), hasLength(2));
    });

    test('buildOpenApiDocument maps paths and request body metadata', () {
      final document = documentation.buildOpenApiDocument();
      final paths = document['paths'] as Map<String, dynamic>;
      final createTask = paths['/monitor-tasks'] as Map<String, dynamic>;
      final post = createTask['post'] as Map<String, dynamic>;
      final requestBody = post['requestBody'] as Map<String, dynamic>;
      final schema =
          (((requestBody['content'] as Map<String, dynamic>)['application/json']
                  as Map<String, dynamic>)['schema']
              as Map<String, dynamic>);

      expect(document['openapi'], '3.1.1');
      expect(document['components']['securitySchemes']['bearerAuth'], {
        'type': 'http',
        'scheme': 'bearer',
      });
      expect(post['security'], [
        {'bearerAuth': <dynamic>[]},
      ]);
      expect(paths.containsKey('/health'), isTrue);
      expect(post['summary'], 'Create task');
      expect(schema['required'], ['path']);
    });
  });
}
