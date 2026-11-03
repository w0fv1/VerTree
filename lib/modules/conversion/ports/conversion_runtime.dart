import '../domain/conversion_models.dart';

abstract interface class ConversionRuntime {
  Future<List<ConversionFormat>> formats();
  Future<List<ConversionFormat>> targetsFor(String source);
  Future<ConversionResult> convert(
    ConversionJob job, {
    void Function(double)? onProgress,
  });
}

class ConversionResult {
  const ConversionResult({this.outputs = const [], this.error});
  final List<String> outputs;
  final String? error;
  bool get succeeded => error == null;
}
