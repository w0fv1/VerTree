import 'file_version_tree.dart';
import '../../../foundation/result.dart';
import '../../../modules/versions/versions.dart';

/// Maps application results to the tree view's display model.
class VersionActions {
  VersionActions(this.commands);
  final VersionCommands commands;
  Future<Result<FileNode, String>> create(
    String path, {
    String? label,
    VersionCreationMode mode = VersionCreationMode.auto,
  }) async {
    try {
      return Result.ok(
        FileNode(await commands.create(path, label: label, mode: mode)),
      );
    } catch (error) {
      return Result.eMsg(error.toString());
    }
  }

  Future<String> renameLabel(String path, String? label) =>
      commands.renameLabel(path, label);
}
