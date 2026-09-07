import 'dart:convert';
import 'package:path/path.dart' as p;
import '../modules/versions/versions.dart';

String fileId(String path) =>
    base64Url.encode(utf8.encode(p.normalize(p.absolute(path))));
String filePathFromId(String id) {
  final path = utf8.decode(base64Url.decode(base64Url.normalize(id)));
  if (!p.isAbsolute(path)) {
    throw const FormatException('Version id must encode an absolute path');
  }
  return p.normalize(path);
}

Map<String, dynamic> restoreDto(RestoreResult result) => {
  'sourcePath': result.sourcePath,
  'targetPath': result.targetPath,
  'backupPath': result.backupPath,
  'id': fileId(result.targetPath),
};
Map<String, dynamic> comparisonDto(VersionComparison result) => {
  'leftPath': result.leftPath,
  'rightPath': result.rightPath,
  'equal': result.equal,
  'leftSha256': result.leftSha256,
  'rightSha256': result.rightSha256,
  'mode': result.changes == null ? 'hash' : 'text',
  if (result.changes != null)
    'changes': [
      for (final change in result.changes!)
        {'operation': change.operation, 'text': change.text},
    ],
  if (result.changes == null)
    'reason': 'Text diff requires UTF-8 text of at most 2 MiB per file',
};
