import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:vertree/core/file_version_tree.dart';

void main() {
  group('FileVersion', () {
    test('parses, serializes and compares versions', () {
      final version = FileVersion('0.1-2.3');

      expect(version.segments, hasLength(2));
      expect(version.segments.first, const Segment(0, 1));
      expect(version.segments.last, const Segment(2, 3));
      expect(version.toString(), '0.1-2.3');

      expect(FileVersion('0.1').compareTo(FileVersion('0.2')), lessThan(0));
      expect(
        FileVersion('0.1-0.0').compareTo(FileVersion('0.1')),
        greaterThan(0),
      );
      expect(
        FileVersion('0.1-0.0').compareTo(FileVersion('0.1-1.0')),
        lessThan(0),
      );
    });

    test('creates next and branch versions', () {
      expect(FileVersion('0.1').nextVersion().toString(), '0.2');
      expect(FileVersion('0.1').branchVersion(3).toString(), '0.1-3.0');
    });

    test('distinguishes branch relationships correctly', () {
      final parent = FileVersion('0.1');
      final directBranch = FileVersion('0.1-0.0');
      final indirectBranch = FileVersion('0.1-0.0-0.0');

      expect(parent.isSameBranch(FileVersion('0.9')), isTrue);
      expect(parent.isSameBranch(directBranch), isFalse);
      expect(parent.isChild(FileVersion('0.2')), isTrue);
      expect(parent.isChild(FileVersion('0.3')), isFalse);
      expect(parent.isDirectBranch(directBranch), isTrue);
      expect(parent.isIndirectBranch(directBranch), isFalse);
      expect(parent.isIndirectBranch(indirectBranch), isTrue);
    });
  });

  group('FileMeta', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vertree_file_meta_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('parses name, label, version and extension from file name', () async {
      final file = await _writeFile(
        tempDir,
        'storyboard#baseline.0.1.txt',
        'baseline',
      );

      final meta = FileMeta(file.path);

      expect(meta.name, 'storyboard');
      expect(meta.label, 'baseline');
      expect(meta.version.toString(), '0.1');
      expect(meta.extension, 'txt');
      expect(meta.fullName, 'storyboard#baseline.0.1.txt');
      expect(meta.fileSize, greaterThan(0));
    });

    test(
      'parses dotted file names and nested version segments correctly',
      () async {
        final file = await _writeFile(
          tempDir,
          'story.board.v2#draft.0.1-2.3.psd',
          'draft',
        );

        final meta = FileMeta(file.path);

        expect(meta.name, 'story.board.v2');
        expect(meta.label, 'draft');
        expect(meta.version.toString(), '0.1-2.3');
        expect(meta.extension, 'psd');
      },
    );

    test('defaults missing version to 0.0 and can rename label', () async {
      final file = await _writeFile(tempDir, 'storyboard#draft.txt', 'draft');

      final meta = FileMeta(file.path);
      expect(meta.version.toString(), '0.0');
      expect(meta.label, 'draft');

      await meta.renameFile('approved');

      expect(meta.label, 'approved');
      expect(meta.fullName, 'storyboard#approved.0.0.txt');
      expect(File(meta.fullPath).existsSync(), isTrue);
      expect(
        File(path.join(tempDir.path, 'storyboard#draft.txt')).existsSync(),
        isFalse,
      );
    });

    test(
      'treats a leading dot file name as unsupported for version trees',
      () async {
        final hiddenFile = await _writeFile(
          tempDir,
          '.storyboard.0.1.txt',
          'hidden',
        );
        final meta = FileMeta(hiddenFile.path);

        expect(meta.name, '.storyboard');
        expect(meta.version.toString(), '0.1');
        expect(FileMeta.isSupportedTreeFilePath(hiddenFile.path), isFalse);
      },
    );

    test('supports dotted names that do not start with a dot', () async {
      final file = await _writeFile(
        tempDir,
        'story.board.release.txt',
        'release',
      );

      final meta = FileMeta(file.path);

      expect(meta.name, 'story.board.release');
      expect(meta.version.toString(), '0.0');
      expect(FileMeta.isSupportedTreeFilePath(file.path), isTrue);
    });
  });

  group('FileNode', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vertree_file_node_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'addChild keeps the first child and avoids duplicate counts',
      () async {
        final root = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.0.txt')).path,
        );
        final firstChild = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.1.txt')).path,
        );
        final secondChild = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.2.txt')).path,
        );

        root.addChild(firstChild);
        root.addChild(secondChild);

        expect(root.child, same(firstChild));
        expect(root.child?.parent, same(root));
        expect(root.totalChildren, 1);
      },
    );

    test(
      'addBranch sorts all branch collections and tracks max branch index',
      () async {
        final root = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.1.txt')).path,
        );
        final branch2 = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.1-2.0.txt')).path,
        );
        final branch0 = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.1-0.0.txt')).path,
        );
        final branch1 = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.1-1.0.txt')).path,
        );

        root.addBranch(branch2);
        root.addBranch(branch0);
        root.addBranch(branch1);

        expect(
          root.branches.map((node) => node.mate.version.toString()).toList(),
          ['0.1-0.0', '0.1-1.0', '0.1-2.0'],
        );
        expect(
          root.topBranches.map((node) => node.mate.version.toString()).toList(),
          ['0.1-0.0', '0.1-2.0'],
        );
        expect(
          root.bottomBranches
              .map((node) => node.mate.version.toString())
              .toList(),
          ['0.1-1.0'],
        );
        expect(root.branchIndex, 2);
        expect(root.totalChildren, 3);
      },
    );

    test(
      'push builds a nested tree when parents are inserted before descendants',
      () async {
        final root = FileNode(
          (await _writeFile(tempDir, 'storyboard.0.0.txt')).path,
        );
        final nodes = [
          'storyboard.0.1.txt',
          'storyboard.0.2.txt',
          'storyboard.0.1-0.0.txt',
          'storyboard.0.1-1.0.txt',
          'storyboard.0.1-1.1.txt',
        ].map((name) async => FileNode((await _writeFile(tempDir, name)).path));

        for (final node in await Future.wait(nodes)) {
          root.push(node);
        }

        expect(root.child?.mate.version.toString(), '0.1');
        expect(root.child?.child?.mate.version.toString(), '0.2');
        expect(
          root.child?.topBranches
              .map((node) => node.mate.version.toString())
              .toList(),
          ['0.1-0.0'],
        );
        expect(
          root.child?.bottomBranches
              .map((node) => node.mate.version.toString())
              .toList(),
          ['0.1-1.0'],
        );
        expect(
          root.child?.bottomBranches.first.child?.mate.version.toString(),
          '0.1-1.1',
        );
      },
    );

    test('backup, branch and safeBackup create expected files', () async {
      final rootFile = await _writeFile(tempDir, 'storyboard.0.0.txt', 'root');
      final root = FileNode(rootFile.path);

      final backupResult = await root.backup('baseline');
      expect(backupResult.isOk, isTrue);
      expect(
        backupResult.unwrap().mate.fullName,
        'storyboard#baseline.0.1.txt',
      );
      expect(
        File(
          path.join(tempDir.path, 'storyboard#baseline.0.1.txt'),
        ).existsSync(),
        isTrue,
      );

      final secondBackup = await root.backup();
      expect(secondBackup.isErr, isTrue);

      final branchResult = await root.branch('hotfix');
      expect(branchResult.isOk, isTrue);
      expect(
        branchResult.unwrap().mate.fullName,
        'storyboard#hotfix.0.0-0.0.txt',
      );

      final separateRootFile = await _writeFile(
        tempDir,
        'spec.0.0.txt',
        'spec',
      );
      await _writeFile(tempDir, 'spec.0.1.txt', 'next');
      final separateRoot = FileNode(separateRootFile.path);

      final safeBackupResult = await separateRoot.safeBackup('branch');
      expect(safeBackupResult.isOk, isTrue);
      expect(safeBackupResult.unwrap().mate.version.toString(), '0.0-0.0');
      expect(
        File(path.join(tempDir.path, 'spec#branch.0.0-0.0.txt')).existsSync(),
        isTrue,
      );
    });

    test('rejects backup and branch for dot-leading file names', () async {
      final hiddenFile = await _writeFile(
        tempDir,
        '.gitignore',
        'node_modules',
      );
      final hiddenNode = FileNode(hiddenFile.path);

      final backupResult = await hiddenNode.backup();
      final branchResult = await hiddenNode.branch();
      final safeBackupResult = await hiddenNode.safeBackup();

      expect(backupResult.isErr, isTrue);
      expect(branchResult.isErr, isTrue);
      expect(safeBackupResult.isErr, isTrue);
      expect(backupResult.msg, contains('当前文件命名不支持版本备份'));
      expect(branchResult.msg, contains('当前文件命名不支持版本备份'));
      expect(safeBackupResult.msg, contains('当前文件命名不支持版本备份'));
      expect(Directory(tempDir.path).listSync(), hasLength(1));
    });

    test('computes heights for mixed child and branch trees', () async {
      final root = FileNode(
        (await _writeFile(tempDir, 'storyboard.0.0.txt')).path,
      );
      final child = FileNode(
        (await _writeFile(tempDir, 'storyboard.0.1.txt')).path,
      );
      final topBranch = FileNode(
        (await _writeFile(tempDir, 'storyboard.0.1-0.0.txt')).path,
      );
      final bottomBranch = FileNode(
        (await _writeFile(tempDir, 'storyboard.0.1-1.0.txt')).path,
      );
      final bottomChild = FileNode(
        (await _writeFile(tempDir, 'storyboard.0.1-1.1.txt')).path,
      );

      root.addChild(child);
      child.addBranch(topBranch);
      child.addBranch(bottomBranch);
      bottomBranch.addChild(bottomChild);

      expect(bottomBranch.getHeight(), 1);
      expect(child.getHeight(), 3);
      expect(topBranch.getParentRelativeHeight(), 1);
      expect(bottomBranch.getParentRelativeHeight(), 1);
    });
  });
}

Future<File> _writeFile(
  Directory dir,
  String name, [
  String content = 'sample',
]) async {
  final file = File(path.join(dir.path, name));
  await file.parent.create(recursive: true);
  return file.writeAsString(content);
}
