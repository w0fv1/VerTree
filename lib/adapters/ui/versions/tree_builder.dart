import 'package:vertree/adapters/ui/versions/file_version_tree.dart';
import 'package:vertree/foundation/result.dart';
import 'package:vertree/modules/versions/versions.dart';

Future<Result<FileNode, String>> buildTree(
  String path,
  VersionCatalog catalog,
) async {
  try {
    final graph = await catalog.read(path);
    if (graph.entries.isEmpty) return Result.eMsg('未找到根节点');
    final nodes = {
      for (final entry in graph.entries) entry.path: FileNode(entry.path),
    };
    for (final entry in graph.entries) {
      final parent = nodes[graph.parents[entry.path]];
      final node = nodes[entry.path]!;
      if (parent == null) continue;
      if (parent.version.isChild(node.version)) {
        parent.addChild(node);
      } else {
        parent.addBranch(node);
      }
    }
    final root = nodes[graph.entries.first.path]!;
    root.diagnostics = graph.diagnostics;
    return Result.ok(root);
  } catch (error) {
    return Result.eMsg(error.toString());
  }
}
