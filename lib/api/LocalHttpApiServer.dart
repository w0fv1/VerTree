import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vertree/api/LocalHttpApiContract.dart';
import 'package:vertree/api/LocalHttpApiDocumentation.dart';
import 'package:vertree/main.dart';
import 'package:vertree/service/LanFileShareServer.dart';
import 'package:vertree/service/LocalHttpApiService.dart';

class LocalHttpApiServer {
  LocalHttpApiServer({required this.apiService}) : _routes = [] {
    _routes.addAll(_buildRoutes());
  }

  static const int defaultPort = 31414;
  static const int maxPortSearchSpan = 200;

  final LocalHttpApiService apiService;
  final List<LocalHttpApiRoute> _routes;

  HttpServer? _server;
  int? _port;

  bool get isRunning => _server != null;
  int? get port => _port;
  String? get baseUrl =>
      _port == null ? null : 'http://127.0.0.1:$_port/api/v1';
  String? get openApiUrl => baseUrl == null ? null : '$baseUrl/openapi.json';
  String? get docsUrl => baseUrl == null ? null : '$baseUrl/docs';

  Future<void> syncWithConfig() async {
    final enabled = configer.get<bool>('localHttpApiEnabled', true);
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    for (
      var candidate = defaultPort;
      candidate < defaultPort + maxPortSearchSpan;
      candidate++
    ) {
      try {
        final server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidate,
        );
        _server = server;
        _port = candidate;
        unawaited(_listen(server));
        logger.info(
          'Local HTTP API started at http://127.0.0.1:$candidate/api/v1',
        );
        return;
      } on SocketException catch (e) {
        logger.info('Port $candidate unavailable for local HTTP API: $e');
      }
    }

    throw Exception(
      'Unable to bind local HTTP API after trying ports $defaultPort-${defaultPort + maxPortSearchSpan - 1}',
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    if (server != null) {
      await server.close(force: true);
      logger.info('Local HTTP API stopped');
    }
  }

  Future<void> _listen(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (e) {
      logger.error('Local HTTP API listen loop failed: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final startedAt = DateTime.now();

    try {
      if (!_isLoopbackRequest(request)) {
        await _writeJson(
          request,
          statusCode: HttpStatus.forbidden,
          body: _errorBody(
            request,
            'FORBIDDEN',
            'Only loopback requests are allowed.',
            startedAt,
          ),
        );
        return;
      }

      final pathSegments = request.uri.pathSegments;
      if (pathSegments.length < 2 ||
          pathSegments[0] != 'api' ||
          pathSegments[1] != 'v1') {
        await _writeJson(
          request,
          statusCode: HttpStatus.notFound,
          body: _errorBody(
            request,
            'NOT_FOUND',
            'Unknown endpoint.',
            startedAt,
          ),
        );
        return;
      }

      final route = pathSegments
          .skip(2)
          .where((segment) => segment.isNotEmpty)
          .toList();
      await _dispatch(request, route, startedAt);
    } catch (e) {
      logger.error('Local HTTP API request failed: $e');
      await _writeJson(
        request,
        statusCode: HttpStatus.internalServerError,
        body: _errorBody(request, 'INTERNAL_ERROR', e.toString(), startedAt),
      );
    }
  }

  Future<void> _dispatch(
    HttpRequest request,
    List<String> route,
    DateTime startedAt,
  ) async {
    for (final definition in _routes) {
      if (!definition.matches(method: request.method, pathSegments: route)) {
        continue;
      }
      final pathParameters = definition.extractPathParameters(route);
      await definition.handler(request, pathParameters, startedAt);
      return;
    }

    await _writeJson(
      request,
      statusCode: HttpStatus.notFound,
      body: _errorBody(request, 'NOT_FOUND', 'Unknown endpoint.', startedAt),
    );
  }

  List<LocalHttpApiRoute> _buildRoutes() {
    return [
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/',
        summary: 'Read the generated API index',
        description:
            'Returns links to the OpenAPI document, the docs page, and all registered endpoints.',
        tags: const ['meta'],
        handler: _handleApiIndex,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/openapi.json',
        summary: 'Read the generated OpenAPI document',
        description: 'Returns the OpenAPI 3.1.1 document for this local API.',
        tags: const ['meta'],
        includeInOpenApi: false,
        handler: _handleOpenApiDocument,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/docs',
        summary: 'Open the interactive documentation page',
        description:
            'Returns a Redoc-based HTML page powered by the generated OpenAPI document.',
        tags: const ['meta'],
        includeInOpenApi: false,
        responseContentType: 'text/html',
        handler: _handleDocsPage,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/health',
        summary: 'Read runtime health information',
        description:
            'Returns runtime status, config values, and the current local HTTP API address.',
        tags: const ['system'],
        handler: _handleHealth,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/app/quit',
        summary: 'Quit the current Vertree app process',
        description:
            'Returns a success response first, then asynchronously shuts down the current desktop app process.',
        tags: const ['system', 'automation'],
        handler: _handleQuitApp,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/ui/navigation',
        summary: 'Switch to a specific app page',
        description:
            'Shows the main window if needed and navigates the desktop app to a supported page.',
        tags: const ['ui', 'automation'],
        requestBody: const LocalHttpApiRequestBody(
          description: 'The target page and optional navigation parameters.',
          fields: [
            LocalHttpApiField(
              name: 'page',
              type: 'string',
              description:
                  'Supported values: brand, monitor, settings, version-tree.',
              required: true,
              example: 'settings',
            ),
            LocalHttpApiField(
              name: 'path',
              type: 'string',
              description:
                  'Required when page is version-tree. Use an absolute file path.',
              required: false,
              example: r'D:\project\storyboard.0.1.txt',
            ),
            LocalHttpApiField(
              name: 'waitMilliseconds',
              type: 'integer',
              description:
                  'Extra time to wait after navigation before returning.',
              required: false,
              example: 600,
            ),
            LocalHttpApiField(
              name: 'ensureWindowVisible',
              type: 'boolean',
              description:
                  'Whether the API should surface the main window before navigation.',
              required: false,
              example: true,
            ),
            LocalHttpApiField(
              name: 'windowMode',
              type: 'string',
              description:
                  'Optional window mode applied after navigation: restore, maximize, fullscreen.',
              required: false,
              example: 'fullscreen',
            ),
            LocalHttpApiField(
              name: 'windowWidth',
              type: 'number',
              description:
                  'Optional target window width used with windowMode=restore.',
              required: false,
              example: 1440,
            ),
            LocalHttpApiField(
              name: 'windowHeight',
              type: 'number',
              description:
                  'Optional target window height used with windowMode=restore.',
              required: false,
              example: 920,
            ),
            LocalHttpApiField(
              name: 'showInitialSetupDialog',
              type: 'boolean',
              description:
                  'When page is brand, forces the initialization setup dialog to open.',
              required: false,
              example: true,
            ),
            LocalHttpApiField(
              name: 'fileTreeScale',
              type: 'number',
              description:
                  'Optional initial canvas scale when page is version-tree.',
              required: false,
              example: 0.42,
            ),
            LocalHttpApiField(
              name: 'fitFileTreeToViewport',
              type: 'boolean',
              description:
                  'Whether the version-tree canvas should auto-fit into the current viewport after loading.',
              required: false,
              example: true,
            ),
          ],
        ),
        handler: _handleUiNavigation,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/ui/window-state',
        summary: 'Adjust the current app window state',
        description:
            'Shows the current app window and updates its mode to restore, maximize, or fullscreen.',
        tags: const ['ui', 'automation'],
        requestBody: const LocalHttpApiRequestBody(
          description: 'Window state and optional restore size.',
          fields: [
            LocalHttpApiField(
              name: 'mode',
              type: 'string',
              description: 'Supported values: restore, maximize, fullscreen.',
              required: false,
              example: 'fullscreen',
            ),
            LocalHttpApiField(
              name: 'width',
              type: 'number',
              description: 'Optional window width used when mode is restore.',
              required: false,
              example: 1440,
            ),
            LocalHttpApiField(
              name: 'height',
              type: 'number',
              description: 'Optional window height used when mode is restore.',
              required: false,
              example: 920,
            ),
            LocalHttpApiField(
              name: 'focus',
              type: 'boolean',
              description:
                  'Whether the app window should be focused after the state change.',
              required: false,
              example: true,
            ),
          ],
        ),
        handler: _handleUiWindowState,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/ui/theme-mode',
        summary: 'Set the current app theme mode',
        description:
            'Updates the desktop app theme mode to system, light, or dark and returns the current UI state.',
        tags: const ['ui', 'automation'],
        requestBody: const LocalHttpApiRequestBody(
          description: 'Theme mode settings.',
          fields: [
            LocalHttpApiField(
              name: 'mode',
              type: 'string',
              description: 'Supported values: system, light, dark.',
              required: true,
              example: 'light',
            ),
          ],
        ),
        handler: _handleUiThemeMode,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/ui/file-tree/viewport',
        summary: 'Adjust the version-tree canvas viewport',
        description:
            'Fits the version-tree canvas to the viewport or applies an explicit scale.',
        tags: const ['ui', 'automation'],
        requestBody: const LocalHttpApiRequestBody(
          description: 'File tree viewport options.',
          fields: [
            LocalHttpApiField(
              name: 'scale',
              type: 'number',
              description:
                  'Explicit file tree canvas scale. Lower values zoom out.',
              required: false,
              example: 0.38,
            ),
            LocalHttpApiField(
              name: 'fitToViewport',
              type: 'boolean',
              description:
                  'Whether the canvas should be auto-fitted to the current viewport.',
              required: false,
              example: true,
            ),
          ],
        ),
        handler: _handleUiFileTreeViewport,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/ui/screenshot',
        summary: 'Capture the current app UI as a PNG image',
        description:
            'Captures the rendered desktop app window and writes a PNG file to the requested path.',
        tags: const ['ui', 'automation'],
        requestBody: const LocalHttpApiRequestBody(
          description: 'The PNG output path and optional rendering parameters.',
          fields: [
            LocalHttpApiField(
              name: 'outputPath',
              type: 'string',
              description: 'Absolute PNG output path on the local machine.',
              required: true,
              example: r'D:\vertree\docs\static\img\settings.png',
            ),
            LocalHttpApiField(
              name: 'pixelRatio',
              type: 'number',
              description:
                  'Flutter image pixel ratio used for rendering the screenshot.',
              required: false,
              example: 1.75,
            ),
            LocalHttpApiField(
              name: 'waitMilliseconds',
              type: 'integer',
              description:
                  'Extra time to wait before capturing the frame, useful for async page loading.',
              required: false,
              example: 900,
            ),
            LocalHttpApiField(
              name: 'ensureWindowVisible',
              type: 'boolean',
              description:
                  'Whether the API should surface the main window before capturing.',
              required: false,
              example: true,
            ),
          ],
        ),
        handler: _handleUiScreenshot,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/monitor-tasks',
        summary: 'List monitor tasks',
        description:
            'Returns all file monitoring tasks with backup folder and runtime details.',
        tags: const ['monitoring'],
        handler: _handleMonitorTaskList,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/monitor-tasks',
        summary: 'Create a monitor task',
        description: 'Creates and starts monitoring for the given file path.',
        tags: const ['monitoring'],
        successStatusCode: HttpStatus.created,
        requestBody: const LocalHttpApiRequestBody(
          description: 'The file that should be monitored.',
          fields: [
            LocalHttpApiField(
              name: 'path',
              type: 'string',
              description: 'Absolute file path to monitor.',
              required: true,
              example: r'D:\project\storyboard.0.1.txt',
            ),
          ],
        ),
        handler: _handleCreateMonitorTask,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/monitor-tasks/{id}',
        summary: 'Read one monitor task',
        description: 'Reads a single monitor task using its encoded task id.',
        tags: const ['monitoring'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'id',
            type: 'string',
            description: 'base64url-encoded normalized file path.',
            required: true,
          ),
        ],
        handler: _handleGetMonitorTask,
      ),
      LocalHttpApiRoute(
        method: 'PATCH',
        pathTemplate: '/monitor-tasks/{id}',
        summary: 'Update one monitor task',
        description:
            'Starts or stops a monitor task by updating its running state.',
        tags: const ['monitoring'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'id',
            type: 'string',
            description: 'base64url-encoded normalized file path.',
            required: true,
          ),
        ],
        requestBody: const LocalHttpApiRequestBody(
          description: 'The desired running state for the task.',
          fields: [
            LocalHttpApiField(
              name: 'isRunning',
              type: 'boolean',
              description:
                  'Whether the task should be running after the update.',
              required: true,
              example: true,
            ),
          ],
        ),
        handler: _handlePatchMonitorTask,
      ),
      LocalHttpApiRoute(
        method: 'DELETE',
        pathTemplate: '/monitor-tasks/{id}',
        summary: 'Delete one monitor task',
        description: 'Stops and removes a monitor task by id.',
        tags: const ['monitoring'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'id',
            type: 'string',
            description: 'base64url-encoded normalized file path.',
            required: true,
          ),
        ],
        handler: _handleDeleteMonitorTask,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/backups',
        summary: 'Create one backup',
        description:
            'Runs a backup for the given file path and returns detailed result data.',
        tags: const ['backup'],
        successStatusCode: HttpStatus.created,
        requestBody: const LocalHttpApiRequestBody(
          description: 'The backup target file and optional label.',
          fields: [
            LocalHttpApiField(
              name: 'path',
              type: 'string',
              description: 'Absolute file path to back up.',
              required: true,
              example: r'D:\project\storyboard.0.1.txt',
            ),
            LocalHttpApiField(
              name: 'label',
              type: 'string',
              description: 'Optional backup label.',
              required: false,
              example: 'baseline',
            ),
          ],
        ),
        handler: _handleCreateBackup,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/backups',
        summary: 'List backups for one file',
        description:
            'Lists files in the derived backup directory for the given source file path.',
        tags: const ['backup'],
        queryParameters: const [
          LocalHttpApiField(
            name: 'path',
            type: 'string',
            description: 'Absolute file path whose backups should be listed.',
            required: true,
            example: r'D:\project\storyboard.0.1.txt',
          ),
        ],
        handler: _handleListBackups,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/version-files',
        summary: 'List version-managed files',
        description:
            'Lists all version-tree sibling files that belong to the same logical document.',
        tags: const ['version-tree'],
        queryParameters: const [
          LocalHttpApiField(
            name: 'path',
            type: 'string',
            description: 'Absolute file path used to select a version family.',
            required: true,
            example: r'D:\project\storyboard.0.1.txt',
          ),
        ],
        handler: _handleListVersionFiles,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/file-shares',
        summary: 'List active LAN file shares',
        description:
            'Lists temporary LAN file shares created by the current desktop app instance.',
        tags: const ['sharing'],
        handler: _handleListFileShares,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/file-shares',
        summary: 'Create one LAN file share',
        description:
            'Creates a temporary LAN download share for a specific file version and returns the GitHub Pages landing URL plus direct LAN candidates.',
        tags: const ['sharing', 'automation'],
        successStatusCode: HttpStatus.created,
        requestBody: const LocalHttpApiRequestBody(
          description: 'The file to share and optional expiry.',
          fields: [
            LocalHttpApiField(
              name: 'path',
              type: 'string',
              description: 'Absolute file path to expose on the LAN.',
              required: true,
              example: r'D:\project\storyboard.0.1.txt',
            ),
            LocalHttpApiField(
              name: 'expiresInMinutes',
              type: 'integer',
              description: 'How long the temporary share should stay valid.',
              required: false,
              example: 30,
            ),
          ],
        ),
        handler: _handleCreateFileShare,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/file-shares/{token}',
        summary: 'Read one LAN file share',
        description: 'Reads one temporary LAN file share by token.',
        tags: const ['sharing'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'token',
            type: 'string',
            description:
                'Opaque share token returned when the share was created.',
            required: true,
          ),
        ],
        handler: _handleGetFileShare,
      ),
      LocalHttpApiRoute(
        method: 'DELETE',
        pathTemplate: '/file-shares/{token}',
        summary: 'Revoke one LAN file share',
        description: 'Revokes one temporary LAN file share by token.',
        tags: const ['sharing', 'automation'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'token',
            type: 'string',
            description:
                'Opaque share token returned when the share was created.',
            required: true,
          ),
        ],
        handler: _handleDeleteFileShare,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/version-trees',
        summary: 'Build a version tree',
        description:
            'Builds the version tree for the given file and returns the nested structure.',
        tags: const ['version-tree'],
        queryParameters: const [
          LocalHttpApiField(
            name: 'path',
            type: 'string',
            description: 'Absolute file path used as the version tree focus.',
            required: true,
            example: r'D:\project\storyboard.0.1.txt',
          ),
        ],
        handler: _handleVersionTree,
      ),
      LocalHttpApiRoute(
        method: 'GET',
        pathTemplate: '/monitor-tasks/{id}/backups',
        summary: 'List monitor backups for one task',
        description:
            'Lists timestamped files from the monitor backup directory for a specific monitor task.',
        tags: const ['monitoring'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'id',
            type: 'string',
            description: 'base64url-encoded normalized file path.',
            required: true,
          ),
        ],
        handler: _handleListMonitorTaskBackups,
      ),
      LocalHttpApiRoute(
        method: 'POST',
        pathTemplate: '/monitor-tasks/{id}/verification-writes',
        summary: 'Write to a monitored file and verify backup creation',
        description:
            'Appends text to the monitored file, waits briefly, and reports whether a new monitor backup was created.',
        tags: const ['monitoring', 'testing'],
        pathParameters: const [
          LocalHttpApiField(
            name: 'id',
            type: 'string',
            description: 'base64url-encoded normalized file path.',
            required: true,
          ),
        ],
        requestBody: const LocalHttpApiRequestBody(
          description: 'Verification write payload.',
          fields: [
            LocalHttpApiField(
              name: 'appendText',
              type: 'string',
              description:
                  'Text appended to the monitored file during verification.',
              required: true,
              example: '\napi-verification-write',
            ),
            LocalHttpApiField(
              name: 'waitMilliseconds',
              type: 'integer',
              description:
                  'How long to wait after the write before reading backup results.',
              required: false,
              example: 1800,
            ),
          ],
        ),
        handler: _handleVerifyMonitorTaskWrite,
      ),
    ];
  }

  LocalHttpApiDocumentation get _documentation {
    final serverUrl =
        baseUrl ?? 'http://127.0.0.1:${_port ?? defaultPort}/api/v1';
    return LocalHttpApiDocumentation(
      title: 'Vertree Local HTTP API',
      appVersion: apiService.currentVersion,
      serverUrl: serverUrl,
      routes: _routes,
    );
  }

  Future<void> _handleApiIndex(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    await _writeSuccess(
      request,
      data: _documentation.buildIndex(),
      startedAt: startedAt,
    );
  }

  Future<void> _handleOpenApiDocument(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    await _writeJson(
      request,
      statusCode: HttpStatus.ok,
      body: _documentation.buildOpenApiDocument(),
    );
  }

  Future<void> _handleDocsPage(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    await _writeHtml(
      request,
      statusCode: HttpStatus.ok,
      body: _documentation.buildDocsHtml(),
    );
  }

  Future<void> _handleHealth(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    await _writeSuccess(
      request,
      data: apiService.health(),
      startedAt: startedAt,
    );
  }

  Future<void> _handleQuitApp(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final result = apiService.prepareQuitApp();
    if (result.isErr) {
      await _writeResult(request, result, startedAt);
      return;
    }

    await _writeSuccess(request, data: result.unwrap(), startedAt: startedAt);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 120), () async {
        await apiService.quitApp();
      }),
    );
  }

  Future<void> _handleMonitorTaskList(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    await _writeSuccess(
      request,
      data: apiService.listMonitorTasks(),
      startedAt: startedAt,
    );
  }

  Future<void> _handleUiNavigation(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final page = _requiredStringField(body, 'page');
    if (page == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "page" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.navigateUi(
      page: page,
      path: _optionalStringField(body, 'path'),
      waitMilliseconds: _optionalIntField(body, 'waitMilliseconds') ?? 400,
      ensureWindowVisible:
          _optionalBoolField(body, 'ensureWindowVisible') ?? true,
      windowMode: _optionalStringField(body, 'windowMode'),
      windowWidth: _optionalDoubleField(body, 'windowWidth'),
      windowHeight: _optionalDoubleField(body, 'windowHeight'),
      showInitialSetupDialog:
          _optionalBoolField(body, 'showInitialSetupDialog') ?? false,
      fileTreeScale: _optionalDoubleField(body, 'fileTreeScale'),
      fitFileTreeToViewport:
          _optionalBoolField(body, 'fitFileTreeToViewport') ?? false,
    );
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleUiWindowState(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final result = await apiService.setWindowState(
      mode: _optionalStringField(body, 'mode') ?? 'restore',
      width: _optionalDoubleField(body, 'width'),
      height: _optionalDoubleField(body, 'height'),
      focus: _optionalBoolField(body, 'focus') ?? true,
    );
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleUiFileTreeViewport(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final result = await apiService.setFileTreeViewport(
      scale: _optionalDoubleField(body, 'scale'),
      fitToViewport: _optionalBoolField(body, 'fitToViewport') ?? false,
    );
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleUiThemeMode(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final mode = _requiredStringField(body, 'mode');
    if (mode == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "mode" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.setThemeMode(mode);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleUiScreenshot(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final outputPath = _requiredStringField(body, 'outputPath');
    if (outputPath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "outputPath" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.captureUiScreenshot(
      outputPath: outputPath,
      pixelRatio: _optionalDoubleField(body, 'pixelRatio') ?? 1.5,
      waitMilliseconds: _optionalIntField(body, 'waitMilliseconds') ?? 450,
      ensureWindowVisible:
          _optionalBoolField(body, 'ensureWindowVisible') ?? true,
    );
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleCreateMonitorTask(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final filePath = _requiredStringField(body, 'path');
    if (filePath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "path" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.createMonitorTask(filePath);
    await _writeResult(
      request,
      result,
      startedAt,
      successStatusCode: HttpStatus.created,
    );
  }

  Future<void> _handleGetMonitorTask(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final result = apiService.getMonitorTask(pathParameters['id']!);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handlePatchMonitorTask(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final isRunning = _requiredBoolField(body, 'isRunning');
    if (isRunning == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "isRunning" must be a boolean.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.updateMonitorTask(
      pathParameters['id']!,
      isRunning: isRunning,
    );
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleDeleteMonitorTask(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final result = await apiService.deleteMonitorTask(pathParameters['id']!);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleCreateBackup(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final filePath = _requiredStringField(body, 'path');
    if (filePath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "path" is required.',
          startedAt,
        ),
      );
      return;
    }

    final label = body['label']?.toString();
    final result = await apiService.createBackup(filePath, label: label);
    await _writeResult(
      request,
      result,
      startedAt,
      successStatusCode: HttpStatus.created,
    );
  }

  Future<void> _handleListBackups(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final filePath = _requiredQueryParameter(request, 'path');
    if (filePath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Query parameter "path" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = apiService.listBackups(filePath);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleListVersionFiles(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final filePath = _requiredQueryParameter(request, 'path');
    if (filePath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Query parameter "path" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = apiService.listVersionFiles(filePath);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleListFileShares(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    await _writeSuccess(
      request,
      data: await apiService.listLanFileShares(),
      startedAt: startedAt,
    );
  }

  Future<void> _handleCreateFileShare(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final filePath = _requiredStringField(body, 'path');
    if (filePath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "path" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.createLanFileShare(
      filePath,
      expiresInMinutes:
          _optionalIntField(body, 'expiresInMinutes') ??
          LanFileShareServer.defaultExpiryMinutes,
    );
    await _writeResult(
      request,
      result,
      startedAt,
      successStatusCode: HttpStatus.created,
    );
  }

  Future<void> _handleGetFileShare(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final result = await apiService.getLanFileShare(pathParameters['token']!);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleDeleteFileShare(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final result = apiService.revokeLanFileShare(pathParameters['token']!);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleVersionTree(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final filePath = _requiredQueryParameter(request, 'path');
    if (filePath == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Query parameter "path" is required.',
          startedAt,
        ),
      );
      return;
    }

    final result = await apiService.getVersionTree(filePath);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleListMonitorTaskBackups(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final result = apiService.listMonitorTaskBackups(pathParameters['id']!);
    await _writeResult(request, result, startedAt);
  }

  Future<void> _handleVerifyMonitorTaskWrite(
    HttpRequest request,
    Map<String, String> pathParameters,
    DateTime startedAt,
  ) async {
    final body = await _readJsonBody(request);
    final appendText = _requiredStringField(body, 'appendText');
    if (appendText == null) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(
          request,
          'BAD_REQUEST',
          'Field "appendText" is required.',
          startedAt,
        ),
      );
      return;
    }

    final waitMilliseconds = body['waitMilliseconds'] is int
        ? body['waitMilliseconds'] as int
        : 1800;
    final result = await apiService.verifyMonitorTaskWrite(
      pathParameters['id']!,
      appendText: appendText,
      waitMilliseconds: waitMilliseconds,
    );
    await _writeResult(request, result, startedAt);
  }

  String? _requiredStringField(Map<String, dynamic> body, String fieldName) {
    final value = body[fieldName]?.toString();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String? _optionalStringField(Map<String, dynamic> body, String fieldName) {
    final value = body[fieldName]?.toString();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  bool? _requiredBoolField(Map<String, dynamic> body, String fieldName) {
    final value = body[fieldName];
    return value is bool ? value : null;
  }

  bool? _optionalBoolField(Map<String, dynamic> body, String fieldName) {
    final value = body[fieldName];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return null;
  }

  int? _optionalIntField(Map<String, dynamic> body, String fieldName) {
    final value = body[fieldName];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? _optionalDoubleField(Map<String, dynamic> body, String fieldName) {
    final value = body[fieldName];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String? _requiredQueryParameter(HttpRequest request, String key) {
    final value = request.uri.queryParameters[key];
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) {
      return {};
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('JSON body must be an object.');
  }

  Future<void> _writeResult(
    HttpRequest request,
    dynamic result,
    DateTime startedAt, {
    int successStatusCode = HttpStatus.ok,
  }) async {
    if (result.isErr) {
      await _writeJson(
        request,
        statusCode: HttpStatus.badRequest,
        body: _errorBody(request, 'BAD_REQUEST', result.msg, startedAt),
      );
      return;
    }

    await _writeSuccess(
      request,
      data: result.unwrap(),
      startedAt: startedAt,
      statusCode: successStatusCode,
    );
  }

  Future<void> _writeSuccess(
    HttpRequest request, {
    required Map<String, dynamic> data,
    required DateTime startedAt,
    int statusCode = HttpStatus.ok,
  }) async {
    await _writeJson(
      request,
      statusCode: statusCode,
      body: {
        'success': true,
        'code': 'OK',
        'message': 'ok',
        'data': data,
        'debug': _debugBlock(request, startedAt),
      },
    );
  }

  Map<String, dynamic> _errorBody(
    HttpRequest? request,
    String code,
    String message,
    DateTime startedAt,
  ) {
    return {
      'success': false,
      'code': code,
      'message': message,
      'data': null,
      'debug': _debugBlock(request, startedAt),
    };
  }

  Map<String, dynamic> _debugBlock(HttpRequest? request, DateTime startedAt) {
    final finishedAt = DateTime.now();
    return {
      'requestedAt': startedAt.toIso8601String(),
      'respondedAt': finishedAt.toIso8601String(),
      'durationMs': finishedAt.difference(startedAt).inMilliseconds,
      'method': request?.method,
      'path': request?.uri.path,
      'query': request?.uri.queryParameters,
      'serverPort': _port,
      'remoteAddress': request?.connectionInfo?.remoteAddress.address,
    };
  }

  Future<void> _writeJson(
    HttpRequest request, {
    required int statusCode,
    required Map<String, dynamic> body,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.write(const JsonEncoder.withIndent('  ').convert(body));
    await request.response.close();
  }

  Future<void> _writeHtml(
    HttpRequest request, {
    required int statusCode,
    required String body,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.write(body);
    await request.response.close();
  }

  bool _isLoopbackRequest(HttpRequest request) {
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null) {
      return false;
    }
    return remote.isLoopback;
  }
}
