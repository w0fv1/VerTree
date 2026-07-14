import 'dart:async';
import 'dart:io';
import 'package:vertree/core/monitor.dart';
import 'package:vertree/core/result.dart';
import 'package:vertree/main.dart';
import 'package:path/path.dart' as p;

class MonitManager {
  List<FileMonitTask> monitFileTasks = [];

  int get runningTaskCount {
    return monitFileTasks.where((task) => task.isRunning).length;
  }

  MonitManager() {
    final filesJson = configer.get<List<dynamic>>("monitFiles", <dynamic>[]);
    monitFileTasks = filesJson.map((e) => FileMonitTask.fromJson(e)).toList();

    for (var task in monitFileTasks) {
      if (task.isRunning) {
        _startMonitor(task);
      }
    }
  }

  Future<void> _saveMonitFiles() async {
    configer.set("monitFiles", monitFileTasks.map((t) => t.toJson()).toList());
  }

  int get runningMonitorCount {
    return monitFileTasks.where((t) => t.monitor != null).length;
  }

  Future<void> startAll() async {
    for (var task in monitFileTasks) {
      if (task.isRunning && task.monitor == null) {
        _startMonitor(task);
      }
    }
  }

  Future<Result<FileMonitTask, String>> addFileMonitTask(String path) async {
    if (monitFileTasks.any((task) => task.filePath == path)) {
      logger.info("Task already exists for: $path");
      return Result.eMsg("Task already exists for: $path");
    }

    final newTask = FileMonitTask(filePath: path, isRunning: true);

    _startMonitor(newTask);

    monitFileTasks.add(newTask);
    await _saveMonitFiles();

    return Result.ok(newTask);
  }

  Future<void> removeFileMonitTask(String path) async {
    final index = monitFileTasks.indexWhere((t) => t.filePath == path);
    if (index == -1) {
      logger.info("Task not found for: $path");
      return;
    }

    final task = monitFileTasks[index];
    _pauseMonitor(task);

    monitFileTasks.removeAt(index);
    await _saveMonitFiles();
  }

  Future<Result<FileMonitTask, String>> toggleFileMonitTaskStatus(
    FileMonitTask task,
  ) async {
    final index = monitFileTasks.indexWhere((t) => t.filePath == task.filePath);
    if (index == -1) {
      final errMsg = "Task not found for: ${task.filePath}";
      logger.error(errMsg);
      return Result.err(errMsg);
    }

    final storedTask = monitFileTasks[index];
    Result<FileMonitTask, String> result;

    if (storedTask.isRunning) {
      result = _pauseMonitor(storedTask);
    } else {
      result = _startMonitor(storedTask);
    }

    if (result.isOk) {
      await _saveMonitFiles();
    }

    return result;
  }

  Result<FileMonitTask, String> _startMonitor(FileMonitTask task) {
    if (!File(task.filePath).existsSync()) {
      logger.error(
        "Cannot start monitor: File does not exist: ${task.filePath}",
      );
      return Result.eMsg(
        "Cannot start monitor: File does not exist: ${task.filePath}",
      );
    }

    task.monitor ??= Monitor.fromTask(task);
    task.monitor?.start();
    task.isRunning = true;

    return Result.ok(task);
  }

  Result<FileMonitTask, String> _pauseMonitor(FileMonitTask task) {
    task.monitor?.stop();
    task.monitor = null;
    task.isRunning = false;

    return Result.ok(task);
  }
}

class FileMonitTask {
  String filePath;
  String? backupDirPath;
  bool isRunning;
  bool fileExists;
  late File file;
  Monitor? monitor;

  FileMonitTask({required this.filePath, this.isRunning = false})
    : fileExists = File(filePath).existsSync() {
    if (!fileExists) {
      logger.info("File does not exist: $filePath");
      isRunning = false;
      return;
    }

    file = File(filePath);
    final directory = file.parent;
    final fileName = p.basenameWithoutExtension(file.path);

    final backupDir = Directory(p.join(directory.path, '${fileName}_bak'));
    backupDirPath = backupDir.path;
  }

  Map<String, dynamic> toJson() => {
    "filePath": filePath,
    "backupDirPath": backupDirPath,
    "isRunning": isRunning,
    "fileExists": fileExists,
  };

  factory FileMonitTask.fromJson(Map<String, dynamic> json) {
    final task = FileMonitTask(
      filePath: json["filePath"],
      isRunning: json["isRunning"] ?? false,
    );
    task.fileExists = File(task.filePath).existsSync();

    if (!task.fileExists) {
      task.isRunning = false;
    }

    return task;
  }

  @override
  String toString() =>
      'FileMonitTask(filePath: $filePath, backupDirPath: $backupDirPath, isRunning: $isRunning, fileExists: $fileExists)';
}
