import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/modules/conversion/application/conversion_queue.dart';
import 'package:vertree/modules/conversion/domain/conversion_models.dart';
import 'package:vertree/modules/conversion/ports/conversion_runtime.dart';

class _Runtime implements ConversionRuntime {
  @override
  Future<List<ConversionFormat>> formats() async => const [];
  @override
  Future<List<ConversionFormat>> targetsFor(String source) async => const [];
  @override
  Future<ConversionResult> convert(
    ConversionJob job, {
    void Function(double)? onProgress,
  }) async {
    onProgress?.call(0.5);
    return const ConversionResult(outputs: ['/tmp/out.png']);
  }
}

class _PendingRuntime extends _Runtime {
  final result = Completer<ConversionResult>();
  @override
  Future<ConversionResult> convert(
    ConversionJob job, {
    void Function(double)? onProgress,
  }) async {
    final value = await result.future;
    onProgress?.call(1);
    return value;
  }
}

void main() {
  test(
    'closing the view waits for accepted conversions before closing updates',
    () async {
      final runtime = _PendingRuntime();
      final queue = ConversionQueue(runtime);
      final completion = queue.enqueue(['input.png'], 'webp');
      final closing = queue.dispose();
      runtime.result.complete(const ConversionResult(outputs: ['output.webp']));
      expect((await completion).state, ConversionState.completed);
      await closing;
    },
  );
  test('queue records a completed conversion', () async {
    final queue = ConversionQueue(_Runtime());
    final job = await queue.enqueue(['/tmp/in.jpg'], 'png');
    expect(job.state, ConversionState.completed);
    expect(job.outputs, ['/tmp/out.png']);
    queue.dispose();
  });
}
