import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../foundation/app_events.dart';
import '../../foundation/operation_control.dart';
import '../../modules/automation/automation.dart';
import '../../modules/deletion/deletion.dart';
import '../../modules/file_locks/file_locks.dart';

class DeletionTaskView {
  DeletionTaskView(this.job, this.plan, this.options);
  final AutomationJob job;
  final DeletionPlan plan;
  final DeletionOptions options;
  DeletionProgress progress = DeletionProgress(const {});
  DeletionResult? get result =>
      job.result is DeletionResult ? job.result as DeletionResult : null;
}

/// UI state only. All mutations go through module commands and the existing
/// application job scheduler. Navigating away does not cancel a deletion.
class FileToolsController extends ChangeNotifier {
  FileToolsController({
    required this.deletion,
    required this.locks,
    required this.jobs,
    required AppEvents events,
  }) {
    _events = events.watch().listen((event) {
      if (event.type.startsWith('job.')) _changed();
    });
  }
  final DeletionCommands deletion;
  final FileLockCommands locks;
  final AutomationJobs jobs;
  late final StreamSubscription<AppEvent> _events;
  final _tasks = <DeletionTaskView>[];
  List<DeletionTaskView> get tasks => List.unmodifiable(_tasks.reversed);
  bool preparing = false, scanning = false, acting = false;
  bool usageElevated = false;
  List<String> usagePaths = const [];
  FileUsageSnapshot? usage;
  Map<String, dynamic> scanProgress = const {};
  final _partialProcesses = <String, FileUsageProcess>{};
  List<FileUsageProcess> get processes => scanning
      ? List.unmodifiable(_partialProcesses.values)
      : usage?.processes ?? const [];
  List<Map<String, dynamic>> history = const [];
  OperationControl? _scanControl, _actionControl;
  Future<void>? _scanFuture;
  Future<List<Map<String, dynamic>>>? _actionFuture;
  bool _closed = false;
  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<DeletionPlan> prepare(List<String> paths) async {
    if (_closed || preparing) throw StateError('FILE_TOOLS_BUSY');
    preparing = true;
    _changed();
    try {
      return await deletion.prepare(List.unmodifiable(paths));
    } finally {
      preparing = false;
      _changed();
    }
  }

  DeletionTaskView start(
    DeletionPlan plan,
    DeletionOptions options, {
    required bool confirmed,
    String? retryReport,
  }) {
    if (!confirmed || _closed) throw StateError('DELETION_NOT_CONFIRMED');
    if (_tasks.any((entry) => !entry.job.completed)) {
      throw StateError('DELETE_ALREADY_RUNNING');
    }
    if (_tasks.length >= 20) _tasks.removeWhere((entry) => entry.job.completed);
    final job = jobs.start(
      'file.delete',
      (job) => deletion.execute(plan, options, job.control, (progress) {
        final entry = _tasks
            .where((entry) => entry.job.id == job.id)
            .firstOrNull;
        if (entry != null) entry.progress = progress;
        job.update(progress.percent);
        _changed();
      }, retryReport: retryReport),
    );
    job.progress = null;
    final entry = DeletionTaskView(job, plan, options);
    _tasks.add(entry);
    _changed();
    return entry;
  }

  DeletionTaskView retry(DeletionTaskView entry, {required bool confirmed}) {
    final result = entry.result;
    if (result == null ||
        result.outcome != 'partial' ||
        result.reportPath == null) {
      throw StateError('NO_RETRYABLE_RESULT');
    }
    return start(
      entry.plan,
      entry.options,
      confirmed: confirmed,
      retryReport: result.reportPath,
    );
  }

  void cancel(DeletionTaskView entry) {
    jobs.cancel(entry.job.id);
    _changed();
  }

  void pause(DeletionTaskView entry) {
    jobs.pause(entry.job.id);
    _changed();
  }

  void resume(DeletionTaskView entry) {
    jobs.resume(entry.job.id);
    _changed();
  }

  Future<void> scan(List<String> paths, {bool elevated = false}) {
    if (scanning || acting || _closed) throw StateError('FILE_TOOLS_BUSY');
    final control = OperationControl();
    _scanControl = control;
    scanning = true;
    usage = null;
    _partialProcesses.clear();
    scanProgress = const {};
    usagePaths = List.unmodifiable(paths);
    usageElevated = elevated;
    _changed();
    final future = () async {
      try {
        usage = await locks.scan(usagePaths, control, (event) {
          scanProgress = event;
          if (event['type'] == 'process') {
            final process = FileUsageProcess(
              Map<String, dynamic>.from(event['process'] as Map),
            );
            _partialProcesses['${process.pid}:${process.creationTime}'] =
                process;
          }
          _changed();
        }, elevated: elevated);
      } finally {
        scanning = false;
        _scanControl = null;
        await control.dispose();
        _changed();
      }
    }();
    _scanFuture = future;
    return future;
  }

  void cancelScan() {
    _scanControl?.cancel();
    _changed();
  }

  Future<List<Map<String, dynamic>>> act(
    List<FileUsageProcess> selected,
    FileProcessAction action, {
    required bool confirmed,
  }) {
    if (scanning ||
        acting ||
        _closed ||
        !confirmed ||
        selected.isEmpty ||
        selected.length > 32) {
      throw StateError('INVALID_PROCESS_ACTION');
    }
    final control = OperationControl();
    _actionControl = control;
    acting = true;
    _changed();
    final future = () async {
      final outcomes = <Map<String, dynamic>>[];
      try {
        for (final process in selected) {
          if (control.cancelled) break;
          try {
            outcomes.add(
              await locks.act(
                usagePaths,
                process,
                action,
                control,
                confirmed: true,
                elevated: usageElevated,
              ),
            );
          } catch (error) {
            outcomes.add({
              'pid': process.pid,
              'status': 'failed',
              'error': '$error',
            });
            // A cancelled/failed explicit action does not silently expand to the
            // remaining applications or trigger a deletion retry.
            break;
          }
        }
        return outcomes;
      } finally {
        acting = false;
        _actionControl = null;
        await control.dispose();
        _changed();
      }
    }();
    _actionFuture = future;
    return future;
  }

  void cancelAction() {
    _actionControl?.cancel();
    _changed();
  }

  Future<void> loadHistory() async {
    history = List.unmodifiable(await deletion.history());
    _changed();
  }

  Future<void> shutdown() async {
    _closed = true;
    _scanControl?.cancel();
    _actionControl?.cancel();
    for (final entry in _tasks.where((entry) => !entry.job.completed)) {
      jobs.cancel(entry.job.id);
    }
    try {
      await _scanFuture;
    } catch (_) {}
    try {
      await _actionFuture;
    } catch (_) {}
    await _events.cancel();
    super.dispose();
  }
}
