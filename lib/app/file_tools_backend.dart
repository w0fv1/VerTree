import 'package:path/path.dart' as p;
import '../file_access/file_access.dart';
import '../file_access/infrastructure/windows_file_worker.dart';
import '../modules/deletion/deletion.dart';
import '../modules/deletion/infrastructure/windows_deletion_backend.dart';
import '../modules/file_locks/file_locks.dart';
import '../modules/file_locks/infrastructure/windows_file_lock_backend.dart';
import '../modules/monitoring/monitoring.dart';

class FileToolsBackend {
  FileToolsBackend({
    required FileMutationCoordinator writes,
    required MonitManager monitors,
    required String configurationDirectory,
    required Future<void> Function(List<String>) releasePresentations,
    String? workerExecutable,
  }) {
    final journal = p.join(configurationDirectory, 'file-tools', 'jobs');
    worker = WindowsFileWorker(
      executable: workerExecutable,
      protectedPaths: [configurationDirectory],
    );
    final nativeDeletion = WindowsDeletionBackend(
      worker,
      journalDirectory: journal,
    );
    deletion = DeletionCommands(
      writes: writes,
      backend: nativeDeletion,
      obstacles: WindowsDeletionObstacles(nativeDeletion),
      usage: _AppDeletionUsageGuard(worker, monitors, releasePresentations),
    );
    locks = FileLockCommands(WindowsFileLockBackend(worker));
  }
  late final WindowsFileWorker worker;
  late final DeletionCommands deletion;
  late final FileLockCommands locks;
}

class _AppDeletionUsageGuard implements DeletionUsageGuard {
  _AppDeletionUsageGuard(this.worker, this.monitors, this.releasePresentations);
  final WindowsFileWorker worker;
  final MonitManager monitors;
  final Future<void> Function(List<String>) releasePresentations;
  Future<String?> identity(String path) async {
    try {
      final value = await worker.run({
        'op': 'prepare',
        'paths': [path],
      });
      return ((value['targets'] as List).single as Map)['identity'] as String;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Future<void> Function()> quiesce(List<String> paths) async {
    final identities = <String, String?>{};
    for (final task in monitors.monitFileTasks) {
      if (paths.any(
        (path) => MutationScope.containsPath(path, task.filePath),
      )) {
        identities[task.filePath] = await identity(task.filePath);
      }
    }
    final release = await monitors.suspendPaths(
      paths,
      canResume: (path) async {
        final expected = identities[path];
        return expected != null && await identity(path) == expected;
      },
    );
    try {
      await releasePresentations(paths);
      return release;
    } catch (_) {
      await release();
      rethrow;
    }
  }
}
