import 'package:path/path.dart' as p;
import '../../../file_access/file_access.dart';
import '../domain/snapshot.dart';
import '../ports/snapshot_store.dart';

class SnapshotCommands {
  SnapshotCommands({
    required this.store,
    required this.files,
    required this.writes,
    required this.emit,
  });
  final SnapshotStore store;
  final FileAccess files;
  final FileMutationCoordinator writes;
  final void Function(String type, Map<String, dynamic> data) emit;

  Future<Snapshot> create(
    String source,
    String monitorId, {
    required int keep,
  }) async => writes.run(
    [await files.canonicalize(p.dirname(source)), 'snapshots:$monitorId'],
    () async {
      final snapshot = await store.create(source, monitorId);
      emit('snapshot.created', {
        'path': source,
        'backupPath': snapshot.path,
        'source': 'monitor',
      });
      try {
        final owned = (await store.list(source, monitorId)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await store.deleteOwned(
          source,
          monitorId,
          owned.skip(keep < 1 ? 1 : keep),
        );
      } catch (error) {
        // The backup is committed. A retention failure must not turn it into
        // a failed backup or advance a retry loop that creates duplicates.
        emit('snapshot.retention-failed', {
          'monitorId': monitorId,
          'message': error.toString(),
        });
      }
      return snapshot;
    },
  );

  Future<List<Snapshot>> list(String source, String monitorId) =>
      writes.run(['snapshots:$monitorId'], () => store.list(source, monitorId));
  Future<void> clear(String source, String monitorId) =>
      writes.run(['snapshots:$monitorId'], () async {
        final owned = (await store.list(source, monitorId));
        await store.deleteOwned(source, monitorId, owned);
        emit('snapshots.deleted', {'monitorId': monitorId});
      });
}
