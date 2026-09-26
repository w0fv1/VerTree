import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/foundation/app_events.dart';
import 'package:vertree/foundation/operation_control.dart';
import 'package:vertree/modules/automation/automation.dart';
import 'package:vertree/modules/deletion/deletion.dart';
import 'package:vertree/modules/file_locks/file_locks.dart';

DeletionPlan fixturePlan() => DeletionPlan([
  DeletionTarget({
    'path': r'C:\fixture\tree',
    'identity': 'original',
    'directory': true,
    'deviceKey': 'disk:0',
    'ancestors': ['volume', 'fixture'],
  }),
]);

class TestBackend implements DeletionBackend {
  int prepareCalls = 0, executeCalls = 0;
  Future<DeletionResult> Function(OperationControl)? operation;
  @override
  Future<DeletionPlan> prepare(List<String> paths) async {
    prepareCalls++;
    return fixturePlan();
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => [];
  @override
  Future<DeletionResult> execute(
    DeletionPlan plan,
    DeletionOptions options,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  }) async {
    executeCalls++;
    onProgress(DeletionProgress({'discovered': 1, 'percent': null}));
    if (operation != null) return operation!(control);
    return DeletionResult(
      outcome: 'partial',
      plan: plan,
      progress: DeletionProgress({'failedItems': 1}),
      reportPath: 'owned-report',
    );
  }
}

class TestUsage implements DeletionUsageGuard {
  int acquired = 0, released = 0;
  Object? error;
  @override
  Future<Future<void> Function()> quiesce(List<String> paths) async {
    acquired++;
    if (error != null) throw error!;
    return () async {
      released++;
    };
  }
}

class TestLocks implements FileLockBackend {
  int actions = 0;
  @override
  Future<FileUsageSnapshot> scan(
    List<String> paths,
    OperationControl control,
    void Function(Map<String, dynamic>) onProgress, {
    bool elevated = false,
  }) async => FileUsageSnapshot(processes: [], complete: false);
  @override
  Future<Map<String, dynamic>> act(
    List<String> paths,
    FileUsageProcess process,
    FileProcessAction action,
    OperationControl control, {
    required bool confirmed,
    bool elevated = false,
  }) async {
    actions++;
    return {'status': 'exited'};
  }
}

void main() {
  late FileMutationCoordinator writes;
  late TestBackend backend;
  late TestUsage usage;
  late DeletionCommands deletion;
  late OperationControl control;
  setUp(() {
    writes = FileMutationCoordinator();
    backend = TestBackend();
    usage = TestUsage();
    deletion = DeletionCommands(backend: backend, writes: writes, usage: usage);
    control = OperationControl();
  });
  tearDown(() async {
    await control.dispose();
    await writes.close();
  });

  test('preparation never deletes, and selection size is bounded', () async {
    expect(() => deletion.prepare([]), throwsArgumentError);
    expect(() => deletion.prepare(List.filled(1025, 'x')), throwsArgumentError);
    await deletion.prepare([r'C:\fixture\tree']);
    expect(backend.prepareCalls, 1);
    expect(backend.executeCalls, 0);
    expect(usage.acquired, 0);
  });
  test(
    'deletion reserves subtree immediately and waits for existing writers',
    () async {
      final writerStarted = Completer<void>(),
          writerRelease = Completer<void>();
      final writer = writes.run(
        [MutationScope.file(r'C:\fixture\tree\file')],
        () async {
          writerStarted.complete();
          await writerRelease.future;
        },
      );
      await writerStarted.future;
      final deleting = deletion.execute(
        fixturePlan(),
        const DeletionOptions(),
        control,
        (_) {},
      );
      expect(writes.isReserved(r'C:\fixture\tree\file'), isTrue);
      await expectLater(
        writes.run([MutationScope.file(r'C:\fixture\tree\new')], () async {}),
        throwsStateError,
      );
      await writes.run([
        MutationScope.file(r'C:\fixture\sibling'),
      ], () async {});
      expect(backend.executeCalls, 0);
      writerRelease.complete();
      await writer;
      expect((await deleting).outcome, 'partial');
      expect(usage.released, 1);
      expect(writes.isReserved(r'C:\fixture\tree\file'), isFalse);
    },
  );
  test('quiescence failure releases reservation without executing', () async {
    usage.error = StateError('fixture quiesce failure');
    await expectLater(
      deletion.execute(fixturePlan(), const DeletionOptions(), control, (_) {}),
      throwsStateError,
    );
    expect(backend.executeCalls, 0);
    expect(writes.isReserved(r'C:\fixture\tree'), isFalse);
  });
  test('native failure still releases usage and file reservations', () async {
    backend.operation = (_) async => throw StateError('fixture native failure');
    await expectLater(
      deletion.execute(fixturePlan(), const DeletionOptions(), control, (_) {}),
      throwsStateError,
    );
    expect(usage.released, 1);
    expect(writes.isReserved(r'C:\fixture\tree'), isFalse);
  });
  test('cancelled request cannot start native work', () async {
    control.cancel();
    await expectLater(
      deletion.execute(fixturePlan(), const DeletionOptions(), control, (_) {}),
      throwsA(isA<OperationCancelled>()),
    );
    expect(usage.acquired, 0);
    expect(backend.executeCalls, 0);
  });
  test(
    'reservation remains until native cancellation has actually settled',
    () async {
      final entered = Completer<void>(), exited = Completer<void>();
      backend.operation = (_) async {
        entered.complete();
        await exited.future;
        return DeletionResult(
          outcome: 'cancelled',
          plan: fixturePlan(),
          progress: DeletionProgress({}),
        );
      };
      final future = deletion.execute(
        fixturePlan(),
        const DeletionOptions(),
        control,
        (_) {},
      );
      await entered.future;
      control.cancel();
      expect(writes.isReserved(r'C:\fixture\tree'), isTrue);
      expect(usage.released, 0);
      exited.complete();
      expect((await future).outcome, 'cancelled');
      expect(writes.isReserved(r'C:\fixture\tree'), isFalse);
      expect(usage.released, 1);
    },
  );
  test('automation preserves partial result and unknown progress', () async {
    final events = AppEvents();
    final jobs = AutomationJobs(events);
    final done = Completer<void>();
    final subscription = events.watch().listen((event) {
      if (event.type == 'job.partial') done.complete();
    });
    final job = jobs.start('file.delete', (job) async {
      job.update(null);
      return DeletionResult(
        outcome: 'partial',
        plan: fixturePlan(),
        progress: DeletionProgress({'failedItems': 1}),
      );
    });
    await done.future;
    expect(job.status, 'partial');
    expect(job.progress, isNull);
    expect(job.toJson()['result'], isA<Map<String, dynamic>>());
    expect(job.completed, isTrue);
    await subscription.cancel();
    await jobs.dispose();
    await events.dispose();
  });
  test(
    'lock actions require explicit confirmation and actionable identity',
    () async {
      final backend = TestLocks(), control = OperationControl();
      final commands = FileLockCommands(backend);
      final process = FileUsageProcess({
        'pid': 100,
        'creationTime': '0000000000000001',
        'actionAllowed': true,
      });
      expect(
        () => commands.act(
          ['path'],
          process,
          FileProcessAction.terminate,
          control,
          confirmed: false,
        ),
        throwsStateError,
      );
      expect(
        () => commands.act(
          ['path'],
          FileUsageProcess({
            'pid': 100,
            'creationTime': '',
            'actionAllowed': true,
          }),
          FileProcessAction.terminate,
          control,
          confirmed: true,
        ),
        throwsStateError,
      );
      expect(backend.actions, 0);
      expect(
        (await commands.act(
          ['path'],
          process,
          FileProcessAction.close,
          control,
          confirmed: true,
        ))['status'],
        'exited',
      );
      expect(backend.actions, 1);
      await control.dispose();
    },
  );
}
