class Snapshot {
  const Snapshot({
    required this.id,
    required this.monitorId,
    required this.sourcePath,
    required this.path,
    required this.createdAt,
    required this.size,
  });
  final String id, monitorId, sourcePath, path;
  final DateTime createdAt;
  final int size;
}
