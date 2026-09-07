import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/modules/versions/versions.dart';
import 'package:vertree/modules/versions/infrastructure/local_version_comparator.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/file_access/infrastructure/local_file_access.dart';
import 'package:vertree/api/version_dto.dart';
import 'package:vertree/foundation/app_events.dart';
import 'package:vertree/foundation/operation_failure.dart';

void main() {
  test('restore preserves current bytes and supports save-as', () async {
    final dir = await Directory.systemTemp.createTemp('vertree-restore-test');
    addTearDown(() => dir.delete(recursive: true));
    final source = await File('${dir.path}/notes.0.1.txt').writeAsString('old');
    final current = await File(
      '${dir.path}/notes.txt',
    ).writeAsString('current');
    final operations = VersionCommands(
      files: LocalFileAccess(),
      writes: FileMutationCoordinator(),
      emit: AppEvents().emit,
    );
    final result = await operations.restore(source.path);
    expect(await current.readAsString(), 'old');
    expect(await File(result.backupPath!).readAsString(), 'current');
    expect(await source.readAsString(), 'old');
    await current.writeAsString('second');
    final second = await operations.restore(source.path);
    expect(second.backupPath, isNot(result.backupPath));
    expect(await File(result.backupPath!).readAsString(), 'current');
    expect(await File(second.backupPath!).readAsString(), 'second');
    final saved = await operations.restore(
      source.path,
      targetPath: '${dir.path}/copy.txt',
    );
    expect(saved.backupPath, isNull);
    expect(filePathFromId(fileId(source.path)), p.normalize(source.path));
  });
  test(
    'renaming cannot overwrite another version; comparison reports changes',
    () async {
      final dir = await Directory.systemTemp.createTemp('vertree-version-test');
      addTearDown(() => dir.delete(recursive: true));
      final a = await File('${dir.path}/notes.0.1.txt').writeAsString('one');
      final b = await File(
        '${dir.path}/notes#saved.0.1.txt',
      ).writeAsString('two');
      final operations = VersionCommands(
        files: LocalFileAccess(),
        writes: FileMutationCoordinator(),
        emit: AppEvents().emit,
      );
      await expectLater(
        operations.renameLabel(a.path, 'saved'),
        throwsA(isA<OperationFailure>()),
      );
      final result = await LocalVersionComparator().compare(a.path, b.path);
      expect(result.equal, false);
      expect(result.changes, isNotNull);
      expect(result.changes, isNotEmpty);
      await expectLater(
        operations.restore(a.path, targetPath: a.path),
        throwsA(isA<OperationFailure>()),
      );
    },
  );
}
