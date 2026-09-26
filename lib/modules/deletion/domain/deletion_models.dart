import '../../../foundation/operation_control.dart';

class DeletionTarget {
  DeletionTarget(Map<String, dynamic> value) : data = Map.unmodifiable(value);
  final Map<String, dynamic> data;
  String get path => data['path'] as String;
  String get identity => data['identity'] as String;
  bool get isDirectory => data['directory'] == true;
  String get deviceKey => data['deviceKey'] as String? ?? 'unknown';
  Map<String, dynamic> toJson() => data;
}

class DeletionPlan {
  DeletionPlan(Iterable<DeletionTarget> targets)
    : targets = List.unmodifiable(targets);
  final List<DeletionTarget> targets;
  List<String> get paths => targets.map((t) => t.path).toList();
  Map<String, dynamic> toJson() => {
    'targets': targets.map((t) => t.toJson()).toList(),
  };
}

class DeletionOptions {
  const DeletionOptions({
    this.removeReadOnly = false,
    this.workers = 0,
    this.resolveBlockers = false,
  });

  /// Applied only after the user confirms permanent deletion and process closure.
  const DeletionOptions.lightning()
    : removeReadOnly = true,
      workers = 0,
      resolveBlockers = true;
  final bool removeReadOnly;
  final bool resolveBlockers;

  /// Zero selects a device-aware parallel budget; explicit values are 1..8.
  final int workers;
  Map<String, dynamic> toJson() => {
    'readOnly': removeReadOnly,
    'workers': workers,
    'resolveBlockers': resolveBlockers,
  };
}

class DeletionProgress {
  DeletionProgress(Map<String, dynamic> value) : data = Map.unmodifiable(value);
  final Map<String, dynamic> data;
  int get filesDeleted => (data['deletedFiles'] as num?)?.toInt() ?? 0;
  int get directoriesDeleted =>
      (data['deletedDirectories'] as num?)?.toInt() ?? 0;
  int get failures => (data['failedItems'] as num?)?.toInt() ?? 0;
  int get pending => (data['pendingDelete'] as num?)?.toInt() ?? 0;
  int get discovered => (data['discovered'] as num?)?.toInt() ?? 0;
  bool get enumerationComplete => data['enumerationComplete'] == true;
  double? get percent => (data['percent'] as num?)?.toDouble();
  Map<String, dynamic> toJson() => data;
}

class DeletionResult implements JobResult {
  DeletionResult({
    required this.outcome,
    required this.plan,
    required this.progress,
    this.reportPath,
    this.failures = const [],
    this.message,
  });
  @override
  final String outcome;
  final DeletionPlan plan;
  final DeletionProgress progress;
  final String? reportPath, message;

  /// Bounded UI preview; the private JSONL report contains complete failures.
  final List<Map<String, dynamic>> failures;
  @override
  Map<String, dynamic> toJson() => {
    'outcome': outcome,
    'plan': plan.toJson(),
    'progress': progress.toJson(),
    'reportPath': reportPath,
    'failures': failures,
    'message': message,
  };
}
