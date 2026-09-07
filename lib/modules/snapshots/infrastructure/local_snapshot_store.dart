import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../file_access/file_access.dart';
import '../snapshots.dart';

/// A complete JSON record is the commit marker. Unknown/orphan files are
/// retained, never eligible for automatic deletion.
class LocalSnapshotStore implements SnapshotStore {
  LocalSnapshotStore(this.files);
  final FileAccess files;
  static final _uuid = RegExp(r'^[a-fA-F0-9-]{36}$');

  @override
  String directoryFor(String sourcePath, String monitorId) {
    if (!_uuid.hasMatch(monitorId)) {
      throw const FormatException('Invalid monitor id');
    }
    return p.join(p.dirname(sourcePath), '.vertree', 'snapshots', monitorId);
  }

  @override
  Future<Snapshot> create(String sourcePath, String monitorId) async {
    final directory = Directory(directoryFor(sourcePath, monitorId));
    await directory.create(recursive: true);
    final id = const Uuid().v4();
    final name = '$id${p.extension(sourcePath)}';
    final target = p.join(directory.path, name);
    await files.copyNew(sourcePath, target);
    final created = DateTime.now().toUtc();
    final size = await File(target).length();
    final staged = File(p.join(directory.path, '$id.json.tmp'));
    await staged.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'id': id,
        'monitorId': monitorId,
        'sourcePath': sourcePath,
        'fileName': name,
        'createdAt': created.toIso8601String(),
        'size': size,
      }),
      flush: true,
    );
    await staged.rename(p.join(directory.path, '$id.json'));
    return Snapshot(
      id: id,
      monitorId: monitorId,
      sourcePath: sourcePath,
      path: target,
      createdAt: created,
      size: size,
    );
  }

  @override
  Future<List<Snapshot>> list(String sourcePath, String monitorId) async {
    final result = <Snapshot>[];
    final directory = Directory(directoryFor(sourcePath, monitorId));
    if (await directory.exists()) {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File || !entry.path.endsWith('.json')) continue;
        try {
          final record =
              jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
          final name = record['fileName'] as String;
          final id = record['id'] as String;
          if (record['schemaVersion'] != 1 ||
              record['monitorId'] != monitorId ||
              record['sourcePath'] != sourcePath ||
              !_uuid.hasMatch(id) ||
              p.basename(entry.path) != '$id.json' ||
              p.basename(name) != name ||
              name != '$id${p.extension(sourcePath)}') {
            continue;
          }
          final target = p.join(directory.path, name);
          if (await FileSystemEntity.type(target, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          final size = await File(target).length();
          if (size != record['size']) continue;
          result.add(
            Snapshot(
              id: id,
              monitorId: monitorId,
              sourcePath: sourcePath,
              path: target,
              createdAt: DateTime.parse(record['createdAt'] as String),
              size: size,
            ),
          );
        } catch (_) {
          /* Unrecognized records remain untouched. */
        }
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(result);
  }

  @override
  Future<void> deleteOwned(
    String sourcePath,
    String monitorId,
    Iterable<Snapshot> snapshots,
  ) async {
    final directory = directoryFor(sourcePath, monitorId);
    // Re-read verified records instead of trusting caller-provided paths.
    final ids = snapshots.map((s) => s.id).toSet();
    final verified = await list(sourcePath, monitorId);
    for (final snapshot in verified.where((s) => ids.contains(s.id))) {
      if (!p.isWithin(directory, snapshot.path)) continue;
      await File(snapshot.path).delete();
      await File(p.join(directory, '${snapshot.id}.json')).delete();
    }
  }
}
