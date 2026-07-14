import 'dart:io';

typedef LocalHttpApiHandler =
    Future<void> Function(
      HttpRequest request,
      Map<String, String> pathParameters,
      DateTime startedAt,
    );

class LocalHttpApiField {
  const LocalHttpApiField({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.example,
  });

  final String name;
  final String type;
  final String description;
  final bool required;
  final Object? example;

  Map<String, dynamic> toSchema() {
    return {
      'type': type,
      'description': description,
      if (example != null) 'example': example,
    };
  }

  Map<String, dynamic> toParameterSchema({required String location}) {
    return {
      'name': name,
      'in': location,
      'required': location == 'path' ? true : required,
      'description': description,
      'schema': {'type': type},
      if (example != null) 'example': example,
    };
  }
}

class LocalHttpApiRequestBody {
  const LocalHttpApiRequestBody({
    required this.description,
    required this.fields,
  });

  final String description;
  final List<LocalHttpApiField> fields;

  Map<String, dynamic> toOpenApi() {
    return {
      'required': true,
      'description': description,
      'content': {
        'application/json': {
          'schema': {
            'type': 'object',
            'properties': {
              for (final field in fields) field.name: field.toSchema(),
            },
            'required': [
              for (final field in fields)
                if (field.required) field.name,
            ],
            'additionalProperties': false,
          },
        },
      },
    };
  }
}

class LocalHttpApiRoute {
  const LocalHttpApiRoute({
    required this.method,
    required this.pathTemplate,
    required this.summary,
    required this.description,
    required this.tags,
    required this.handler,
    this.pathParameters = const [],
    this.queryParameters = const [],
    this.requestBody,
    this.successStatusCode = HttpStatus.ok,
    this.successDescription = 'Successful response',
    this.includeInOpenApi = true,
    this.responseContentType = 'application/json',
    this.requiresAuthentication = true,
  });

  final String method;
  final String pathTemplate;
  final String summary;
  final String description;
  final List<String> tags;
  final List<LocalHttpApiField> pathParameters;
  final List<LocalHttpApiField> queryParameters;
  final LocalHttpApiRequestBody? requestBody;
  final int successStatusCode;
  final String successDescription;
  final bool includeInOpenApi;
  final String responseContentType;
  final bool requiresAuthentication;
  final LocalHttpApiHandler handler;

  List<String> get templateSegments {
    if (pathTemplate == '/') {
      return const [];
    }
    return pathTemplate
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
  }

  bool matches({required String method, required List<String> pathSegments}) {
    if (this.method != method) {
      return false;
    }

    final template = templateSegments;
    if (template.length != pathSegments.length) {
      return false;
    }

    for (var index = 0; index < template.length; index++) {
      final expected = template[index];
      final actual = pathSegments[index];
      if (_isPathParameterSegment(expected)) {
        continue;
      }
      if (expected != actual) {
        return false;
      }
    }

    return true;
  }

  Map<String, String> extractPathParameters(List<String> pathSegments) {
    final params = <String, String>{};
    final template = templateSegments;
    for (var index = 0; index < template.length; index++) {
      final segment = template[index];
      if (_isPathParameterSegment(segment)) {
        params[_pathParameterName(segment)] = pathSegments[index];
      }
    }
    return params;
  }

  bool _isPathParameterSegment(String segment) {
    return segment.startsWith('{') && segment.endsWith('}');
  }

  String _pathParameterName(String segment) {
    return segment.substring(1, segment.length - 1);
  }
}
