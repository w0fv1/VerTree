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
  Future<ConversionResult> convert(ConversionJob job, {void Function(double)? onProgress}) async {
    onProgress?.call(0.5);
    return const ConversionResult(outputs: ['/tmp/out.png']);
  }
}

void main() {
  test('queue records a completed conversion', () async {
    final queue = ConversionQueue(_Runtime());
    final job = await queue.enqueue(['/tmp/in.jpg'], 'png');
    expect(job.state, ConversionState.completed);
    expect(job.outputs, ['/tmp/out.png']);
    queue.dispose();
  });
}
