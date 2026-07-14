import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:vertree/core/tree_builder.dart';

void main() {
  group('buildTree', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vertree_tree_builder_');
      await _copyDirectory(
        Directory(
          path.join(
            Directory.current.path,
            '.sample',
            'file_version_tree',
            'storyboard',
          ),
        ),
        Directory(path.join(tempDir.path, 'storyboard')),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('builds the expected tree from the sample directory', () async {
      final selectedPath = path.join(
        tempDir.path,
        'storyboard',
        'storyboard#hotfix.0.1-1.0.txt',
      );

      final result = await buildTree(selectedPath);

      expect(result.isOk, isTrue);
      final root = result.unwrap();

      expect(root.mate.version.toString(), '0.0');
      expect(root.child?.mate.version.toString(), '0.1');
      expect(root.child?.child?.mate.version.toString(), '0.2');

      final topBranch = root.child?.topBranches.single;
      final bottomBranch = root.child?.bottomBranches.single;

      expect(topBranch?.mate.version.toString(), '0.1-0.0');
      expect(topBranch?.child?.mate.version.toString(), '0.1-0.1');

      expect(bottomBranch?.mate.version.toString(), '0.1-1.0');
      expect(bottomBranch?.child?.mate.version.toString(), '0.1-1.1');
      expect(
        bottomBranch?.topBranches.single.mate.version.toString(),
        '0.1-1.0-0.0',
      );
    });

    test('ignores unrelated files in the same directory', () async {
      await File(
        path.join(tempDir.path, 'storyboard', '.storyboard.9.9.txt'),
      ).writeAsString('hidden');

      final selectedPath = path.join(
        tempDir.path,
        'storyboard',
        'storyboard.0.0.txt',
      );

      final result = await buildTree(selectedPath);

      expect(result.isOk, isTrue);
      final tree = result.unwrap().toTreeString();

      expect(tree, contains('storyboard.0.0.txt'));
      expect(tree, contains('storyboard#release.0.2.txt'));
      expect(tree, isNot(contains('notes.0.0.txt')));
      expect(tree, isNot(contains('.storyboard.9.9.txt')));
    });

    test('returns an error when the selected file does not exist', () async {
      final result = await buildTree(
        path.join(tempDir.path, 'storyboard', 'missing.0.0.txt'),
      );

      expect(result.isErr, isTrue);
      expect(result.msg, contains('文件路径不存在'));
    });

    test(
      'returns an error when the selected file name is unsupported',
      () async {
        final hiddenPath = path.join(
          tempDir.path,
          'storyboard',
          '.storyboard.0.0.txt',
        );
        await File(hiddenPath).writeAsString('hidden root');

        final result = await buildTree(hiddenPath);

        expect(result.isErr, isTrue);
        expect(result.msg, contains('当前文件命名不支持版本树'));
      },
    );
  });
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);

  await for (final entity in source.list(recursive: false)) {
    final targetPath = path.join(destination.path, path.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(targetPath));
    } else if (entity is File) {
      await entity.copy(targetPath);
    }
  }
}
