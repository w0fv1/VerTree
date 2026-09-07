import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../foundation/result.dart';
import '../../../file_access/file_access.dart';
import '../../snapshots/snapshots.dart';
import '../ports/file_watcher.dart';
import 'monitor.dart';

class MonitManager {
  MonitManager({
    required this.files,
    required this.snapshots,
    required this.watcher,
    required this.loadTasks,
    required this.saveTasks,
    required this.interval,
    required this.maxBackups,
    required this.emit,
  });
  final FileAccess files;
  final SnapshotCommands snapshots;
  final FileWatcher watcher;
  final List<dynamic> Function() loadTasks;
  final Future<void> Function(List<Map<String, dynamic>>) saveTasks;
  final Duration Function() interval;
  final int Function() maxBackups;
  final void Function(String, Map<String, dynamic>) emit;
  final _tasks = <FileMonitTask>[];
  final _archived = <FileMonitTask>[];
  FileMonitTask? taskForPath(String path) {
    for (final task in [..._tasks, ..._archived]) {
      if (p.equals(task.filePath, path)) return task;
    }
    return null;
  }

  final _changes = StreamController<int>.broadcast(sync: true);
  final _commands = FileMutationCoordinator();
  int _revision = 0;
  bool _initialized = false;
  List<FileMonitTask> get monitFileTasks => List.unmodifiable(_tasks);
  Stream<int> get changes => _changes.stream;
  int get revision => _revision;
  int get runningTaskCount =>
      _tasks.where((t) => t.runtimeStatus == 'running').length;
  int get runningMonitorCount => _tasks.where((t) => t.monitor != null).length;

  void _changed() {
    if (!_changes.isClosed) _changes.add(++_revision);
  }

  Future<void> _save() => saveTasks([
    for (final task in _tasks) task.toJson(),
    for (final task in _archived) {...task.toJson(), 'removed': true},
  ]);

  Future<void> init() async {
    if (_initialized) return;
    for (final value in loadTasks()) {
      final record = Map<String, dynamic>.from(value as Map);
      final source = await files.canonicalize(record['filePath'] as String);
      if (_tasks.any((task) => p.equals(task.filePath, source))) continue;
      final id = record['id'] as String;
      (record['removed'] == true ? _archived : _tasks).add(
        FileMonitTask._(
          id,
          source,
          snapshots.store.directoryFor(source, id),
          record['enabled'] == true,
          await files.exists(source),
        ),
      );
    }
    // Persist task definitions before the first snapshot can be written.
    await _save();
    _initialized = true;
    _changed();
  }

  Future<void> startAll() async {
    await init();
    for (final task in _tasks) {
      if (task.enabled && task.monitor == null) await _start(task);
    }
  }

  Future<Result<FileMonitTask, String>> addFileMonitTask(String path) =>
      _commands.run(['tasks'], () async {
        final source = await files.canonicalize(path);
        if (_tasks.any((task) => p.equals(task.filePath, source))) {
          return Result.eMsg('Task already exists for: $source');
        }
        if (!await files.exists(source)) {
          return Result.eMsg('File does not exist: $source');
        }
        final archived = taskForPath(source);
        final id = archived?.id ?? const Uuid().v4();
        final task = FileMonitTask._(
          id,
          source,
          snapshots.store.directoryFor(source, id),
          true,
          true,
        );
        _tasks.add(task);
        if (archived != null) _archived.remove(archived);
        try {
          await _save();
        } catch (_) {
          _tasks.remove(task);
          if (archived != null) _archived.add(archived);
          rethrow;
        }
        await _start(task);
        _changed();
        return Result.ok(task);
      });

  Future<void> removeFileMonitTask(String path) =>
      _commands.run(['tasks'], () async {
        final source = await files.canonicalize(path);
        final index = _tasks.indexWhere(
          (task) => p.equals(task.filePath, source),
        );
        if (index < 0) return;
        final task = _tasks[index];
        await task._monitor?.stop();
        task._monitor = null;
        _tasks.removeAt(index);
        _archived.add(task);
        try {
          await _save();
        } catch (_) {
          _archived.remove(task);
          _tasks.insert(index, task);
          if (task.enabled) await _start(task);
          rethrow;
        }
        _changed();
        emit('monitor.removed', {'id': task.id, 'path': task.filePath});
      });

  Future<Result<FileMonitTask, String>> toggleFileMonitTaskStatus(
    FileMonitTask task,
  ) => setEnabled(task, !task.enabled);

  Future<Result<FileMonitTask, String>> setEnabled(
    FileMonitTask task,
    bool enabled,
  ) => _commands.run(['tasks'], () async {
    if (!_tasks.contains(task)) {
      return Result.eMsg('Task not found: ${task.filePath}');
    }
    if (task.enabled == enabled) return Result.ok(task);
    if (enabled && !await files.exists(task.filePath)) {
      return Result.eMsg('File does not exist: ${task.filePath}');
    }
    final previous = task._enabled;
    task._enabled = enabled;
    try {
      await _save();
    } catch (_) {
      task._enabled = previous;
      rethrow;
    }
    if (enabled) {
      await _start(task);
    } else {
      await task._monitor?.stop();
      task._monitor = null;
    }
    _changed();
    return Result.ok(task);
  });

  Future<void> _start(FileMonitTask task) async {
    task._fileExists = await files.exists(task.filePath);
    task._monitor = Monitor(
      filePath: task.filePath,
      backupDirPath: task.backupDirPath!,
      watcher: watcher,
      interval: interval,
      emit: emit,
      onChanged: _changed,
      createSnapshot: () async => (await snapshots.create(
        task.filePath,
        task.id,
        keep: maxBackups(),
      )).path,
    );
    task._monitor!.start();
  }

  Future<List<Snapshot>> listSnapshots(FileMonitTask task) =>
      snapshots.list(task.filePath, task.id);
  Future<void> clearSnapshots(FileMonitTask task) =>
      snapshots.clear(task.filePath, task.id);

  Future<void> dispose() async {
    await _commands.close();
    await Future.wait(
      _tasks.map((task) async {
        await task._monitor?.stop();
        task._monitor = null;
      }),
    );
    await _changes.close();
  }
}

class FileMonitTask {
  FileMonitTask._(
    this.id,
    this.filePath,
    this.backupDirPath,
    this._enabled,
    this._fileExists,
  );
  final String id, filePath;
  final String? backupDirPath;
  bool _enabled, _fileExists;
  Monitor? _monitor;
  bool get enabled => _enabled;
  bool get fileExists => _fileExists;
  Monitor? get monitor => _monitor;
  String get runtimeStatus => _monitor?.status ?? 'stopped';
  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'backupDirPath': backupDirPath,
    'enabled': _enabled,
    'fileExists': _fileExists,
  };
}
