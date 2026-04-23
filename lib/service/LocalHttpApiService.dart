import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vertree/component/Configer.dart';
import 'package:vertree/core/FileVersionTree.dart';
import 'package:vertree/core/MonitManager.dart';
import 'package:vertree/core/Result.dart';
import 'package:vertree/core/TreeBuilder.dart';
import 'package:vertree/service/LanFileShareServer.dart';

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
        'enabled': configer.get<bool>('localHttpApiEnabled', true),
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

  Map<String, dynamic> listMonitorTasks() {
    final tasks = monitManager.monitFileTasks.map(_monitorTaskToMap).toList();
    return {
      'items': tasks,
      'count': tasks.length,
      'runningCount': tasks.where((task) => task['isRunning'] == true).length,
    };
  }

  Result<Map<String, dynamic>, String> getMonitorTask(String taskId) {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }
    return Result.ok(_monitorTaskToMap(task));
  }

  Future<Result<Map<String, dynamic>, String>> createMonitorTask(
    String filePath,
  ) async {
    final normalizedPath = _normalizePath(filePath);
    final result = await monitManager.addFileMonitTask(normalizedPath);
    if (result.isErr) {
      return Result.eMsg(result.msg);
    }

    return Result.ok(_monitorTaskToMap(result.unwrap()));
  }

  Future<Result<Map<String, dynamic>, String>> updateMonitorTask(
    String taskId, {
    required bool isRunning,
  }) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }

    if (task.isRunning != isRunning) {
      final result = await monitManager.toggleFileMonitTaskStatus(task);
      if (result.isErr) {
        return Result.eMsg(result.msg);
      }
    }

    return Result.ok(_monitorTaskToMap(task));
  }

  Future<Result<Map<String, dynamic>, String>> deleteMonitorTask(
    String taskId,
  ) async {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }

    final snapshot = _monitorTaskToMap(task);
    await monitManager.removeFileMonitTask(task.filePath);
    return Result.ok(snapshot);
  }

  Future<Result<Map<String, dynamic>, String>> createBackup(
    String filePath, {
    String? label,
  }) async {
    final normalizedPath = _normalizePath(filePath);
    final file = File(normalizedPath);
    if (!file.existsSync()) {
      return Result.eMsg('File does not exist: $normalizedPath');
    }

    final sourceNode = FileNode(normalizedPath);
    final result = await sourceNode.safeBackup(label);
    if (result.isErr) {
      return Result.eMsg(result.msg);
    }

    final backupNode = result.unwrap();
    final siblings = _listTreeFamilyFiles(sourceNode.mate.fullPath);

    return Result.ok({
      'source': _fileNodeSummary(sourceNode),
      'backup': _fileNodeSummary(backupNode),
      'backupDirectory': _deriveBackupDirectory(normalizedPath),
      'treeFamilyFileCount': siblings.length,
      'treeFamilyFiles': siblings,
    });
  }

  Result<Map<String, dynamic>, String> listBackups(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    final file = File(normalizedPath);
    if (!file.existsSync()) {
      return Result.eMsg('File does not exist: $normalizedPath');
    }

    final backupDirPath = _deriveBackupDirectory(normalizedPath);
    final backupDir = Directory(backupDirPath);
    final backups = backupDir.existsSync()
        ? backupDir.listSync().whereType<File>().map(_fileMetadata).toList()
        : <Map<String, dynamic>>[];

    backups.sort(
      (a, b) => ((b['lastModifiedAt'] as String?) ?? '').compareTo(
        ((a['lastModifiedAt'] as String?) ?? ''),
      ),
    );

    return Result.ok({
      'sourcePath': normalizedPath,
      'backupDirPath': backupDirPath,
      'backupDirExists': backupDir.existsSync(),
      'count': backups.length,
      'items': backups,
    });
  }

  Result<Map<String, dynamic>, String> listVersionFiles(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    final file = File(normalizedPath);
    if (!file.existsSync()) {
      return Result.eMsg('File does not exist: $normalizedPath');
    }

    final items = _listTreeFamilyFiles(normalizedPath);
    return Result.ok({
      'sourcePath': normalizedPath,
      'count': items.length,
      'items': items,
    });
  }

  Result<Map<String, dynamic>, String> listMonitorTaskBackups(String taskId) {
    final task = _findTaskById(taskId);
    if (task == null) {
      return Result.eMsg('Monitor task not found: $taskId');
    }
    return listBackups(task.filePath);
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
    if (!task.isRunning || task.monitor == null) {
      return Result.eMsg('Monitor task is not running: ${task.filePath}');
    }

    final beforeTask = _monitorTaskToMap(task);
    final beforeBackups = listBackups(task.filePath);
    if (beforeBackups.isErr) {
      return Result.eMsg(beforeBackups.msg);
    }

    final marker = appendText;
    await file.writeAsString(marker, mode: FileMode.append, flush: true);
    await Future.delayed(Duration(milliseconds: waitMilliseconds));

    final afterTask = _monitorTaskToMap(task);
    final afterBackups = listBackups(task.filePath);
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
    final result = await buildTree(normalizedPath);
    if (result.isErr) {
      return Result.eMsg(result.msg);
    }

    final root = result.unwrap();
    final summary = _summarizeTree(root);
    return Result.ok({
      'sourcePath': normalizedPath,
      'summary': summary,
      'root': _treeNodeToMap(root),
    });
  }

  String encodeTaskId(String filePath) {
    return base64Url.encode(utf8.encode(_normalizePath(filePath)));
  }

  String? decodeTaskId(String taskId) {
    try {
      return utf8.decode(base64Url.decode(taskId));
    } catch (_) {
      return null;
    }
  }

  FileMonitTask? _findTaskById(String taskId) {
    final decodedPath = decodeTaskId(taskId);
    if (decodedPath == null) {
      return null;
    }

    final normalizedPath = _normalizePath(decodedPath);
    for (final task in monitManager.monitFileTasks) {
      if (_normalizePath(task.filePath) == normalizedPath) {
        return task;
      }
    }
    return null;
  }

  Map<String, dynamic> _monitorTaskToMap(FileMonitTask task) {
    final file = File(task.filePath);
    final backupDirPath =
        task.backupDirPath ?? _deriveBackupDirectory(task.filePath);
    final backupDir = Directory(backupDirPath);
    final recentBackups = backupDir.existsSync()
        ? backupDir.listSync().whereType<File>().toList()
        : <File>[];

    recentBackups.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    final monitor = task.monitor;

    return {
      'id': encodeTaskId(task.filePath),
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
      'isRunning': task.isRunning,
      'monitorAttached': task.monitor != null,
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

  Map<String, dynamic> _fileNodeSummary(FileNode node) {
    return {
      'path': node.mate.fullPath,
      'fullName': node.mate.fullName,
      'name': node.mate.name,
      'label': node.mate.label,
      'extension': node.mate.extension,
      'version': node.mate.version.toString(),
      'branchPath': node.mate.version.branchPath,
      'revisionNumber': node.mate.version.revisionNumber,
      'fileSize': node.mate.fileSize,
      'createdAt': node.mate.creationTime.toIso8601String(),
      'lastModifiedAt': node.mate.lastModifiedTime.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _listTreeFamilyFiles(String filePath) {
    final selectedMeta = FileMeta(filePath);
    final directory = Directory(p.dirname(filePath));
    if (!directory.existsSync()) {
      return [];
    }

    final files = <Map<String, dynamic>>[];
    for (final entity in directory.listSync()) {
      if (entity is! File) {
        continue;
      }
      if (!FileMeta.isSupportedTreeFilePath(entity.path)) {
        continue;
      }
      final meta = FileMeta(entity.path);
      if (meta.name == selectedMeta.name &&
          meta.extension == selectedMeta.extension) {
        files.add(_fileMetadata(entity));
      }
    }

    files.sort(
      (a, b) => ((a['name'] as String?) ?? '').compareTo(
        (b['name'] as String?) ?? '',
      ),
    );
    return files;
  }

  Map<String, dynamic> _treeNodeToMap(FileNode node) {
    return {
      'path': node.mate.fullPath,
      'fullName': node.mate.fullName,
      'name': node.mate.name,
      'label': node.mate.label,
      'extension': node.mate.extension,
      'version': node.mate.version.toString(),
      'child': node.child == null ? null : _treeNodeToMap(node.child!),
      'branches': node.branches.map(_treeNodeToMap).toList(),
    };
  }

  Map<String, dynamic> _summarizeTree(FileNode root) {
    var totalNodes = 0;
    var branchNodes = 0;
    FileNode? latest;

    void walk(FileNode node) {
      totalNodes += 1;
      latest =
          latest == null ||
              latest!.mate.version.compareTo(node.mate.version) < 0
          ? node
          : latest;
      branchNodes += node.branches.length;
      if (node.child != null) {
        walk(node.child!);
      }
      for (final branch in node.branches) {
        walk(branch);
      }
    }

    walk(root);

    return {
      'rootVersion': root.mate.version.toString(),
      'latestVersion': latest?.mate.version.toString(),
      'totalNodes': totalNodes,
      'branchNodes': branchNodes,
    };
  }

  Map<String, dynamic> _fileMetadata(File file) {
    final stat = file.statSync();
    return {
      'path': file.path,
      'name': p.basename(file.path),
      'size': stat.size,
      'createdAt': stat.changed.toIso8601String(),
      'lastModifiedAt': stat.modified.toIso8601String(),
    };
  }

  String _deriveBackupDirectory(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    final directory = p.dirname(normalizedPath);
    final fileName = p.basenameWithoutExtension(normalizedPath);
    return p.join(directory, '${fileName}_bak');
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
