import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vertree/adapters/ui/versions/file_version_tree.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/file_access/infrastructure/local_file_access.dart';
import 'package:vertree/foundation/operation_failure.dart';
import 'package:vertree/modules/versions/versions.dart';

void main() {
  late Directory directory;
  late VersionCommands commands;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vertree-commands-');
    commands = VersionCommands(
      files: LocalFileAccess(),
      writes: FileMutationCoordinator(),
      emit: (_, _) {},
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'concurrent auto backups allocate different versions without losing content',
    () async {
      final source = await File(
        p.join(directory.path, 'report.txt'),
      ).writeAsString('content');
      final results = await Future.wait(
        List.generate(6, (_) => commands.create(source.path)),
      );
      expect(results.toSet(), hasLength(6));
      for (final path in results) {
        expect(await File(path).readAsString(), 'content');
      }
    },
  );

  test(
    'rename followed by backup uses the new reference and preserves collisions',
    () async {
      final source = await File(
        p.join(directory.path, 'report.0.1.txt'),
      ).writeAsString('content');
      final node = FileNode(source.path);
      final renamed = await commands.renameLabel(source.path, 'approved');
      node.mate = FileMeta(renamed);
      expect(node.originalFile.path, renamed);
      final backup = await commands.create(node.mate.fullPath);
      expect(await File(backup).readAsString(), 'content');
      final conflict = await File(
        p.join(directory.path, 'report#other.0.1.txt'),
      ).writeAsString('keep');
      await expectLater(
        commands.renameLabel(renamed, 'other'),
        throwsA(isA<OperationFailure>()),
      );
      expect(await conflict.readAsString(), 'keep');
      await expectLater(
        commands.create(renamed, label: '../bad'),
        throwsA(isA<OperationFailure>()),
      );
    },
  );

  test(
    'failed writer releases locks and independent resources can proceed',
    () async {
      final writes = FileMutationCoordinator();
      await expectLater(
        writes.run(['a'], () async => throw StateError('fail')),
        throwsStateError,
      );
      expect(await writes.run(['a'], () async => 42), 42);
      await writes.close();
      await expectLater(writes.run(['a'], () async => 0), throwsStateError);
    },
  );
}
