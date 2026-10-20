import 'dart:async';
import '../domain/conversion_models.dart';
import '../ports/conversion_runtime.dart';

class ConversionQueue {
  ConversionQueue(this.runtime);
  final ConversionRuntime runtime;
  final _jobs = StreamController<ConversionJob>.broadcast();
  final List<ConversionJob> history = [];
  bool _busy = false;
  Stream<ConversionJob> get updates => _jobs.stream;

  Future<ConversionJob> enqueue(List<String> sources, String target) async {
    final job = ConversionJob(sources: sources, target: target);
    history.insert(0, job);
    _jobs.add(job);
    while (_busy) await Future<void>.delayed(const Duration(milliseconds: 30));
    _busy = true;
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
    } finally {
      _busy = false;
      _jobs.add(job);
    }
    return job;
  }

  void dispose() => _jobs.close();
}
