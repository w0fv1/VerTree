import 'dart:async';

import '../domain/conversion_models.dart';
import '../ports/conversion_runtime.dart';

class ConversionQueue {
  ConversionQueue(this.runtime);
  final ConversionRuntime runtime;
  final _jobs = StreamController<ConversionJob>.broadcast();
  final List<ConversionJob> history = [];
  Future<void> _tail = Future.value();
  bool _disposed = false;
  Stream<ConversionJob> get updates => _jobs.stream;

  Future<ConversionJob> enqueue(List<String> sources, String target) {
    if (_disposed) throw StateError('Conversion queue is disposed');
    final job = ConversionJob(
      sources: List.unmodifiable(sources),
      target: target,
    );
    history.insert(0, job);
    _jobs.add(job);
    final completion = _tail.then((_) async {
      job.state = ConversionState.running;
      _jobs.add(job);
      try {
        final result = await runtime.convert(
          job,
          onProgress: (value) {
            job.progress = value;
            _jobs.add(job);
          },
        );
        job.outputs = result.outputs;
        job.error = result.error;
        job.state = result.succeeded
            ? ConversionState.completed
            : ConversionState.failed;
      } catch (error) {
        job.error = error.toString();
        job.state = ConversionState.failed;
      }
      _jobs.add(job);
      return job;
    });
    _tail = completion.then<void>((_) {});
    return completion;
  }

  Future<void> dispose() {
    _disposed = true;
    return _tail.then<void>((_) async {
      await _jobs.close();
    });
  }
}
