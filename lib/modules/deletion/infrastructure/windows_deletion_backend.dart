import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../file_access/infrastructure/windows_file_worker.dart';
import '../../../foundation/operation_control.dart';
import '../domain/deletion_models.dart';
import '../ports/deletion_backend.dart';

/// Windows-only adapter. Intent and bounded JSONL failure reports live outside
/// the selected roots; interrupted journals are displayed, never auto-resumed.
class WindowsDeletionBackend implements DeletionBackend {
  WindowsDeletionBackend(this.worker, {required this.journalDirectory});
  final WindowsFileWorker worker;
  final String journalDirectory;
  final _retryDigests = <String, String>{};

  @override
  Future<DeletionPlan> prepare(List<String> paths) async {
    final result = await worker.run({'op': 'prepare', 'paths': paths});
    return DeletionPlan(
      (result['targets'] as List).map(
        (value) => DeletionTarget(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  @override
  Future<DeletionResult> execute(
    DeletionPlan plan,
    DeletionOptions options,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  }) {
    if (options.workers < 0 || options.workers > 8) {
      throw ArgumentError('Worker count must be 0..8');
    }
    return worker.withDeviceBudget(
      plan.targets.map((target) => target.deviceKey),
      options.workers == 0 ? 8 : options.workers,
      control,
      (maximum) => _execute(
        plan,
        options,
        maximum,
        control,
        onProgress,
        retryReport: retryReport,
      ),
    );
  }

  Future<DeletionResult> _execute(
    DeletionPlan plan,
    DeletionOptions options,
    int maximumWorkers,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  }) async {
    control.checkCancelled();
    if (retryReport != null) {
      final expected = _retryDigests[retryReport];
      if (expected == null || !p.isWithin(journalDirectory, retryReport)) {
        throw const FileWorkerException(
          'RETRY_NOT_AVAILABLE',
          'Only a completed failure report from this application session may be retried. Reconfirm other selections.',
        );
      }
      final current = await sha256.bind(File(retryReport).openRead()).first;
      if ('$current' != expected) {
        throw const FileWorkerException(
          'REPORT_CHANGED',
          'The failure report changed; automatic retry was refused.',
        );
      }
    }
    final root = Directory(journalDirectory);
    await root.create(recursive: true);
    var count = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory && _isJobName(p.basename(entry.path))) count++;
      if (count >= 100) {
        throw const FileWorkerException(
          'JOURNAL_LIMIT',
          'There are 100 local deletion reports. Remove reviewed reports from the File Tools history before starting another task.',
        );
      }
    }
    final id = const Uuid().v4();
    final directory = await Directory(p.join(journalDirectory, id)).create();
    final report = File(p.join(directory.path, 'failures.jsonl'));
    await _atomicJson(File(p.join(directory.path, 'intent.json')), {
      'schemaVersion': 1,
      'owner': 'VerTree.FileTools',
      'id': id,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'running',
      'plan': plan.toJson(),
      'options': options.toJson(),
      'retryReport': retryReport,
    });
    final file = await report.open(mode: FileMode.write);
    var reportBytes = 0, previewBytes = 0;
    var reportComplete = true;
    final preview = <Map<String, dynamic>>[];
    var progress = DeletionProgress(const {});
    var checkpointAt = DateTime.now();
    DeletionResult? result;
    try {
      final response = await worker.run(
        {
          'op': 'delete',
          'confirmed': true,
          ...plan.toJson(),
          ...options.toJson(),
          'maxWorkers': maximumWorkers,
          'retryReport': ?retryReport,
        },
        control: control,
        onEvent: (event) async {
          if (event['type'] == 'progress') {
            progress = DeletionProgress(
              Map<String, dynamic>.from(event['progress'] as Map),
            );
            onProgress(progress);
            final now = DateTime.now();
            if (now.difference(checkpointAt) >= const Duration(seconds: 2)) {
              checkpointAt = now;
              await _atomicJson(
                File(p.join(directory.path, 'progress.json')),
                progress.toJson(),
                flush: false,
              );
            }
          } else if (event['type'] == 'failure') {
            final bytes = utf8.encode('${jsonEncode(event)}\n');
            if (reportBytes + bytes.length > 32 * 1024 * 1024) {
              reportComplete = false;
              control.cancel();
              return;
            }
            // Awaiting each failed record creates backpressure. Successful files
            // have no per-item journal writes and remain on the native hot path.
            await file.writeFrom(bytes);
            reportBytes += bytes.length;
            if (preview.length < 100 &&
                previewBytes + bytes.length <= 512 * 1024) {
              preview.add(Map.unmodifiable(event));
              previewBytes += bytes.length;
            }
          } else if (event['type'] == 'warning' &&
              event['code'] == 'REPORT_LIMIT') {
            reportComplete = false;
          }
        },
      );
      progress = DeletionProgress(
        Map<String, dynamic>.from(response['progress'] as Map),
      );
      reportComplete = reportComplete && response['reportComplete'] != false;
      final outcome = reportComplete
          ? response['outcome'] as String
          : 'partial';
      result = DeletionResult(
        outcome: outcome,
        plan: plan,
        progress: progress,
        reportPath: report.path,
        failures: List.unmodifiable(preview),
        message: reportComplete
            ? response['message'] as String?
            : 'Failure report limit reached. Remaining items were preserved; a new confirmation is required.',
      );
    } on FileWorkerException catch (error) {
      result = DeletionResult(
        outcome:
            error.code.contains('INTERRUPTED') ||
                error.code.contains('TIMEOUT') ||
                error.code.startsWith('PROTOCOL_')
            ? 'interrupted'
            : progress.filesDeleted + progress.directoriesDeleted > 0
            ? 'partial'
            : 'failed',
        plan: plan,
        progress: progress,
        reportPath: report.path,
        failures: List.unmodifiable(preview),
        message: '$error',
      );
      reportComplete = false;
    } catch (error) {
      result = DeletionResult(
        outcome: 'interrupted',
        plan: plan,
        progress: progress,
        reportPath: report.path,
        failures: List.unmodifiable(preview),
        message: '$error',
      );
      reportComplete = false;
    } finally {
      await file.flush();
      await file.close();
    }
    final completed = result;
    onProgress(completed.progress);
    await _atomicJson(File(p.join(directory.path, 'result.json')), {
      'schemaVersion': 1,
      'owner': 'VerTree.FileTools',
      'id': id,
      'finishedAt': DateTime.now().toUtc().toIso8601String(),
      'reportComplete': reportComplete,
      'result': completed.toJson(),
    });
    if (reportComplete && completed.outcome == 'partial') {
      _retryDigests[report.path] =
          '${await sha256.bind(report.openRead()).first}';
    }
    return completed;
  }

  static bool _isJobName(String name) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(name);

  static Future<Map<String, dynamic>> _readJson(File file) async {
    if (await file.length() > 6 * 1024 * 1024) {
      throw const FormatException('Journal record too large');
    }
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> history() async {
    final root = Directory(journalDirectory);
    if (!await root.exists()) return [];
    final records = <Map<String, dynamic>>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory || !_isJobName(p.basename(entry.path))) continue;
      if (records.length >= 100) break;
      try {
        final intent = await _readJson(File(p.join(entry.path, 'intent.json')));
        if (intent['owner'] != 'VerTree.FileTools' ||
            intent['schemaVersion'] != 1 ||
            intent['id'] != p.basename(entry.path)) {
          continue;
        }
        final resultFile = File(p.join(entry.path, 'result.json'));
        Map<String, dynamic>? result;
        if (await resultFile.exists()) {
          result =
              (await _readJson(resultFile))['result'] as Map<String, dynamic>?;
        }
        records.add({
          'id': intent['id'],
          'startedAt': intent['startedAt'],
          'outcome': result?['outcome'] ?? 'interrupted',
          'message':
              result?['message'] ??
              'Previous run ended without a terminal result. Nothing will be resumed automatically.',
          'progress': result?['progress'],
          'paths': ((intent['plan'] as Map)['targets'] as List)
              .take(10)
              .map((item) => (item as Map)['path'])
              .toList(),
          'reportPath': p.join(entry.path, 'failures.jsonl'),
          'directory': entry.path,
        });
      } catch (_) {
        // Unknown/corrupt records are never interpreted as deletion commands.
      }
    }
    records.sort(
      (a, b) => (b['startedAt'] as String).compareTo(a['startedAt'] as String),
    );
    return records;
  }

  static Future<void> _atomicJson(
    File target,
    Map<String, dynamic> value, {
    bool flush = true,
  }) async {
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: flush);
    await temporary.rename(target.path);
  }
}

/// Uses the same isolated native scanner/process-action implementation as the
/// File Locksmith page, but restricts it to identity-bound failed objects.
class WindowsDeletionObstacles implements DeletionObstacleResolver {
  WindowsDeletionObstacles(this.backend);
  final WindowsDeletionBackend backend;

  @override
  Future<DeletionObstacleResolution> resolve(
    DeletionResult previous,
    OperationControl control,
    void Function(DeletionProgress) onProgress,
  ) async {
    final reportPath = previous.reportPath;
    final expected = backend._retryDigests[reportPath];
    if (reportPath == null ||
        expected == null ||
        !p.isWithin(backend.journalDirectory, reportPath)) {
      return const DeletionObstacleResolution();
    }
    final report = File(reportPath);
    if (await report.length() > 32 * 1024 * 1024 ||
        '${await sha256.bind(report.openRead()).first}' != expected) {
      throw const FileWorkerException(
        'REPORT_CHANGED',
        'The original failure report has changed; obstacle removal was refused.',
      );
    }
    var candidates = 0, ended = 0;
    final attempted = <String>{};
    final batch = <Map<String, dynamic>>[];
    Future<void> resolveBatch() async {
      if (batch.isEmpty) return;
      control.checkCancelled();
      if (attempted.length >= 64) {
        batch.clear();
        return;
      }
      final targets = List<Map<String, dynamic>>.of(batch);
      batch.clear();
      final paths = targets.map((target) => target['path'] as String).toList();
      Map<String, dynamic> scan;
      try {
        scan = await backend.worker.run(
          {
            'op': 'scan',
            'paths': paths,
            'exactPaths': true,
            'expectedTargets': targets,
            'budgetSeconds': 20,
          },
          control: control,
          onEvent: (event) {
            if (event['type'] == 'scanProgress') {
              onProgress(
                DeletionProgress({
                  'phase': 'resolving',
                  'processesEnded': ended,
                }),
              );
            }
          },
        );
      } on FileWorkerException catch (error) {
        control.checkCancelled();
        if (error.code == 'SCAN_TARGET_UNAVAILABLE') return;
        rethrow;
      }
      for (final value in scan['processes'] as List? ?? []) {
        control.checkCancelled();
        if (attempted.length >= 64) break;
        final process = Map<String, dynamic>.from(value as Map);
        final key = '${process['pid']}:${process['creationTime']}';
        if (process['actionAllowed'] != true || !attempted.add(key)) continue;
        final matchedPaths = (process['files'] as List? ?? [])
            .map(
              (file) => p.windows
                  .normalize((file as Map)['path'] as String)
                  .toLowerCase(),
            )
            .toSet();
        final matches = targets
            .where(
              (target) => matchedPaths.contains(
                p.windows.normalize(target['path'] as String).toLowerCase(),
              ),
            )
            .toList();
        if (matches.isEmpty) continue;
        onProgress(
          DeletionProgress({'phase': 'releasing', 'processesEnded': ended}),
        );
        try {
          final action = await backend.worker.run({
            'op': 'process',
            'action': 'terminate',
            'confirmed': true,
            'automaticDelete': true,
            'exactPaths': true,
            'paths': matches.map((target) => target['path']).toList(),
            'expectedTargets': matches,
            'pid': process['pid'],
            'creationTime': process['creationTime'],
          }, control: control);
          if (action['status'] == 'exited') ended++;
        } on FileWorkerException catch (error) {
          control.checkCancelled();
          // Changed identity, insufficient rights and protected processes remain
          // untouched. The following retry records the actual remaining errors.
          if (error.code.startsWith('PROTOCOL_') ||
              error.code == 'WORKER_TIMEOUT' ||
              error.code == 'WORKER_INTERRUPTED') {
            rethrow;
          }
        }
      }
    }

    // Read all bounded failures, not only the 100-row UI preview. Batches never
    // widen a file target to its parent; directory matches are exact-only.
    await for (final line
        in report
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      control.checkCancelled();
      final entry = jsonDecode(line) as Map;
      if (entry['type'] != 'failure' ||
          !{
            'SHARING_VIOLATION',
            'ACCESS_DENIED',
            'DELETE_PENDING',
          }.contains(entry['code'])) {
        continue;
      }
      final target = Map<String, dynamic>.from(entry['target'] as Map);
      if ((target['tag'] as num? ?? 0) != 0) continue;
      if (!previous.plan.targets.any(
        (root) => _withinOriginal(target, root.data),
      )) {
        throw const FileWorkerException(
          'INVALID_REPORT',
          'A failure record is outside the confirmed object identities.',
        );
      }
      candidates++;
      batch.add(target);
      if (batch.length >= 64) await resolveBatch();
    }
    await resolveBatch();
    return DeletionObstacleResolution(
      retry: candidates > 0,
      processesEnded: ended,
    );
  }

  static bool _withinOriginal(
    Map<String, dynamic> target,
    Map<String, dynamic> root,
  ) {
    final path = p.windows.normalize(target['path'] as String).toLowerCase();
    final rootPath = p.windows.normalize(root['path'] as String).toLowerCase();
    final ids = target['ancestors'] as List? ?? const [];
    final rootIds = root['ancestors'] as List? ?? const [];
    if (ids.length < rootIds.length) return false;
    for (var index = 0; index < rootIds.length; index++) {
      if (ids[index] != rootIds[index]) return false;
    }
    if (path == rootPath) {
      return target['identity'] == root['identity'] &&
          ids.length == rootIds.length;
    }
    return root['directory'] == true &&
        (root['tag'] as num? ?? 0) == 0 &&
        p.windows.isWithin(rootPath, path) &&
        ids.length > rootIds.length &&
        ids[rootIds.length] == root['identity'];
  }
}
