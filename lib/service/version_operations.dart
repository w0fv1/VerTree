import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:path/path.dart' as p;
import '../core/file_version_tree.dart';
import 'app_events.dart';

String fileId(String path) =>
    base64Url.encode(utf8.encode(p.normalize(p.absolute(path))));
String filePathFromId(String id) {
  final path = utf8.decode(base64Url.decode(base64Url.normalize(id)));
  if (!p.isAbsolute(path)) {
    throw const FormatException('Version id must encode an absolute path');
  }
  return p.normalize(path);
}

class VersionOperations {
  VersionOperations(this.events);
  final AppEvents events;
  final _writing = <String>{};

  Future<Map<String, dynamic>> restore(
    String sourcePath, {
    String? targetPath,
  }) async {
    final source = File(await File(sourcePath).resolveSymbolicLinks());
    final meta = FileMeta(source.path);
    final target = File(
      targetPath ??
          p.join(p.dirname(source.path), '${meta.name}.${meta.extension}'),
    );
    if (!p.isAbsolute(target.path)) {
      throw const FormatException('targetPath must be absolute');
    }
    final canonicalTarget = await target.exists()
        ? await target.resolveSymbolicLinks()
        : p.join(
            await target.parent.resolveSymbolicLinks(),
            p.basename(target.path),
          );
    if (p.equals(source.path, canonicalTarget)) {
      throw const FormatException('Source and target are the same file');
    }
    if (!_writing.add(canonicalTarget)) {
      throw StateError('FILE_BUSY: another write is in progress');
    }
    Directory? temporary;
    String? backupPath;
    try {
      temporary = await Directory(
        p.dirname(canonicalTarget),
      ).createTemp('.vertree-restore-');
      final staged = await source.copy(p.join(temporary.path, 'content'));
      if (await File(canonicalTarget).exists()) {
        final backup = await FileNode(
          canonicalTarget,
        ).safeBackup('before-restore');
        if (backup.isErr) {
          throw FileSystemException(
            'Cannot preserve current file: ${backup.msg}',
            canonicalTarget,
          );
        }
        backupPath = backup.unwrap().mate.fullPath;
      }
      await staged.rename(canonicalTarget);
      final result = {
        'sourcePath': source.path,
        'targetPath': canonicalTarget,
        'backupPath': backupPath,
        'id': fileId(canonicalTarget),
      };
      events.emit('version.restored', result);
      return result;
    } finally {
      try {
        if (temporary != null) await temporary.delete(recursive: true);
      } finally {
        _writing.remove(canonicalTarget);
      }
    }
  }

  Future<Map<String, dynamic>> renameLabel(String path, String? label) async {
    if (label != null &&
        (label.length > 120 ||
            RegExp(r'[<>:"/\\|?*#\x00-\x1f]').hasMatch(label) ||
            label.endsWith('.') ||
            label.endsWith(' '))) {
      throw const FormatException('Invalid version label');
    }
    final source = await File(path).resolveSymbolicLinks();
    if (!_writing.add(source)) throw StateError('FILE_BUSY');
    try {
      final meta = FileMeta(source);
      meta.setLabel(label);
      final destination = p.join(p.dirname(source), meta.fullName);
      if (!p.equals(source, destination) && await File(destination).exists()) {
        throw StateError('VERSION_EXISTS: target label would overwrite a file');
      }
      await meta.renameFile(label);
      final result = {
        'id': fileId(meta.fullPath),
        'path': meta.fullPath,
        'previousPath': source,
        'label': meta.label,
      };
      events.emit('version.updated', result);
      return result;
    } finally {
      _writing.remove(source);
    }
  }

  Future<Map<String, dynamic>> compare(
    String leftPath,
    String rightPath,
  ) async {
    if (!p.isAbsolute(leftPath) || !p.isAbsolute(rightPath)) {
      throw const FormatException('Both paths must be absolute');
    }
    return Isolate.run(() async {
      final left = File(leftPath), right = File(rightPath);
      final leftHash = (await sha256.bind(left.openRead()).first).toString();
      final rightHash = (await sha256.bind(right.openRead()).first).toString();
      final result = <String, dynamic>{
        'leftPath': leftPath,
        'rightPath': rightPath,
        'equal': leftHash == rightHash,
        'leftSha256': leftHash,
        'rightSha256': rightHash,
      };
      if (await left.length() <= 2 * 1024 * 1024 &&
          await right.length() <= 2 * 1024 * 1024) {
        try {
          final a = utf8.decode(await left.readAsBytes()),
              b = utf8.decode(await right.readAsBytes());
          if (!a.contains('\u0000') && !b.contains('\u0000')) {
            result['mode'] = 'text';
            result['changes'] = dmp
                .diff(a, b, timeout: 2)
                .map(
                  (change) => {
                    'operation': change.operation == dmp.DIFF_EQUAL
                        ? 'equal'
                        : change.operation == dmp.DIFF_INSERT
                        ? 'insert'
                        : 'delete',
                    'text': change.text,
                  },
                )
                .toList();
            return result;
          }
        } on FormatException {
          result['textDecoding'] = 'unsupported';
        }
      }
      return {
        ...result,
        'mode': 'hash',
        'reason': 'Text diff requires UTF-8 text of at most 2 MiB per file',
      };
    });
  }
}
