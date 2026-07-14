import 'package:vertree/api/local_http_api_contract.dart';

class LocalHttpApiDocumentation {
  LocalHttpApiDocumentation({
    required this.title,
    required this.appVersion,
    required this.serverUrl,
    required this.routes,
  });

  final String title;
  final String appVersion;
  final String serverUrl;
  final List<LocalHttpApiRoute> routes;

  Map<String, dynamic> buildIndex() {
    final documentedRoutes = routes
        .where((route) => route.includeInOpenApi)
        .toList();

    return {
      'name': title,
      'version': appVersion,
      'openApiVersion': '3.1.1',
      'serverUrl': serverUrl,
      'docsUrl': '$serverUrl/docs',
      'openApiUrl': '$serverUrl/openapi.json',
      'endpoints': documentedRoutes
          .map(
            (route) => {
              'method': route.method,
              'path': route.pathTemplate,
              'summary': route.summary,
              'tags': route.tags,
              'queryParameters': route.queryParameters
                  .map(_parameterPreview)
                  .toList(),
              'pathParameters': route.pathParameters
                  .map(_parameterPreview)
                  .toList(),
              'requestBody': route.requestBody == null
                  ? null
                  : {
                      'description': route.requestBody!.description,
                      'fields': route.requestBody!.fields
                          .map(_parameterPreview)
                          .toList(),
                    },
            },
          )
          .toList(),
      'notes': [
        'This API only listens on 127.0.0.1.',
        'Default port is 31414 and auto-increments when occupied.',
        'Operational endpoints require an Authorization: Bearer token header.',
        'OpenAPI is generated from the same route definitions used for request dispatch.',
      ],
    };
  }

  Map<String, dynamic> buildOpenApiDocument() {
    final paths = <String, Map<String, dynamic>>{};

    for (final route in routes.where((route) => route.includeInOpenApi)) {
      final operations = paths.putIfAbsent(route.pathTemplate, () => {});
      operations[route.method.toLowerCase()] = {
        'tags': route.tags,
        'summary': route.summary,
        'description': route.description,
        if (route.requiresAuthentication)
          'security': [
            {'bearerAuth': <dynamic>[]},
          ],
        'parameters': [
          ...route.pathParameters.map(
            (parameter) => parameter.toParameterSchema(location: 'path'),
          ),
          ...route.queryParameters.map(
            (parameter) => parameter.toParameterSchema(location: 'query'),
          ),
        ],
        if (route.requestBody != null)
          'requestBody': route.requestBody!.toOpenApi(),
        'responses': {
          '${route.successStatusCode}': {
            'description': route.successDescription,
            'content': {
              route.responseContentType: {'schema': _successEnvelopeSchema()},
            },
          },
          '400': {
            'description': 'Request validation failed',
            'content': {
              'application/json': {'schema': _errorEnvelopeSchema()},
            },
          },
          if (route.requiresAuthentication)
            '401': {
              'description': 'Bearer authentication failed',
              'content': {
                'application/json': {'schema': _errorEnvelopeSchema()},
              },
            },
          '403': {
            'description': 'The request origin or fetch context was rejected',
            'content': {
              'application/json': {'schema': _errorEnvelopeSchema()},
            },
          },
          if (route.requestBody != null)
            '415': {
              'description': 'The request body is not application/json',
              'content': {
                'application/json': {'schema': _errorEnvelopeSchema()},
              },
            },
          '500': {
            'description': 'Unhandled internal error',
            'content': {
              'application/json': {'schema': _errorEnvelopeSchema()},
            },
          },
        },
      };
    }

    return {
      'openapi': '3.1.1',
      'info': {
        'title': title,
        'version': appVersion,
        'description':
            'Authenticated loopback HTTP API for Vertree monitoring, backup, verification, and UI automation.',
      },
      'servers': [
        {'url': serverUrl, 'description': 'Local loopback endpoint'},
      ],
      'components': {
        'securitySchemes': {
          'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
        },
      },
      'paths': paths,
    };
  }

  String buildDocsHtml() {
    final specUrl = '$serverUrl/openapi.json';
    return '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$title Docs</title>
    <style>
      body {
        margin: 0;
        font-family: "Segoe UI", "Microsoft YaHei", sans-serif;
        background: #f3f6f4;
      }
      .banner {
        padding: 14px 18px;
        background: #163725;
        color: #f7fbf8;
        font-size: 14px;
      }
      .banner a {
        color: #b8f2ca;
      }
    </style>
  </head>
  <body>
    <div class="banner">
      <strong>$title</strong>
      <span>OpenAPI generated from runtime route definitions.</span>
      <span>Spec: <a href="$specUrl">$specUrl</a></span>
    </div>
    <redoc spec-url="$specUrl"></redoc>
    <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
  </body>
</html>
''';
  }

  Map<String, dynamic> _parameterPreview(LocalHttpApiField field) {
    return {
      'name': field.name,
      'type': field.type,
      'required': field.required,
      'description': field.description,
      if (field.example != null) 'example': field.example,
    };
  }

  Map<String, dynamic> _successEnvelopeSchema() {
    return {
      'type': 'object',
      'properties': {
        'success': {'type': 'boolean', 'const': true},
        'code': {'type': 'string', 'example': 'OK'},
        'message': {'type': 'string', 'example': 'ok'},
        'data': {'type': 'object', 'additionalProperties': true},
        'debug': _debugSchema(),
      },
      'required': ['success', 'code', 'message', 'data', 'debug'],
      'additionalProperties': false,
    };
  }

  Map<String, dynamic> _errorEnvelopeSchema() {
    return {
      'type': 'object',
      'properties': {
        'success': {'type': 'boolean', 'const': false},
        'code': {'type': 'string', 'example': 'BAD_REQUEST'},
        'message': {'type': 'string'},
        'data': {'type': 'null'},
        'debug': _debugSchema(),
      },
      'required': ['success', 'code', 'message', 'data', 'debug'],
      'additionalProperties': false,
    };
  }

  Map<String, dynamic> _debugSchema() {
    return {
      'type': 'object',
      'properties': {
        'requestedAt': {'type': 'string', 'format': 'date-time'},
        'respondedAt': {'type': 'string', 'format': 'date-time'},
        'durationMs': {'type': 'integer'},
        'method': {
          'type': ['string', 'null'],
        },
        'path': {
          'type': ['string', 'null'],
        },
        'query': {
          'type': ['object', 'null'],
          'additionalProperties': {'type': 'string'},
        },
        'serverPort': {
          'type': ['integer', 'null'],
        },
        'remoteAddress': {
          'type': ['string', 'null'],
        },
      },
      'required': [
        'requestedAt',
        'respondedAt',
        'durationMs',
        'method',
        'path',
        'query',
        'serverPort',
        'remoteAddress',
      ],
      'additionalProperties': false,
    };
  }
}
