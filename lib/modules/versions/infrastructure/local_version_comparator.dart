import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:path/path.dart' as p;
import '../ports/version_comparator.dart';

class LocalVersionComparator implements VersionComparator {
  @override
  Future<VersionComparison> compare(String leftPath, String rightPath) async {
    if (!p.isAbsolute(leftPath) || !p.isAbsolute(rightPath)) {
      throw const FormatException('Both paths must be absolute');
    }
    return Isolate.run(() async {
      final left = File(leftPath), right = File(rightPath);
      final leftHash = (await sha256.bind(left.openRead()).first).toString();
      final rightHash = (await sha256.bind(right.openRead()).first).toString();
      List<TextChange>? changes;
      if (await left.length() <= 2 * 1024 * 1024 &&
          await right.length() <= 2 * 1024 * 1024) {
        try {
          final a = utf8.decode(await left.readAsBytes()),
              b = utf8.decode(await right.readAsBytes());
          if (!a.contains('\u0000') && !b.contains('\u0000')) {
            changes = dmp
                .diff(a, b, timeout: 2)
                .map(
                  (change) => TextChange(
                    change.operation == dmp.DIFF_EQUAL
                        ? 'equal'
                        : change.operation == dmp.DIFF_INSERT
                        ? 'insert'
                        : 'delete',
                    change.text,
                  ),
                )
                .toList();
          }
        } on FormatException {
          /* Binary comparison remains available. */
        }
      }
      return VersionComparison(
        leftPath: leftPath,
        rightPath: rightPath,
        leftSha256: leftHash,
        rightSha256: rightHash,
        changes: changes == null ? null : List.unmodifiable(changes),
      );
    });
  }
}
