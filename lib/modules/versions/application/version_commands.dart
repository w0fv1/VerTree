import 'package:path/path.dart' as p;
import '../../../file_access/file_access.dart';
import '../../../foundation/operation_failure.dart';
import '../domain/version_name.dart';
import '../domain/version_number.dart';

enum VersionCreationMode { next, branch, auto }

class VersionCommands {
  VersionCommands({
    required this.files,
    required this.writes,
    required this.emit,
  });
  final FileAccess files;
  final FileMutationCoordinator writes;
  final void Function(String type, Map<String, dynamic> data) emit;

  // Directory locking also serializes renames involving family aliases and
  // restores with a different target family. Independent directories proceed.
  Future<List<String>> _resources(List<String> paths) async => [
    for (final path in paths) await files.canonicalize(p.dirname(path)),
  ];

  Future<String> create(
    String path, {
    String? label,
    VersionCreationMode mode = VersionCreationMode.auto,
  }) async {
    VersionName.validateLabel(label);
    final source = await files.canonicalize(path);
    final meta = VersionName.parse(source);
    if (!meta.supported) {
      throw const OperationFailure('UNSUPPORTED_NAME', '当前文件命名不支持版本备份');
    }
    return writes.run(
      await _resources([source]),
      () => _create(source, label, mode),
    );
  }

  Future<String> _create(
    String source,
    String? label,
    VersionCreationMode mode,
  ) async {
    await files.fingerprint(source);
    final meta = VersionName.parse(source);
    final family = (await files.files(
      p.dirname(source),
    )).map(VersionName.parse).where(meta.sameFamily).toList();
    bool exists(FileVersion version) =>
        family.any((entry) => entry.version == version);
    var version = meta.version.nextVersion();
    final branch =
        mode == VersionCreationMode.branch ||
        mode == VersionCreationMode.auto && exists(version);
    if (branch) {
      var index = 0;
      while (exists(meta.version.branchVersion(index))) {
        index++;
      }
      version = meta.version.branchVersion(index);
    } else if (exists(version)) {
      throw const OperationFailure(
        'VERSION_EXISTS',
        'A successor version already exists',
      );
    }
    final target = p.join(p.dirname(source), meta.fileName(version, label));
    await files.copyNew(source, target);
    emit('version.created', {
      'path': source,
      'backupPath': target,
      'source': branch ? 'branch' : 'manual',
    });
    return target;
  }

  Future<String> renameLabel(String path, String? label) async {
    VersionName.validateLabel(label);
    final source = await files.canonicalize(path);
    return writes.run(await _resources([source]), () async {
      await files.fingerprint(source);
      final meta = VersionName.parse(source);
      if (!meta.supported) {
        throw const OperationFailure(
          'UNSUPPORTED_NAME',
          'Unsupported version name',
        );
      }
      final target = p.join(
        p.dirname(source),
        meta.fileName(meta.version, label),
      );
      await files.renameNew(source, target);
      emit('version.updated', {
        'path': target,
        'previousPath': source,
        'label': label,
      });
      return target;
    });
  }

  Future<RestoreResult> restore(String path, {String? targetPath}) async {
    if (targetPath != null && !p.isAbsolute(targetPath)) {
      throw const OperationFailure(
        'INVALID_PATH',
        'Target path must be absolute',
      );
    }
    final source = await files.canonicalize(path);
    final meta = VersionName.parse(source);
    final target = await files.canonicalize(
      targetPath ?? p.join(p.dirname(source), '${meta.name}.${meta.extension}'),
    );
    if (p.equals(source, target)) {
      throw const OperationFailure(
        'SAME_FILE',
        'Source and target are the same file',
      );
    }
    return writes.run(await _resources([source, target]), () async {
      await files.fingerprint(source);
      final expected = await files.exists(target)
          ? await files.fingerprint(target)
          : null;
      final backup = expected == null
          ? null
          : await _create(target, 'before-restore', VersionCreationMode.auto);
      await files.replace(source, target, expected);
      final result = RestoreResult(source, target, backup);
      emit('version.restored', {
        'sourcePath': source,
        'targetPath': target,
        'backupPath': backup,
      });
      return result;
    });
  }
}

class RestoreResult {
  const RestoreResult(this.sourcePath, this.targetPath, this.backupPath);
  final String sourcePath, targetPath;
  final String? backupPath;
}
