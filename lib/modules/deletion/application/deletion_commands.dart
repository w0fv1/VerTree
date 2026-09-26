import '../../../file_access/file_access.dart';
import '../../../foundation/operation_control.dart';
import '../domain/deletion_models.dart';
import '../ports/deletion_backend.dart';

class DeletionCommands {
  DeletionCommands({
    required this.backend,
    required this.writes,
    required this.usage,
    this.obstacles,
  });
  final DeletionBackend backend;
  final FileMutationCoordinator writes;
  final DeletionUsageGuard usage;
  final DeletionObstacleResolver? obstacles;
  Future<List<Map<String, dynamic>>> history() => backend.history();
  Future<DeletionPlan> prepare(List<String> paths) {
    if (paths.isEmpty || paths.length > 1024) {
      throw ArgumentError('Select between 1 and 1024 top-level items');
    }
    return backend.prepare(paths);
  }

  Future<DeletionResult> execute(
    DeletionPlan plan,
    DeletionOptions options,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  }) async {
    control.checkCancelled();
    final scopes = plan.targets
        .map(
          (target) => target.isDirectory
              ? MutationScope.subtree(target.path)
              : MutationScope.file(target.path),
        )
        .toList();
    final reservation = writes.reserve(scopes);
    Future<void> Function()? release;
    try {
      release = await usage.quiesce(plan.paths);
      return await writes.run(
        scopes,
        () => _execute(
          plan,
          options,
          control,
          onProgress,
          retryReport: retryReport,
        ),
        reservation: reservation,
      );
    } finally {
      // Keep the same reservation and usage lease throughout all scans/actions
      // and retries, until every native child has actually exited.
      reservation.release();
      await release?.call();
    }
  }

  Future<DeletionResult> _execute(
    DeletionPlan plan,
    DeletionOptions options,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  }) async {
    control.checkCancelled();
    var files = 0,
        directories = 0,
        bytes = 0,
        missing = 0,
        discovered = 0,
        ended = 0;
    var phase = 'deleting';
    DeletionProgress merge(DeletionProgress progress) {
      if (progress.discovered > discovered) discovered = progress.discovered;
      return DeletionProgress({
        ...progress.data,
        'phase': phase,
        'deletedFiles': files + progress.filesDeleted,
        'deletedDirectories': directories + progress.directoriesDeleted,
        'logicalBytesProcessed':
            bytes +
            ((progress.data['logicalBytesProcessed'] as num?)?.toInt() ?? 0),
        'alreadyMissing':
            missing + ((progress.data['alreadyMissing'] as num?)?.toInt() ?? 0),
        'discovered': discovered,
        'processesEnded': ended,
      });
    }

    var result = await backend.execute(
      plan,
      options,
      control,
      (progress) => onProgress(merge(progress)),
      retryReport: retryReport,
    );
    DeletionResult finish({String? outcome, String? message}) {
      final progress = merge(result.progress);
      onProgress(progress);
      return DeletionResult(
        outcome: outcome ?? result.outcome,
        plan: plan,
        progress: progress,
        reportPath: result.reportPath,
        failures: result.failures,
        message: message ?? result.message,
      );
    }

    if (!options.resolveBlockers || obstacles == null) return finish();
    try {
      // A bounded operation, not a persistent authorization to hunt newly
      // created files or repeatedly terminate respawning applications.
      for (var round = 0; round < 3 && result.outcome == 'partial'; round++) {
        control.checkCancelled();
        if (result.reportPath == null) break;
        phase = 'resolving';
        onProgress(merge(result.progress));
        final resolution = await obstacles!.resolve(result, control, (event) {
          final reported = event.data['phase'];
          if (reported is String) phase = reported;
          onProgress(
            DeletionProgress({
              ...merge(result.progress).data,
              ...event.data,
              'percent': null,
              'processesEnded':
                  ended +
                  ((event.data['processesEnded'] as num?)?.toInt() ?? 0),
            }),
          );
        });
        ended += resolution.processesEnded;
        control.checkCancelled();
        if (!resolution.retry) break;
        files += result.progress.filesDeleted;
        directories += result.progress.directoriesDeleted;
        bytes +=
            (result.progress.data['logicalBytesProcessed'] as num?)?.toInt() ??
            0;
        missing +=
            (result.progress.data['alreadyMissing'] as num?)?.toInt() ?? 0;
        phase = 'retrying';
        result = DeletionResult(
          outcome: 'interrupted',
          plan: plan,
          progress: DeletionProgress(const {}),
          reportPath: result.reportPath,
          failures: result.failures,
        );
        // Only identity-bound records in the existing failure report are retried.
        // Successful branches and newly created files are never rescanned.
        result = await backend.execute(
          plan,
          options,
          control,
          (progress) => onProgress(merge(progress)),
          retryReport: result.reportPath,
        );
        if (resolution.processesEnded == 0) break;
      }
    } on OperationCancelled {
      return finish(outcome: 'cancelled');
    } catch (error) {
      return finish(
        outcome: control.cancelled ? 'cancelled' : 'partial',
        message: '${result.message ?? ''}\n$error'.trim(),
      );
    }
    return finish(outcome: control.cancelled ? 'cancelled' : null);
  }
}
