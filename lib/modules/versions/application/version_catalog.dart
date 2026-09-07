import 'package:path/path.dart' as p;
import '../../../file_access/file_access.dart';
import '../../../foundation/operation_failure.dart';
import '../domain/version_name.dart';
import '../domain/version_graph.dart';

class VersionCatalog {
  VersionCatalog(this.files, this.writes);
  final FileAccess files;
  final FileMutationCoordinator writes;
  Future<VersionGraph> read(String path) async {
    final source = await files.canonicalize(path);
    final name = VersionName.parse(source);
    if (!name.supported) {
      throw const OperationFailure('UNSUPPORTED_NAME', '当前文件命名不支持版本树');
    }
    return writes.run([p.dirname(source)], () async {
      await files.fingerprint(source);
      final entries =
          (await files.files(p.dirname(source)))
              .map(VersionEntry.new)
              .where(
                (entry) => entry.name.supported && name.sameFamily(entry.name),
              )
              .toList()
            ..sort((a, b) {
              final order = a.name.version.compareTo(b.name.version);
              return order != 0 ? order : a.path.compareTo(b.path);
            });
      return VersionGraph(entries);
    });
  }
}
