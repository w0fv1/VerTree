import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vertree/component/configer.dart';
import 'package:vertree/modules/monitoring/monitoring.dart';
import 'package:vertree/foundation/result.dart';
import 'package:vertree/service/lan_file_share_server.dart';
import 'package:vertree/modules/versions/versions.dart';
import 'package:vertree/api/version_dto.dart';

typedef CurrentPortResolver = int? Function();
typedef UiStateResolver = Map<String, dynamic> Function();
typedef UiNavigateHandler =
    Future<Result<Map<String, dynamic>, String>> Function({
      required String page,
      String? path,
      int waitMilliseconds,
      bool ensureWindowVisible,
      String? windowMode,
      double? windowWidth,
      double? windowHeight,
      bool showInitialSetupDialog,
      double? fileTreeScale,
      bool fitFileTreeToViewport,
    });
typedef UiScreenshotHandler =
    Future<Result<Map<String, dynamic>, String>> Function({
      required String outputPath,
      double pixelRatio,
      int waitMilliseconds,
      bool ensureWindowVisible,
    });
typedef UiWindowStateHandler =
    Future<Result<Map<String, dynamic>, String>> Function({
      String mode,
      double? width,
      double? height,
      bool focus,
    });
typedef UiThemeModeHandler =
    Future<Result<Map<String, dynamic>, String>> Function(String mode);
typedef FileTreeViewportHandler =
    Future<Result<Map<String, dynamic>, String>> Function({
      double? scale,
      bool fitToViewport,
    });
typedef AppQuitHandler = Future<void> Function();

class LocalHttpApiService {
  LocalHttpApiService({
    required this.configer,
    required this.versions,
    required this.comparator,
    required this.catalog,
    required this.monitManager,
    required this.lanFileShareServer,
    required this.currentVersion,
    required this.startedAt,
    required this.currentPortResolver,
    required this.currentUiStateResolver,
    required this.navigateUiHandler,
    required this.captureUiScreenshotHandler,
    required this.setWindowStateHandler,
    required this.setThemeModeHandler,
    required this.setFileTreeViewportHandler,
    required this.quitAppHandler,
  });

  final Configer configer;
  final VersionCommands versions;
  final VersionComparator comparator;
  final VersionCatalog catalog;
  final MonitManager monitManager;
  final LanFileShareServer lanFileShareServer;
  final String currentVersion;
  final DateTime startedAt;
  final CurrentPortResolver currentPortResolver;
  final UiStateResolver currentUiStateResolver;
  final UiNavigateHandler navigateUiHandler;
  final UiScreenshotHandler captureUiScreenshotHandler;
  final UiWindowStateHandler setWindowStateHandler;
  final UiThemeModeHandler setThemeModeHandler;
  final FileTreeViewportHandler setFileTreeViewportHandler;
  final AppQuitHandler quitAppHandler;

  Map<String, dynamic> health() {
    return {
      'appVersion': currentVersion,
      'startedAt': startedAt.toIso8601String(),
      'uptimeSeconds': DateTime.now().difference(startedAt).inSeconds,
      'configFilePath': configer.configFilePath,
      'httpApi': {
        'enabled': currentPortResolver() != null,
        'port': currentPortResolver(),
        'baseUrl': _baseUrl,
        'docsUrl': _baseUrl == null ? null : '$_baseUrl/docs',
        'openApiUrl': _baseUrl == null ? null : '$_baseUrl/openapi.json',
      },
      'monitoring': {
        'taskCount': monitManager.monitFileTasks.length,
        'runningTaskCount': monitManager.runningTaskCount,
      },
      'lanFileSharing': lanFileShareServer.status(),
      'config': {
        'monitorRateMinutes': configer.get<int>('monitorRate', 5),
        'monitorMaxSize': configer.get<int>('monitorMaxSize', 50),
      },
      'ui': currentUiStateResolver(),
    };
  }

  Future<Result<Map<String, dynamic>, String>> navigateUi({
    required String page,
    String? path,
    int waitMilliseconds = 400,
    bool ensureWindowVisible = true,
    String? windowMode,
    double? windowWidth,
    double? windowHeight,
    bool showInitialSetupDialog = false,
    double? fileTreeScale,
    bool fitFileTreeToViewport = false,
  }) async {
    return navigateUiHandler(
      page: page,
      path: path,
      waitMilliseconds: waitMilliseconds,
      ensureWindowVisible: ensureWindowVisible,
      windowMode: windowMode,
      windowWidth: windowWidth,
      windowHeight: windowHeight,
      showInitialSetupDialog: showInitialSetupDialog,
      fileTreeScale: fileTreeScale,
      fitFileTreeToViewport: fitFileTreeToViewport,
    );
  }

  Future<Result<Map<String, dynamic>, String>> captureUiScreenshot({
    required String outputPath,
    double pixelRatio = 1.5,
    int waitMilliseconds = 450,
    bool ensureWindowVisible = true,
  }) async {
    return captureUiScreenshotHandler(
      outputPath: outputPath,
      pixelRatio: pixelRatio,
      waitMilliseconds: waitMilliseconds,
      ensureWindowVisible: ensureWindowVisible,
    );
  }

  Future<Result<Map<String, dynamic>, String>> setWindowState({
    String mode = 'restore',
    double? width,
    double? height,
    bool focus = true,
  }) async {
    return setWindowStateHandler(
      mode: mode,
      width: width,
      height: height,
      focus: focus,
    );
  }

  Future<Result<Map<String, dynamic>, String>> setThemeMode(String mode) async {
    return setThemeModeHandler(mode);
  }

  Future<Result<Map<String, dynamic>, String>> setFileTreeViewport({
    double? scale,
    bool fitToViewport = false,
  }) async {
    return setFileTreeViewportHandler(
      scale: scale,
      fitToViewport: fitToViewport,
    );
  }

  Result<Map<String, dynamic>, String> prepareQuitApp() {
    return Result.ok({
      'requested': true,
      'message': 'app quit scheduled',
      'appVersion': currentVersion,
    });
  }

  Future<void> quitApp() async {
    await quitAppHandler();
  }

  Future<Map<String, dynamic>> listMonitorTasks() async {
    final tasks = await Future.wait(
      monitManager.monitFileTasks.map(_monitorTaskToMap),
    );
    return {
      'items': tasks,
      'count': tasks.length,
      'enabledCount': tasks.where((task) => task['enabled'] == true).length,
      'runningCount': tasks
          .where((task) => task['runtimeStatus'] == 'running')
          .length,
    };
  }

  Future<Result<Map<String, dynamic>, String>> getMonitorTask(
    String taskId,
  ) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }
    return Result.ok(await _monitorTaskToMap(task));
  }

  Future<Result<Map<String, dynamic>, String>> createMonitorTask(
    String filePath,
  ) async {
    final normalizedPath = _normalizePath(filePath);
    final result = await monitManager.addFileMonitTask(normalizedPath);
    if (result.isErr) {
      return Result.eMsg(result.msg);
    }

    return Result.ok(await _monitorTaskToMap(result.unwrap()));
  }

  Future<Result<Map<String, dynamic>, String>> updateMonitorTask(
    String taskId, {
    required bool enabled,
  }) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }

    if (task.enabled != enabled) {
      final result = await monitManager.setEnabled(task, enabled);
      if (result.isErr) {
        return Result.eMsg(result.msg);
      }
    }

    return Result.ok(await _monitorTaskToMap(task));
  }

  Future<Result<Map<String, dynamic>, String>> deleteMonitorTask(
    String taskId,
  ) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }

    final snapshot = await _monitorTaskToMap(task);
    await monitManager.removeFileMonitTask(task.filePath);
    return Result.ok(snapshot);
  }

  Future<Result<Map<String, dynamic>, String>> createVersion(
    String filePath, {
    String? label,
  }) async {
    final normalizedPath = _normalizePath(filePath);
    final backupPath = await versions.create(normalizedPath, label: label);
    final siblings = await _listTreeFamilyFiles(normalizedPath);

    return Result.ok({
      'source': await _versionEntrySummary(VersionEntry(normalizedPath)),
      'backup': await _versionEntrySummary(VersionEntry(backupPath)),
      'versionDirectory': p.dirname(normalizedPath),
      'treeFamilyFileCount': siblings.length,
      'treeFamilyFiles': siblings,
    });
  }

  Future<Result<Map<String, dynamic>, String>> listSnapshots(
    String filePath,
  ) async {
    final normalized = _normalizePath(filePath);
    final task = monitManager.taskForPath(normalized);
    final snapshots = task == null
        ? []
        : await monitManager.listSnapshots(task);
    final directory = task?.backupDirPath;
    return Result.ok({
      'sourcePath': normalized,
      'backupDirPath': directory,
      'backupDirExists':
          directory != null && await Directory(directory).exists(),
      'count': snapshots.length,
      'items': [
        for (final snapshot in snapshots)
          {..._fileMetadata(File(snapshot.path)), 'snapshotId': snapshot.id},
      ],
    });
  }

  Future<Result<Map<String, dynamic>, String>> listVersionFiles(
    String filePath,
  ) async {
    final normalizedPath = _normalizePath(filePath);
    final file = File(normalizedPath);
    if (!file.existsSync()) {
      return Result.eMsg('File does not exist: $normalizedPath');
    }

    final items = await _listTreeFamilyFiles(normalizedPath);
    return Result.ok({
      'sourcePath': normalizedPath,
      'count': items.length,
      'items': items,
    });
  }

  Future<Result<Map<String, dynamic>, String>> listMonitorTaskSnapshots(
    String taskId,
  ) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }
    return listSnapshots(task.filePath);
  }

  Future<Map<String, dynamic>> listLanFileShares() async {
    return lanFileShareServer.listShares();
  }

  Future<Result<Map<String, dynamic>, String>> createLanFileShare(
    String filePath, {
    int expiresInMinutes = LanFileShareServer.defaultExpiryMinutes,
  }) async {
    final normalizedPath = _normalizePath(filePath);
    return lanFileShareServer.createShare(
      normalizedPath,
      expiresInMinutes: expiresInMinutes,
    );
  }

  Future<Result<Map<String, dynamic>, String>> getLanFileShare(
    String token,
  ) async {
    return lanFileShareServer.getShare(token);
  }

  Result<Map<String, dynamic>, String> revokeLanFileShare(String token) {
    return lanFileShareServer.revokeShare(token);
  }

  Future<Result<Map<String, dynamic>, String>> verifyMonitorTaskWrite(
    String taskId, {
    required String appendText,
    int waitMilliseconds = 1800,
  }) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }

    final file = File(task.filePath);
    if (!file.existsSync()) {
      return Result.eMsg('File does not exist: ${task.filePath}');
    }
    if (!task.enabled || task.monitor == null) {
      return Result.eMsg('Monitor task is not running: ${task.filePath}');
    }

    final beforeTask = await _monitorTaskToMap(task);
    final beforeBackups = await listSnapshots(task.filePath);
    if (beforeBackups.isErr) {
      return Result.eMsg(beforeBackups.msg);
    }

    final marker = appendText;
    await file.writeAsString(marker, mode: FileMode.append, flush: true);
    await Future.delayed(Duration(milliseconds: waitMilliseconds));

    final afterTask = await _monitorTaskToMap(task);
    final afterBackups = await listSnapshots(task.filePath);
    if (afterBackups.isErr) {
      return Result.eMsg(afterBackups.msg);
    }

    final beforeBackupCount = (beforeTask['backupFileCount'] as int?) ?? 0;
    final afterBackupCount = (afterTask['backupFileCount'] as int?) ?? 0;

    return Result.ok({
      'taskId': taskId,
      'filePath': task.filePath,
      'appendTextLength': marker.length,
      'waitMilliseconds': waitMilliseconds,
      'before': {'task': beforeTask, 'backups': beforeBackups.unwrap()},
      'after': {'task': afterTask, 'backups': afterBackups.unwrap()},
      'verification': {
        'backupCountBefore': beforeBackupCount,
        'backupCountAfter': afterBackupCount,
        'createdNewBackup': afterBackupCount > beforeBackupCount,
        'monitorRateMinutes': configer.get<int>('monitorRate', 5),
        'monitorRuntime': afterTask['monitorRuntime'],
      },
    });
  }

  Future<Result<Map<String, dynamic>, String>> getVersionTree(
    String filePath,
  ) async {
    final normalizedPath = _normalizePath(filePath);
    final graph = await catalog.read(normalizedPath);
    return Result.ok({
      'sourcePath': normalizedPath,
      'entries': await Future.wait(graph.entries.map(_versionEntrySummary)),
      'parents': graph.parents,
      'diagnostics': graph.diagnostics,
    });
  }

  FileMonitTask? _findTaskById(String taskId) {
    for (final task in monitManager.monitFileTasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  Future<Map<String, dynamic>> _monitorTaskToMap(FileMonitTask task) async {
    final file = File(task.filePath);
    final backupDirPath = monitManager.snapshots.store.directoryFor(
      task.filePath,
      task.id,
    );
    final backupDir = Directory(backupDirPath);
    final recentBackups = (await monitManager.listSnapshots(
      task,
    )).map((snapshot) => File(snapshot.path)).toList();

    final monitor = task.monitor;

    return {
      'id': task.id,
      'filePath': task.filePath,
      'fileName': p.basename(task.filePath),
      'fileExists': file.existsSync(),
      'fileSize': file.existsSync() ? file.lengthSync() : null,
      'lastModifiedAt': file.existsSync()
          ? file.lastModifiedSync().toIso8601String()
          : null,
      'backupDirPath': backupDirPath,
      'backupDirExists': backupDir.existsSync(),
      'backupFileCount': recentBackups.length,
      'recentBackups': recentBackups.take(5).map(_fileMetadata).toList(),
      'enabled': task.enabled,
      'monitorAttached': task.monitor != null,
      'monitorId': task.id,
      'runtimeStatus': task.runtimeStatus,
      'monitorRuntime': {
        'startedAt': monitor?.startedAt?.toIso8601String(),
        'lastObservedEventAt': monitor?.lastObservedEventAt?.toIso8601String(),
        'lastObservedEventPath': monitor?.lastObservedEventPath,
        'lastBackupAt': monitor?.lastBackupTime?.toIso8601String(),
        'lastBackupPath': monitor?.lastBackupPath,
        'lastError': monitor?.lastError,
        'observedEventCount': monitor?.observedEventCount ?? 0,
        'createdBackupCountSinceStart': monitor?.createdBackupCount ?? 0,
        'isHandlingFileChange': monitor?.isHandlingFileChange ?? false,
      },
    };
  }

  Future<Map<String, dynamic>> _versionEntrySummary(VersionEntry entry) async {
    final stat = await File(entry.path).stat();
    final name = entry.name;
    return {
      'id': fileId(entry.path),
      'path': entry.path,
      'fullName': p.basename(entry.path),
      'name': name.name,
      'label': name.label,
      'extension': name.extension,
      'version': name.version.toString(),
      'branchPath': name.version.branchPath,
      'revisionNumber': name.version.revisionNumber,
      'fileSize': stat.size,
      'lastModifiedAt': stat.modified.toIso8601String(),
    };
  }

  Future<List<Map<String, dynamic>>> _listTreeFamilyFiles(String path) async {
    final graph = await catalog.read(path);
    return Future.wait(graph.entries.map(_versionEntrySummary));
  }

  Map<String, dynamic> _fileMetadata(File file) {
    final stat = file.statSync();
    return {
      'id': fileId(file.path),
      'path': file.path,
      'name': p.basename(file.path),
      'size': stat.size,
      'createdAt': stat.changed.toIso8601String(),
      'lastModifiedAt': stat.modified.toIso8601String(),
    };
  }

  String _normalizePath(String input) {
    return p.normalize(input);
  }

  String? get _baseUrl {
    final port = currentPortResolver();
    if (port == null) {
      return null;
    }
    return 'http://127.0.0.1:$port/api/v1';
  }
}
