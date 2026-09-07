import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/service/version_operations.dart';
import 'package:vertree/service/app_events.dart';

void main() {
  test('restore preserves current bytes and supports save-as', () async {
    final dir = await Directory.systemTemp.createTemp('vertree-restore-test');
    addTearDown(() => dir.delete(recursive: true));
    final source = await File('${dir.path}/notes.0.1.txt').writeAsString('old');
    final current = await File(
      '${dir.path}/notes.txt',
    ).writeAsString('current');
    final operations = VersionOperations(AppEvents());
    final result = await operations.restore(source.path);
    expect(await current.readAsString(), 'old');
    expect(
      await File(result['backupPath'] as String).readAsString(),
      'current',
    );
    expect(await source.readAsString(), 'old');
    await current.writeAsString('second');
    final second = await operations.restore(source.path);
    expect(second['backupPath'], isNot(result['backupPath']));
    expect(
      await File(result['backupPath'] as String).readAsString(),
      'current',
    );
    expect(await File(second['backupPath'] as String).readAsString(), 'second');
    final saved = await operations.restore(
      source.path,
      targetPath: '${dir.path}/copy.txt',
    );
    expect(saved['backupPath'], isNull);
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
      final operations = VersionOperations(AppEvents());
      await expectLater(
        operations.renameLabel(a.path, 'saved'),
        throwsStateError,
      );
      final result = await operations.compare(a.path, b.path);
      expect(result['equal'], false);
      expect(result['mode'], 'text');
      expect(result['changes'], isNotEmpty);
      await expectLater(
        operations.restore(a.path, targetPath: a.path),
        throwsFormatException,
      );
    },
  );
}
