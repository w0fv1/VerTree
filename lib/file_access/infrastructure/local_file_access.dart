import 'dart:io';
import 'package:path/path.dart' as p;
import '../../foundation/operation_failure.dart';
import '../file_access.dart';
import 'publish_file.dart';

class LocalFileAccess implements FileAccess {
  @override
  Future<String> canonicalize(String path) async {
    final absolute = p.normalize(p.absolute(path));
    if (await FileSystemEntity.type(absolute) !=
        FileSystemEntityType.notFound) {
      return File(absolute).resolveSymbolicLinks();
    }
    final parent = p.dirname(absolute);
    if (parent == absolute) return absolute;
    return p.join(await canonicalize(parent), p.basename(absolute));
  }

  @override
  Future<bool> exists(String path) => File(path).exists();
  @override
  Future<List<String>> files(String directory) async =>
      (await Directory(directory).list(followLinks: false).toList())
          .whereType<File>()
          .map((file) => file.path)
          .toList();
  @override
  Future<FileFingerprint> fingerprint(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw OperationFailure('NOT_FOUND', 'File not found: $path');
    }
    return FileFingerprint(stat.size, stat.modified, stat.changed);
  }

  Future<File> _stage(String source, String target, Directory temporary) async {
    final before = await fingerprint(source);
    final staged = await File(source).copy(p.join(temporary.path, 'content'));
    if (before != await fingerprint(source)) {
      throw const OperationFailure(
        'SOURCE_CHANGED',
        'Source changed while copying',
      );
    }
    return staged;
  }

  @override
  Future<void> copyNew(String source, String destination) async {
    final temporary = await Directory(
      p.dirname(destination),
    ).createTemp('.vertree-write-');
    try {
      final staged = await _stage(source, destination, temporary);
      final handle = await staged.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      await publishFile(staged.path, destination);
    } finally {
      // Cleanup failure does not undo a committed publication.
      try {
        await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<void> renameNew(String source, String destination) async {
    if (p.equals(source, destination)) return;
    await publishFile(source, destination);
  }

  @override
  Future<void> replace(
    String source,
    String target,
    FileFingerprint? expected,
  ) async {
    final temporary = await Directory(
      p.dirname(target),
    ).createTemp('.vertree-restore-');
    try {
      final staged = await _stage(source, target, temporary);
      final current = await exists(target) ? await fingerprint(target) : null;
      if (current != expected) {
        throw const OperationFailure(
          'TARGET_CHANGED',
          'Target changed before restore',
        );
      }
      if (expected == null) {
        await copyNew(staged.path, target);
      } else {
        final handle = await staged.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
        await staged.rename(target);
      }
    } finally {
      try {
        await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }
}
