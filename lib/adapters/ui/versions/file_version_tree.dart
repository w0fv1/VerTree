import 'dart:io';
import 'package:vertree/modules/versions/versions.dart';
import 'dart:math';
import 'package:path/path.dart' as path;

class FileMeta {
  FileMeta(this.fullPath)
    : _name = VersionName.parse(fullPath),
      _stat = File(fullPath).statSync();
  final String fullPath;
  final VersionName _name;
  final FileStat _stat;
  String get fullName => path.basename(fullPath);
  String get name => _name.name;
  String? get label => _name.label;
  FileVersion get version => _name.version;
  String get extension => _name.extension;
  File get originalFile => File(fullPath);
  int get fileSize => _stat.size;
  DateTime get creationTime => _stat.changed;
  DateTime get lastModifiedTime => _stat.modified;
  static bool isSupportedTreeFilePath(String fullPath) =>
      VersionName.parse(fullPath).supported;

  @override
  String toString() {
    return 'FileMeta('
        'fullName: $fullName, '
        'name: $name, '
        'label: ${label ?? ""}, '
        'version: $version, '
        'extension: $extension, '
        'fullPath: $fullPath, '
        'fileSize: $fileSize bytes, '
        'creationTime: $creationTime, '
        'lastModifiedTime: $lastModifiedTime'
        ')';
  }
}

class FileNode {
  late FileMeta mate;
  List<String> diagnostics = const [];
  File get originalFile => mate.originalFile;
  FileNode? child;
  late FileNode parent;
  final List<FileNode> branches = [];
  int get branchIndex => branches.fold(
    -1,
    (value, node) => max(value, node.version.segments.last.branch),
  );
  int get totalChildren => branches.length + (child == null ? 0 : 1);

  FileVersion get version => mate.version;

  List<FileNode> get topBranches => List.unmodifiable(
    branches.where((node) => node.version.segments.last.branch.isEven),
  );
  List<FileNode> get bottomBranches => List.unmodifiable(
    branches.where((node) => node.version.segments.last.branch.isOdd),
  );

  FileNode(String fullPath) {
    mate = FileMeta(fullPath);
  }

  FileNode.fromMeta(FileMeta fileMeta) {
    mate = fileMeta;
  }

  bool noChildren() {
    return child == null && topBranches.isEmpty && bottomBranches.isEmpty;
  }

  int getHeight([int side = 0]) {
    if (noChildren()) {
      return 1;
    }
    int tmp = 0;
    if (child != null) {
      tmp += child!.getHeight();
    } else {
      tmp += 1;
    }
    if (side == 1 || side == 0) {
      for (var branch in topBranches) {
        tmp += branch.getHeight();
      }
    }
    if (side == -1 || side == 0) {
      for (var branch in bottomBranches) {
        tmp += branch.getHeight();
      }
    }
    return tmp;
  }

  List<FileNode> _getCloserParentBranches() {
    List<FileNode> branchesList = parent.topBranches.contains(this)
        ? parent.topBranches
        : parent.bottomBranches;
    if (!parent.topBranches.contains(this) &&
        !parent.bottomBranches.contains(this)) {
      return [];
    }
    int index = branchesList.indexOf(this);
    if (branchesList.isEmpty) {
      return [];
    }
    return branchesList.sublist(0, index);
  }

  int getParentRelativeHeight() {
    int tmp = 0;
    bool isTopBranch = parent.topBranches.contains(this);
    int top = isTopBranch ? 1 : -1;
    int branchHeight = 0;
    if (isTopBranch) {
      for (var value in bottomBranches) {
        branchHeight += value.getHeight();
      }
    } else {
      for (var value in topBranches) {
        branchHeight += value.getHeight();
      }
    }
    tmp += branchHeight;
    if (child != null) {
      tmp += child!.getHeight(-top) - 1;
    }
    List<FileNode> closerBranches = _getCloserParentBranches();
    for (var closerBranch in closerBranches) {
      tmp += closerBranch.getHeight();
    }
    int parentChildHeight = 0;
    if (parent.child != null) {
      parentChildHeight += parent.child!.getHeight(top);
    }
    tmp += parentChildHeight;
    return max(1, tmp);
  }

  void addChild(FileNode node) {
    if (child != null) {
      return;
    }
    child = node;
    child?.parent = this;
  }

  void addBranch(FileNode branch) {
    if (!branches.any((b) => b.mate.version == branch.mate.version)) {
      branches.add(branch);
      branch.parent = this;
      branches.sort((a, b) => a.mate.version.compareTo(b.mate.version));
    }
  }

  bool push(FileNode node) {
    if (mate.version.compareTo(node.mate.version) == 0) {
      return false;
    }
    if (mate.version.isChild(node.mate.version)) {
      addChild(node);
      return true;
    }
    if (mate.version.isDirectBranch(node.mate.version)) {
      addBranch(node);
      return true;
    }
    if (child != null) {
      if (child!.push(node)) {
        return true;
      }
    }
    for (var branch in branches) {
      if (branch.push(node)) {
        return true;
      }
    }
    return false;
  }

  String toTreeString({int level = 0, String label = 'Root'}) {
    final indent = ' ' * (level * 4);
    final buffer = StringBuffer();
    buffer.writeln(
      '$indent$label[${mate.fullName} (version: ${mate.version})]',
    );
    if (child != null) {
      buffer.write(child!.toTreeString(level: level, label: 'Child'));
    }
    for (var branch in branches) {
      buffer.write(branch.toTreeString(level: level + 1, label: 'Branch'));
    }
    return buffer.toString();
  }

  @override
  String toString() {
    return 'FileNode(file: $mate, child: [$child], branches: [$branches])';
  }
}
