import '../component/configer.dart';
import '../file_access/file_access.dart';
import '../file_access/infrastructure/local_file_access.dart';
import '../modules/monitoring/monitoring.dart';
import '../modules/monitoring/infrastructure/local_file_watcher.dart';
import '../modules/snapshots/snapshots.dart';
import '../modules/snapshots/infrastructure/local_snapshot_store.dart';
import '../modules/versions/versions.dart';
import '../foundation/app_events.dart';
import '../modules/versions/infrastructure/local_version_comparator.dart';

/// Production backend assembly. No constructor starts I/O or timers.
class AppBackend {
  AppBackend({required Configer config, required AppEvents events}) {
    versions = VersionCommands(files: files, writes: writes, emit: events.emit);
    snapshots = SnapshotCommands(
      files: files,
      store: LocalSnapshotStore(files),
      writes: writes,
      emit: events.emit,
    );
    monitors = MonitManager(
      files: files,
      snapshots: snapshots,
      watcher: LocalFileWatcher(),
      loadTasks: () => config.get<List<dynamic>>('monitorTasks', []),
      saveTasks: (tasks) async {
        config.set('monitorTasks', tasks);
        await config.flush();
      },
      interval: () => Duration(minutes: config.get<int>('monitorRate', 5)),
      maxBackups: () => config.get<int>('monitorMaxSize', 50),
      emit: events.emit,
    );
  }
  final files = LocalFileAccess();
  final writes = FileMutationCoordinator();
  late final VersionCatalog catalog = VersionCatalog(files, writes);
  late final VersionCommands versions;
  final VersionComparator comparator = LocalVersionComparator();
  late final SnapshotCommands snapshots;
  late final MonitManager monitors;
}
