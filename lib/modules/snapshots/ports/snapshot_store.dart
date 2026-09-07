import '../domain/snapshot.dart';

abstract interface class SnapshotStore {
  String directoryFor(String sourcePath, String monitorId);
  Future<Snapshot> create(String sourcePath, String monitorId);
  Future<List<Snapshot>> list(String sourcePath, String monitorId);
  Future<void> deleteOwned(
    String sourcePath,
    String monitorId,
    Iterable<Snapshot> snapshots,
  );
}
