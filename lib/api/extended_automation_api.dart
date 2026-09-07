import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../component/configer.dart';
import '../foundation/result.dart';
import '../foundation/app_events.dart';
import '../modules/automation/automation.dart';
import '../service/file_preview_image_service.dart';
import '../service/local_http_api_service.dart';
import '../modules/preview/preview.dart';
import '../modules/versions/versions.dart';
import 'version_dto.dart';
import 'automation_routes.dart';
import 'api_protocol.dart';
import 'local_http_api_contract.dart';

typedef ApiAction = FutureOr<Object?> Function(Map<String, dynamic> body);

class ExtendedAutomationApi {
  ExtendedAutomationApi({
    required this.service,
    required this.events,
    required this.preview,
    required this.jobs,
    required this.images,
    required this.config,
    required this.openPreview,
    required this.closePreview,
    required this.diagnostics,
  }) : versions = service.versions;
  final LocalHttpApiService service;
  final Configer config;
  final Future<void> Function(String path) openPreview;
  final Future<void> Function() closePreview;
  final Map<String, dynamic> Function() diagnostics;
  final AutomationJobs jobs;
  final VersionCommands versions;
  final FilePreviewImageService images;
  final AppEvents events;
  final PreviewActivity preview;

  Object? unwrap(Result<Map<String, dynamic>, String> result) {
    if (result.isErr) throw ApiFailure(422, 'OPERATION_FAILED', result.msg);
    return result.unwrap();
  }

  Map<String, ApiAction> get actions => {
    'backup': (body) async => unwrap(
      await service.createVersion(path(body), label: body['label'] as String?),
    ),
    'monitor': (body) async =>
        unwrap(await service.createMonitorTask(path(body))),
    'share': (body) async => unwrap(
      await service.lanFileShareServer.createShare(
        path(body),
        expiresInMinutes: body['expiresInMinutes'] as int? ?? 30,
      ),
    ),
    'restore': (body) async => restoreDto(
      await versions.restore(
        path(body),
        targetPath: body['targetPath'] as String?,
      ),
    ),
    'compare': (body) async => comparisonDto(
      await service.comparator.compare(
        path(body, 'leftPath'),
        path(body, 'rightPath'),
      ),
    ),
  };

  String path(Map<String, dynamic> body, [String field = 'path']) {
    final value = body[field];
    if (value is! String || !p.isAbsolute(value)) {
      throw FormatException('$field must be an absolute local path');
    }
    return p.normalize(value);
  }

  Future<List<Map<String, dynamic>>> batch(
    Map<String, dynamic> body, {
    AutomationJob? job,
  }) async {
    final operations = body['operations'];
    if (operations is! List || operations.isEmpty || operations.length > 100) {
      throw const FormatException('operations must contain 1–100 actions');
    }
    final results = <Map<String, dynamic>>[];
    for (var index = 0; index < operations.length; index++) {
      job?.checkCancelled();
      try {
        final item = Map<String, dynamic>.from(operations[index] as Map);
        final action = actions[item['action']];
        if (action == null) {
          throw const FormatException(
            'Supported actions: backup, monitor, share, restore, compare',
          );
        }
        results.add({
          'index': index,
          'success': true,
          'data': await action(item),
        });
      } catch (error) {
        results.add({
          'index': index,
          'success': false,
          'message': error.toString(),
        });
      }
      if (job != null) {
        job.result = List.of(results);
        job.update((index + 1) / operations.length);
      }
    }
    return results;
  }

  Map<String, dynamic> settings() => {
    'monitorRateMinutes': config.get<int>('monitorRate', 5),
    'monitorMaxBackups': config.get<int>('monitorMaxSize', 50),
    'themeMode': config.get<String>('themeMode', 'system'),
    'launchToTray': config.get<bool>('launch2Tray', true),
  };

  Future<Object?> updateSettings(Map<String, dynamic> body) async {
    const keys = [
      'monitorRateMinutes',
      'monitorMaxBackups',
      'themeMode',
      'launchToTray',
    ];
    if (body.isEmpty || body.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown or empty settings patch');
    }
    for (final key in ['monitorRateMinutes', 'monitorMaxBackups']) {
      if (body.containsKey(key) &&
          (body[key] is! int ||
              body[key] < (key == 'monitorRateMinutes' ? 0 : 1))) {
        throw FormatException('Invalid $key');
      }
    }
    if (body.containsKey('launchToTray') && body['launchToTray'] is! bool) {
      throw const FormatException('launchToTray must be boolean');
    }
    if (body.containsKey('themeMode') &&
        !['system', 'light', 'dark'].contains(body['themeMode'])) {
      throw const FormatException('Invalid themeMode');
    }
    if (body.containsKey('themeMode')) {
      unwrap(await service.setThemeModeHandler(body['themeMode'] as String));
    }
    if (body.containsKey('monitorRateMinutes')) {
      config.set('monitorRate', body['monitorRateMinutes']);
    }
    if (body.containsKey('monitorMaxBackups')) {
      config.set('monitorMaxSize', body['monitorMaxBackups']);
    }
    if (body.containsKey('launchToTray')) {
      config.set('launch2Tray', body['launchToTray']);
    }
    await config.flush();
    final result = settings();
    events.emit('settings.updated', result);
    return result;
  }

  List<LocalHttpApiRoute> get routes => [
    ...previewImageRoutes(images.render),
    route(
      'GET',
      '/preview-capabilities',
      'Read format and PNG capabilities',
      (request, params) async {
        final data =
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/office_viewer/capabilities.json',
                  ),
                )
                as Map<String, dynamic>;
        data['backgroundImageAvailable'] =
            await FilePreviewImageService.available();
        final filePath = request.uri.queryParameters['path'];
        if (filePath != null) {
          final normalized = path({'path': filePath});
          final file = File(normalized);
          final stat = await file.stat();
          if (stat.type != FileSystemEntityType.file) {
            throw FileSystemException('Not a regular file', normalized);
          }
          final viewers = (data['viewers'] as List)
              .cast<Map<String, dynamic>>();
          final name = p.basename(normalized).toLowerCase();
          final matches = viewers.where(
            (item) => (item['extensions'] as List).any(
              (extension) => name.endsWith('.$extension'),
            ),
          );
          if (matches.isNotEmpty) {
            data['file'] = {
              'path': normalized,
              'viewer': matches.first,
              'support': 'declared',
              'decodingRequired': true,
            };
          } else {
            data['file'] = {
              'path': normalized,
              ...await images.inspect(normalized),
              'support': 'detected',
              'decodingRequired': false,
            };
          }
        }
        return data;
      },
      query: [field('path', 'string', 'Optional absolute file path')],
    ),
    route(
      'GET',
      '/previews/current',
      'Read interactive preview state',
      (request, params) => preview.snapshot,
    ),
    route(
      'POST',
      '/previews',
      'Open or replace the interactive preview',
      (request, params) async {
        final filePath = path(await apiBody(request));
        if (!await File(filePath).exists()) {
          throw FileSystemException('File not found', filePath);
        }
        await openPreview(filePath);
        return preview.snapshot;
      },
      fields: [field('path', 'string', 'Absolute file path', required: true)],
    ),
    route('DELETE', '/previews/current', 'Close interactive preview', (
      request,
      params,
    ) async {
      await closePreview();
      return preview.snapshot;
    }),
    route(
      'POST',
      '/versions/{id}/restore',
      'Restore a version with a backup of current contents',
      (request, params) async {
        final body = await apiBody(request);
        return restoreDto(
          await versions.restore(
            filePathFromId(params['id']!),
            targetPath: body['targetPath'] as String?,
          ),
        );
      },
      fields: [
        field(
          'targetPath',
          'string',
          'Optional save-as path; defaults to the unversioned file',
        ),
      ],
    ),
    route(
      'PATCH',
      '/versions/{id}',
      'Update a version label',
      (request, params) async {
        final body = await apiBody(request);
        if (!body.containsKey('label')) {
          throw const FormatException(
            'label is required; use an empty string to clear it',
          );
        }
        final source = filePathFromId(params['id']!);
        final target = await versions.renameLabel(
          source,
          body['label'] as String?,
        );
        return {
          'id': fileId(target),
          'path': target,
          'previousPath': source,
          'label': body['label'],
        };
      },
      fields: [
        field(
          'label',
          'string',
          'New label; changing it renames the file and changes its id',
          required: true,
        ),
      ],
    ),
    route(
      'POST',
      '/version-comparisons',
      'Compare file hashes and UTF-8 text',
      (request, params) async {
        final body = await apiBody(request);
        return comparisonDto(
          await service.comparator.compare(
            path(body, 'leftPath'),
            path(body, 'rightPath'),
          ),
        );
      },
      fields: [
        field('leftPath', 'string', 'Absolute left path', required: true),
        field('rightPath', 'string', 'Absolute right path', required: true),
      ],
    ),
    route(
      'GET',
      '/settings',
      'Read supported application settings',
      (request, params) => settings(),
    ),
    route(
      'PATCH',
      '/settings',
      'Apply and persist supported settings',
      (request, params) async => updateSettings(await apiBody(request)),
      fields: [
        field(
          'monitorRateMinutes',
          'integer',
          'Minimum interval in minutes, zero allows every change',
        ),
        field(
          'monitorMaxBackups',
          'integer',
          'Positive backup retention count',
        ),
        field('themeMode', 'string', 'system, light, dark'),
        field('launchToTray', 'boolean', 'Start in tray on startup launches'),
      ],
    ),
    route(
      'POST',
      '/batch',
      'Execute actions independently with per-item results',
      (request, params) async => {'items': await batch(await apiBody(request))},
      fields: [
        field(
          'operations',
          'array',
          '1–100 objects: action plus its parameters',
          required: true,
        ),
      ],
    ),
    route(
      'GET',
      '/jobs',
      'List recent asynchronous jobs',
      (request, params) => {'items': jobs.list()},
    ),
    route('GET', '/jobs/{id}', 'Read job progress and result', (
      request,
      params,
    ) {
      final job = jobs.get(params['id']!);
      if (job == null) throw ApiFailure(404, 'JOB_NOT_FOUND', 'Job not found');
      return job.toJson();
    }),
    route(
      'POST',
      '/jobs',
      'Start an asynchronous operation',
      (request, params) async {
        final body = await apiBody(request);
        final kind = body['action'] as String?;
        if (kind != 'batch' && !actions.containsKey(kind)) {
          throw const FormatException('Unknown job action');
        }
        return jobs
            .start(
              kind!,
              (job) => kind == 'batch'
                  ? batch(body, job: job)
                  : Future.sync(() => actions[kind]!(body)),
            )
            .toJson();
      },
      fields: [
        field(
          'action',
          'string',
          'batch, backup, monitor, share, restore or compare',
          required: true,
        ),
        field('path', 'string', 'Action path'),
        field('label', 'string', 'Backup label'),
        field('targetPath', 'string', 'Restore target'),
        field('leftPath', 'string', 'Comparison left file'),
        field('rightPath', 'string', 'Comparison right file'),
        field('operations', 'array', 'Batch actions'),
        field('expiresInMinutes', 'integer', 'Share lifetime'),
      ],
      success: 202,
    ),
    route(
      'DELETE',
      '/jobs/{id}',
      'Request cancellation between safe operation boundaries',
      (request, params) {
        if (jobs.get(params['id']!) == null) {
          throw ApiFailure(404, 'JOB_NOT_FOUND', 'Job not found');
        }
        return jobs.cancel(params['id']!).toJson();
      },
    ),
    route(
      'GET',
      '/diagnostics',
      'Read runtime and preview diagnostics',
      (request, params) => {
        ...diagnostics(),
        'jobs': jobs.list(),
        'lastEventId': events.lastId,
        'recentErrors': events.recent
            .where(
              (event) =>
                  event.type.endsWith('.error') ||
                  event.type.endsWith('.failed'),
            )
            .map((event) => event.toJson())
            .toList(),
        'preview': preview.snapshot,
      },
    ),
    LocalHttpApiRoute(
      method: 'GET',
      pathTemplate: '/events',
      summary: 'Subscribe to server-sent events',
      description:
          'SSE with Last-Event-ID replay of the latest 256 events. An expired cursor returns 409. Cursors include a session ID and expire on application restart.',
      tags: const ['automation'],
      responseContentType: 'text/event-stream',
      handler: apiGuard((request, params, start) async {
        final raw = request.headers.value('Last-Event-ID');
        final parts = raw?.split(':');
        final after = parts == null || parts.length != 2
            ? null
            : int.tryParse(parts.last);
        if (raw != null && after == null) {
          throw const FormatException(
            'Last-Event-ID must be sessionId:sequence',
          );
        }
        late Stream<AppEvent> stream;
        try {
          stream = events.watch(after: after, session: parts?.first);
        } catch (error) {
          throw ApiFailure(409, 'EVENT_CURSOR_EXPIRED', error.toString());
        }
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.headers.set('Cache-Control', 'no-cache');
        request.response.bufferOutput = false;
        request.response.write(': connected\n\n');
        await request.response.flush();
        final finished = Completer<void>();
        Future<void> writes = Future.value();
        var queued = 0;
        void send(String message) {
          if (finished.isCompleted) return;
          if (++queued > 256) {
            finished.complete();
            return;
          }
          writes = writes
              .then((_) async {
                if (!finished.isCompleted) {
                  request.response.write(message);
                  await request.response.flush().timeout(
                    const Duration(seconds: 5),
                  );
                }
                queued--;
              })
              .catchError((Object error) {
                if (!finished.isCompleted) finished.complete();
              });
        }

        final subscription = stream.listen(
          (event) => send(
            'id: ${event.sessionId}:${event.id}\nevent: ${event.type}\ndata: ${jsonEncode(event.toJson())}\n\n',
          ),
        );
        final heartbeat = Timer.periodic(
          const Duration(seconds: 10),
          (_) => send(': heartbeat\n\n'),
        );
        unawaited(
          request.response.done.then(
            (_) {
              if (!finished.isCompleted) finished.complete();
            },
            onError: (Object error) {
              if (!finished.isCompleted) finished.complete();
            },
          ),
        );
        await finished.future;
        heartbeat.cancel();
        await subscription.cancel();
        await writes;
        await request.response.close();
      }),
    ),
  ];

  LocalHttpApiField field(
    String name,
    String type,
    String description, {
    bool required = false,
  }) => LocalHttpApiField(
    name: name,
    type: type,
    description: description,
    required: required,
  );

  LocalHttpApiRoute route(
    String method,
    String path,
    String summary,
    FutureOr<Object?> Function(HttpRequest request, Map<String, String> params)
    handle, {
    List<LocalHttpApiField>? fields,
    List<LocalHttpApiField> query = const [],
    int success = 200,
  }) => LocalHttpApiRoute(
    method: method,
    pathTemplate: path,
    summary: summary,
    description: summary,
    tags: const ['automation'],
    successStatusCode: success,
    pathParameters: path.contains('{id}')
        ? [
            field(
              'id',
              'string',
              path.startsWith('/versions')
                  ? 'base64url encoded absolute file path; returned by version queries'
                  : 'Job ID',
              required: true,
            ),
          ]
        : const [],
    queryParameters: query,
    requestBody: fields == null
        ? null
        : LocalHttpApiRequestBody(description: summary, fields: fields),
    handler: apiGuard(
      (request, params, start) async =>
          apiJson(request, await handle(request, params), status: success),
    ),
  );
}
