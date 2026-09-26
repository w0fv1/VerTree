import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/file_access/file_access.dart';
import 'package:vertree/foundation/operation_control.dart';
import 'package:vertree/modules/deletion/deletion.dart';

import 'deletion_commands_test.dart' show fixturePlan, TestUsage;

class ScriptedDeletion implements DeletionBackend {
  final reports = <String?>[];
  bool succeedFirst = false, alwaysPartial = false, failRetry = false;
  @override
  Future<DeletionPlan> prepare(List<String> paths) async => fixturePlan();
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
    reports.add(retryReport);
    if (reports.length > 1 && failRetry) {
      throw StateError('retry fixture failure');
    }
    final partial = alwaysPartial || (reports.length == 1 && !succeedFirst);
    final progress = DeletionProgress({
      'deletedFiles': reports.length == 1 ? 3 : 2,
      'deletedDirectories': 0,
      'discovered': 5,
      'failedItems': partial ? 2 : 0,
    });
    onProgress(progress);
    return DeletionResult(
      outcome: partial ? 'partial' : 'succeeded',
      plan: plan,
      progress: progress,
      reportPath: 'report-${reports.length}',
    );
  }
}

class FixtureObstacles implements DeletionObstacleResolver {
  int calls = 0;
  bool retry = true, cancel = false;
  void Function()? observe;
  @override
  Future<DeletionObstacleResolution> resolve(
    DeletionResult previous,
    OperationControl control,
    void Function(DeletionProgress) onProgress,
  ) async {
    calls++;
    observe?.call();
    if (cancel) control.cancel();
    onProgress(
      DeletionProgress({
        'phase': 'releasing',
        'processesEnded': cancel ? 0 : 1,
      }),
    );
    return DeletionObstacleResolution(
      retry: retry,
      processesEnded: cancel ? 0 : 1,
    );
  }
}

void main() {
  late ScriptedDeletion backend;
  late FixtureObstacles obstacles;
  late TestUsage usage;
  late FileMutationCoordinator writes;
  late OperationControl control;
  late DeletionCommands commands;
  setUp(() {
    backend = ScriptedDeletion();
    obstacles = FixtureObstacles();
    usage = TestUsage();
    writes = FileMutationCoordinator();
    control = OperationControl();
    commands = DeletionCommands(
      backend: backend,
      obstacles: obstacles,
      writes: writes,
      usage: usage,
    );
  });
  tearDown(() async {
    await control.dispose();
    await writes.close();
  });
  Future<DeletionResult> run([
    DeletionOptions options = const DeletionOptions.lightning(),
  ]) => commands.execute(fixturePlan(), options, control, (_) {});

  test(
    'lightning policy enables automatic workers, read-only clearing and blockers',
    () {
      const options = DeletionOptions.lightning();
      expect(options.workers, 0);
      expect(options.removeReadOnly, isTrue);
      expect(options.resolveBlockers, isTrue);
    },
  );
  test('successful deletion does not scan or terminate any process', () async {
    backend.succeedFirst = true;
    expect((await run()).outcome, 'succeeded');
    expect(obstacles.calls, 0);
  });
  test(
    'one consent spans resolution and identity-bound retries with a single lease',
    () async {
      obstacles.observe = () {
        expect(writes.isReserved(r'C:\fixture\tree'), isTrue);
        expect(usage.acquired, 1);
        expect(usage.released, 0);
      };
      final result = await run();
      expect(result.outcome, 'succeeded');
      expect(result.progress.filesDeleted, 5);
      expect(result.progress.failures, 0);
      expect(result.progress.data['processesEnded'], 1);
      expect(backend.reports, [null, 'report-1']);
      expect(usage.released, 1);
      expect(writes.isReserved(r'C:\fixture\tree'), isFalse);
    },
  );
  test('ordinary policy never ends processes implicitly', () async {
    expect((await run(const DeletionOptions())).outcome, 'partial');
    expect(obstacles.calls, 0);
    expect(backend.reports.length, 1);
  });
  test('unsafe or unavailable original report is not retried', () async {
    obstacles.retry = false;
    expect((await run()).outcome, 'partial');
    expect(backend.reports.length, 1);
  });
  test(
    'cancel during resolution preserves counts and prevents further deletion',
    () async {
      obstacles.cancel = true;
      final result = await run();
      expect(result.outcome, 'cancelled');
      expect(result.progress.filesDeleted, 3);
      expect(backend.reports.length, 1);
      expect(usage.released, 1);
    },
  );
  test(
    'retry exception never double-counts previously deleted files',
    () async {
      backend.failRetry = true;
      final result = await run();
      expect(result.outcome, isNot('succeeded'));
      expect(result.progress.filesDeleted, 3);
    },
  );
  test(
    'respawning blockers are bounded, not an endless kill/retry loop',
    () async {
      backend.alwaysPartial = true;
      final result = await run();
      expect(result.outcome, 'partial');
      expect(obstacles.calls, 3);
      expect(backend.reports.length, 4);
      expect(result.progress.filesDeleted, 9);
    },
  );
}
