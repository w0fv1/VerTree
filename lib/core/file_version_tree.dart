import 'dart:io';
import 'package:vertree/service/app_events.dart';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:vertree/core/result.dart';

void _logCoreError(String message) {
  stderr.writeln(message);
}

class _ParsedFileNameParts {
  final String name;
  final String? label;
  final FileVersion version;

  const _ParsedFileNameParts({
    required this.name,
    required this.label,
    required this.version,
  });
}

class FileVersion implements Comparable<FileVersion> {
  final List<Segment> segments;

  FileVersion._(this.segments);

  factory FileVersion(String versionString) {
    return FileVersion._(_parse(versionString));
  }

  static List<Segment> _parse(String versionString) {
    final parts = versionString.split('-');
    final segs = <Segment>[];
    for (final part in parts) {
      List<String> bv = part.split('.');
      if (bv.length != 2) {
        _logCoreError("版本段格式错误，每段必须是 X.Y 形式: $part");
        bv = ["0", "0"];
      }
      final branch = int.parse(bv[0]);
      final ver = int.parse(bv[1]);
      segs.add(Segment(branch, ver));
    }
    return segs;
  }

  factory FileVersion.fromSegments(List<Segment> segs) {
    return FileVersion._(List<Segment>.from(segs));
  }

  FileVersion nextVersion() {
    if (segments.isEmpty) {
      return FileVersion('0.0');
    }
    final newSegs = List<Segment>.from(segments);
    final last = newSegs.last;
    newSegs[newSegs.length - 1] = Segment(last.branch, last.version + 1);
    return FileVersion.fromSegments(newSegs);
  }

  FileVersion branchVersion(int branchIndex) {
    final newSegs = List<Segment>.from(segments);
    newSegs.add(Segment(branchIndex, 0));
    return FileVersion.fromSegments(newSegs);
  }

  @override
  String toString() {
    return segments.map((seg) => '${seg.branch}.${seg.version}').join('-');
  }

  String get branchPath {
    return segments.map((seg) => seg.branch.toString()).join('-');
  }

  int get revisionNumber {
    if (segments.isEmpty) {
      return 0;
    }
    return segments.last.version;
  }

  @override
  int compareTo(FileVersion other) {
    final minLen = segments.length < other.segments.length
        ? segments.length
        : other.segments.length;
    for (int i = 0; i < minLen; i++) {
      final diffBranch = segments[i].branch - other.segments[i].branch;
      if (diffBranch != 0) return diffBranch;
      final diffVer = segments[i].version - other.segments[i].version;
      if (diffVer != 0) return diffVer;
    }
    return segments.length - other.segments.length;
  }

  bool isSameBranch(FileVersion other) {
    if (segments.length != other.segments.length) {
      return false;
    }
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].branch != other.segments[i].branch) {
        return false;
      }
    }
    return true;
  }

  bool isChild(FileVersion other) {
    if (!isSameBranch(other)) return false;
    return segments.last.version + 1 == other.segments.last.version;
  }

  bool isDirectBranch(FileVersion other) {
    if (other.segments.length != segments.length + 1) {
      return false;
    }
    final n = segments.length;
    for (int i = 0; i < n; i++) {
      if (segments[i] != other.segments[i]) {
        return false;
      }
    }
    final lastOther = other.segments[other.segments.length - 1];
    if (lastOther.version != 0) {
      return false;
    }
    return true;
  }

  bool isIndirectBranch(FileVersion other) {
    if (other.segments.length <= segments.length + 1) {
      return false;
    }
    for (int i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) {
        return false;
      }
    }
    return true;
  }
}

class Segment {
  final int branch;
  final int version;

  const Segment(this.branch, this.version);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Segment) return false;
    return branch == other.branch && version == other.version;
  }

  @override
  int get hashCode => Object.hash(branch, version);
}

class FileMeta {
  static final RegExp _versionSuffixPattern = RegExp(
    r'^(.*)\.((?:\d+\.\d+)(?:-\d+\.\d+)*)$',
  );

  String fullName = "";

  String name = "";

  String? label;

  FileVersion version = FileVersion("0.0");

  String extension = "";

  String fullPath;

  File originalFile;

  int fileSize = 0;

  DateTime creationTime = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime lastModifiedTime = DateTime.fromMillisecondsSinceEpoch(0);

  static bool isSupportedTreeFilePath(String fullPath) {
    final extension = path.extension(fullPath);
    final fileNameWithoutExt = path.basenameWithoutExtension(fullPath);

    if (extension.isEmpty || fileNameWithoutExt.isEmpty) {
      return false;
    }

    final parsed = _parseFileNameParts(fileNameWithoutExt);
    return parsed.name.isNotEmpty && !parsed.name.startsWith('.');
  }

  static _ParsedFileNameParts _parseFileNameParts(String fileNameWithoutExt) {
    String basePart = fileNameWithoutExt;
    FileVersion version = FileVersion("0.0");

    final versionMatch = _versionSuffixPattern.firstMatch(fileNameWithoutExt);
    if (versionMatch != null) {
      basePart = versionMatch.group(1)!;
      version = FileVersion(versionMatch.group(2)!);
    }

    final hashIndex = basePart.indexOf('#');
    if (hashIndex == -1) {
      return _ParsedFileNameParts(
        name: basePart,
        label: null,
        version: version,
      );
    }

    final name = basePart.substring(0, hashIndex);
    final rawLabel = basePart.substring(hashIndex + 1);

    return _ParsedFileNameParts(
      name: name,
      label: rawLabel.isEmpty ? null : rawLabel,
      version: version,
    );
  }

  FileMeta(this.fullPath) : originalFile = File(fullPath) {
    fullName = path.basename(fullPath);

    extension = path.extension(fullPath).replaceFirst('.', '');

    final fileNameWithoutExt = path.basenameWithoutExtension(fullPath);
    final parsed = _parseFileNameParts(fileNameWithoutExt);
    name = parsed.name;
    label = parsed.label;
    version = parsed.version;

    if (originalFile.existsSync()) {
      final fileStat = originalFile.statSync();
      fileSize = fileStat.size;
      creationTime = fileStat.changed;
      lastModifiedTime = fileStat.modified;
    }
  }

  void setLabel(String? newLabel) {
    label = newLabel;
    fullName =
        "$name${(newLabel != null && newLabel.isNotEmpty) ? "#$newLabel" : ""}.${version.toString()}.$extension";
  }

  Future<void> renameFile(String? newLabel) async {
    setLabel(newLabel);

    final dir = path.dirname(fullPath);
    final newFullName = fullName;
    final newFullPath = path.join(dir, newFullName);

    final newFile = await originalFile.rename(newFullPath);

    fullPath = newFullPath;
    fullName = newFullName;
    originalFile = newFile;

    if (newFile.existsSync()) {
      final fileStat = newFile.statSync();
      fileSize = fileStat.size;
      creationTime = fileStat.changed;
      lastModifiedTime = fileStat.modified;
    }
  }

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
  late File originalFile;
  FileNode? child;
  late FileNode parent;
  final List<FileNode> branches = [];
  int branchIndex = -1;
  FileNode? firstBranch;

  int totalChildren = 0;

  FileVersion get version => mate.version;

  final List<FileNode> topBranches = [];
  final List<FileNode> bottomBranches = [];

  FileNode(String fullPath) {
    mate = FileMeta(fullPath);
    originalFile = File(fullPath);
  }

  FileNode.fromMeta(FileMeta fileMeta) {
    mate = fileMeta;
    originalFile = fileMeta.originalFile;
  }

  String? _validateVersionableSource() {
    if (FileMeta.isSupportedTreeFilePath(mate.fullPath)) {
      return null;
    }
    return "当前文件命名不支持版本备份";
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
    totalChildren += 1;
  }

  void addBranch(FileNode branch) {
    if (!branches.any((b) => b.mate.version == branch.mate.version)) {
      branches.add(branch);
      branch.parent = this;
      totalChildren += 1;
      branches.sort((a, b) => a.mate.version.compareTo(b.mate.version));
      if (branch.mate.version.segments.last.branch > branchIndex) {
        branchIndex = branch.mate.version.segments.last.branch;
      }
      if (branch.mate.version.segments.last.branch % 2 == 0) {
        topBranches.add(branch);
        topBranches.sort((a, b) => a.mate.version.compareTo(b.mate.version));
      } else {
        bottomBranches.add(branch);
        bottomBranches.sort((a, b) => a.mate.version.compareTo(b.mate.version));
      }
    }
  }

  Future<Result<FileNode, String>> safeBackup([String? label]) async {
    final unsupportedMessage = _validateVersionableSource();
    if (unsupportedMessage != null) {
      return Result.eMsg(unsupportedMessage);
    }

    try {
      final newVersion = mate.version.nextVersion();
      if (!_hasVersionConflict(newVersion)) {
        return await backup(label);
      } else {
        return await branch(label);
      }
    } catch (e) {
      return Result.eMsg("safeBackup 失败: ${e.toString()}");
    }
  }

  Future<Result<FileNode, String>> backup([String? label]) async {
    final unsupportedMessage = _validateVersionableSource();
    if (unsupportedMessage != null) {
      return Result.eMsg(unsupportedMessage);
    }

    if (child != null) {
      return Result.eMsg("当前版本已有长子，不允许备份");
    }
    try {
      final newVersion = mate.version.nextVersion();
      final newFileName =
          '${mate.name}${label != null ? "#$label" : ""}.${newVersion.toString()}.${mate.extension}';
      final dirPath = path.dirname(mate.fullPath);
      final newFilePath = path.join(dirPath, newFileName);
      await _copyNewVersion(originalFile, newFilePath);
      AppEvents.instance.emit('backup.created', {'path': mate.fullPath, 'backupPath': newFilePath, 'source': 'manual'});
      final newNode = FileNode(newFilePath);
      addChild(newNode);
      return Result.ok(newNode);
    } catch (e) {
      return Result.err("备份文件失败: ${e.toString()}");
    }
  }

  Future<Result<FileNode, String>> branch([String? label]) async {
    final unsupportedMessage = _validateVersionableSource();
    if (unsupportedMessage != null) {
      return Result.eMsg(unsupportedMessage);
    }

    try {
      var nextBranchIndex = branchIndex + 1;
      var branchedVersion = mate.version.branchVersion(nextBranchIndex);
      while (_hasVersionConflict(branchedVersion)) {
        branchedVersion = mate.version.branchVersion(++nextBranchIndex);
      }
      final newFileName =
          '${mate.name}${label != null ? "#$label" : ""}.${branchedVersion.toString()}.${mate.extension}';
      final dirPath = path.dirname(mate.fullPath);
      final newFilePath = path.join(dirPath, newFileName);
      await _copyNewVersion(originalFile, newFilePath);
      AppEvents.instance.emit('backup.created', {'path': mate.fullPath, 'backupPath': newFilePath, 'source': 'branch'});
      final newNode = FileNode(newFilePath);
      addBranch(newNode);
      return Result.ok(newNode);
    } catch (e) {
      return Result.err("创建分支失败: ${e.toString()}");
    }
  }

  bool _hasVersionConflict(FileVersion version) {
    final dir = Directory(path.dirname(mate.fullPath));
    if (!dir.existsSync()) {
      return false;
    }

    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }

      final meta = FileMeta(entity.path);
      if (meta.name == mate.name && meta.extension == mate.extension && meta.version.compareTo(version) == 0) {
        return true;
      }
    }

    return false;
  }

  Future<void> _copyNewVersion(File source, String destination) async {
    final target = File(destination);
    await target.create(exclusive: true);
    try {
      await source.copy(destination);
    } catch (_) {
      await target.delete();
      rethrow;
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
