import 'dart:async';
import 'package:uuid/uuid.dart';
import 'app_events.dart';

class JobCancelled implements Exception {}

class AutomationJob {
  AutomationJob(this.kind, this.events);
  final String id = const Uuid().v4();
  final String kind;
  final AppEvents events;
  final DateTime createdAt = DateTime.now().toUtc();
  String status = 'queued';
  double progress = 0;
  bool cancelRequested = false;
  Object? result;
  String? error;
  bool get completed => ['succeeded', 'failed', 'cancelled'].contains(status);
  void checkCancelled() {
    if (cancelRequested) throw JobCancelled();
  }

  void update(double value) {
    progress = value.clamp(0, 1);
    events.emit('job.progress', toJson());
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'status': status,
    'progress': progress,
    'cancelRequested': cancelRequested,
    'createdAt': createdAt.toIso8601String(),
    'result': result,
    'error': error,
  };
}

class AutomationJobs {
  AutomationJobs(this.events);
  final AppEvents events;
  final _jobs = <String, AutomationJob>{};
  List<Map<String, dynamic>> list() =>
      _jobs.values.map((job) => job.toJson()).toList();
  AutomationJob? get(String id) => _jobs[id];
  AutomationJob start(
    String kind,
    Future<Object?> Function(AutomationJob job) run,
  ) {
    if (_jobs.values.where((job) => !job.completed).length >= 4) {
      throw StateError('JOB_LIMIT: four jobs are already active');
    }
    if (_jobs.length >= 100) {
      _jobs.remove(_jobs.values.firstWhere((job) => job.completed).id);
    }
    final job = AutomationJob(kind, events);
    _jobs[job.id] = job;
    events.emit('job.queued', job.toJson());
    unawaited(
      Future<void>(() async {
        try {
          job.checkCancelled();
          job.status = 'running';
          events.emit('job.started', job.toJson());
          job.result = await run(job);
          job.status = 'succeeded';
          job.progress = 1;
        } on JobCancelled {
          job.status = 'cancelled';
        } catch (error) {
          job.status = 'failed';
          job.error = error.toString();
        }
        events.emit('job.${job.status}', job.toJson());
      }),
    );
    return job;
  }

  AutomationJob cancel(String id) {
    final job = _jobs[id];
    if (job == null) throw StateError('JOB_NOT_FOUND');
    if (!job.completed) {
      job.cancelRequested = true;
      events.emit('job.cancel-requested', job.toJson());
    }
    return job;
  }
}
