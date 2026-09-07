import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/file_access/infrastructure/local_file_access.dart';
import 'package:vertree/modules/snapshots/snapshots.dart';
import 'package:vertree/modules/snapshots/infrastructure/local_snapshot_store.dart';
import 'package:vertree/modules/monitoring/monitoring.dart';

class _Watcher implements FileWatcher {
  int starts = 0;
  @override
  Stream<FileChange> watch(String path) {
    starts++;
    return const Stream.empty();
  }
}

void main() {
  late Directory directory;
  late LocalSnapshotStore store;
  late SnapshotCommands snapshots;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vertree-snapshots-');
    store = LocalSnapshotStore(LocalFileAccess());
    snapshots = SnapshotCommands(
      files: LocalFileAccess(),
      store: store,
      writes: FileMutationCoordinator(),
      emit: (_, _) {},
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'retention is isolated by owner and never deletes unknown or legacy files',
    () async {
      final doc = await File(
        p.join(directory.path, 'report.docx'),
      ).writeAsString('doc');
      final pdf = await File(
        p.join(directory.path, 'report.pdf'),
      ).writeAsString('pdf');
      final a = const Uuid().v4(), b = const Uuid().v4();
      final first = await snapshots.create(doc.path, a, keep: 1);
      final other = await snapshots.create(pdf.path, b, keep: 1);
      final unknown = await File(
        p.join(store.directoryFor(doc.path, a), 'user.txt'),
      ).writeAsString('keep');
      final legacyDir = await Directory(
        p.join(directory.path, 'report_bak'),
      ).create();
      final legacyDoc = await File(
        p.join(legacyDir.path, 'report.docx_2026-09-07T01-02-03.000.bak.docx'),
      ).writeAsString('legacy');
      await File(
        p.join(legacyDir.path, 'report.pdf_2026-09-07T01-02-03.000.bak.pdf'),
      ).writeAsString('legacy pdf');
      await snapshots.create(doc.path, a, keep: 1);
      expect(await File(first.path).exists(), isFalse);
      expect(await File(other.path).readAsString(), 'pdf');
      final listed = await snapshots.list(doc.path, a);
      expect(listed, hasLength(1));

      await snapshots.clear(doc.path, a);
      expect(await unknown.exists(), isTrue);
      expect(await legacyDoc.exists(), isTrue);
      expect(await File(other.path).exists(), isTrue);
    },
  );

  test(
    'copy failure does not run retention or remove the last good snapshot',
    () async {
      final source = await File(
        p.join(directory.path, 'source.txt'),
      ).writeAsString('saved');
      final id = const Uuid().v4();
      final good = await snapshots.create(source.path, id, keep: 1);
      await source.delete();
      await expectLater(
        snapshots.create(source.path, id, keep: 1),
        throwsA(anything),
      );
      expect(await File(good.path).readAsString(), 'saved');
    },
  );

  test(
    'manager has explicit startup, rejects missing files, publishes changes and retains identity',
    () async {
      var persisted = <dynamic>[];
      final watcher = _Watcher();
      MonitManager manager() => MonitManager(
        files: LocalFileAccess(),
        snapshots: snapshots,
        watcher: watcher,
        loadTasks: () => persisted,
        saveTasks: (tasks) async {
          persisted = tasks;
        },
        interval: () => const Duration(minutes: 5),
        maxBackups: () => 50,
        emit: (_, _) {},
      );
      final tasks = manager();
      expect(watcher.starts, 0);
      await tasks.init();
      expect(
        (await tasks.addFileMonitTask(
          p.join(directory.path, 'missing.txt'),
        )).isErr,
        isTrue,
      );
      expect(tasks.monitFileTasks, isEmpty);
      var revisions = 0;
      final subscription = tasks.changes.listen((_) => revisions++);
      final file = await File(
        p.join(directory.path, 'file.txt'),
      ).writeAsString('test');
      final task = (await tasks.addFileMonitTask(file.path)).unwrap();
      expect(revisions, greaterThan(0));
      expect(() => tasks.monitFileTasks.clear(), throwsUnsupportedError);
      final snapshot = await snapshots.create(file.path, task.id, keep: 1);
      await tasks.removeFileMonitTask(file.path);
      expect(await File(snapshot.path).exists(), isTrue);
      await subscription.cancel();
      await tasks.dispose();
      final restored = manager();
      await restored.init();
      final readded = (await restored.addFileMonitTask(file.path)).unwrap();
      expect(readded.id, task.id);
      expect(await restored.listSnapshots(readded), hasLength(1));
      await restored.dispose();
    },
  );
}
