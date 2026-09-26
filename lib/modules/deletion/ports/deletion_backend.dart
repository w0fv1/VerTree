import '../../../foundation/operation_control.dart';
import '../domain/deletion_models.dart';

abstract interface class DeletionBackend {
  Future<DeletionPlan> prepare(List<String> paths);
  Future<List<Map<String, dynamic>>> history();
  Future<DeletionResult> execute(
    DeletionPlan plan,
    DeletionOptions options,
    OperationControl control,
    void Function(DeletionProgress) onProgress, {
    String? retryReport,
  });
}

abstract interface class DeletionUsageGuard {
  /// Suspend only selected ranges; the returned callback releases the lease.
  Future<Future<void> Function()> quiesce(List<String> paths);
}

/// Resolve only original, verified failure records; never scan fresh subtrees.
abstract interface class DeletionObstacleResolver {
  Future<DeletionObstacleResolution> resolve(
    DeletionResult previous,
    OperationControl control,
    void Function(DeletionProgress) onProgress,
  );
}

class DeletionObstacleResolution {
  const DeletionObstacleResolution({
    this.retry = false,
    this.processesEnded = 0,
  });
  final bool retry;
  final int processesEnded;
}
