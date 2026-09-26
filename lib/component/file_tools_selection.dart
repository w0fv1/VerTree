import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Explorer hands off one bounded private manifest, never thousands of quoted
/// shell arguments. Reading it only populates a confirmation UI, not a command.
Future<List<String>> readFileToolsSelection(String manifestPath) async {
  final expectedRoot = p.normalize(
    p.join(Directory.systemTemp.path, 'VerTree.FileTools.Selections'),
  );
  final path = p.normalize(p.absolute(manifestPath));
  final name = p.basename(path);
  if (!p.equals(p.dirname(path), expectedRoot) ||
      !RegExp(r'^[0-9a-fA-F-]{36}\.json$').hasMatch(name)) {
    throw const FormatException(
      'Selection manifest is outside the Explorer handoff directory',
    );
  }
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Selection manifest is not an ordinary file');
  }
  final file = File(path);
  if (!p.equals(p.normalize(await file.resolveSymbolicLinks()), path)) {
    throw const FormatException('Selection manifest must not follow a link');
  }
  final stat = await file.stat();
  if (stat.size > 4 * 1024 * 1024 ||
      DateTime.now().difference(stat.modified).abs() >
          const Duration(minutes: 30)) {
    throw const FormatException('Selection manifest is oversized or expired');
  }
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, dynamic> ||
      value['schemaVersion'] != 1 ||
      value['owner'] != 'VerTree.Explorer' ||
      value['paths'] is! List) {
    throw const FormatException('Invalid Explorer selection manifest');
  }
  final paths = (value['paths'] as List).cast<String>();
  if (paths.isEmpty ||
      paths.length > 1024 ||
      paths.any((path) => path.isEmpty || path.contains('\u0000'))) {
    throw const FormatException('Invalid selection size or path');
  }
  // Consume only the known, per-invocation temporary handoff file. The target
  // files/folders are untouched until a separate native preparation + dialog.
  await file.delete();
  return List.unmodifiable(paths);
}
