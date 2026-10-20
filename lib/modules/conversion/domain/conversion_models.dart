import 'dart:io';

enum ConversionState { queued, running, completed, failed, cancelled }

class ConversionFormat {
  const ConversionFormat({
    required this.id,
    required this.name,
    required this.extensions,
  });
  final String id;
  final String name;
  final List<String> extensions;
}

class ConversionJob {
  ConversionJob({required this.sources, required this.target});
  final List<String> sources;
  final String target;
  ConversionState state = ConversionState.queued;
  double progress = 0;
  List<String> outputs = const [];
  String? error;
}

bool hasFileExtension(String path, String extension) {
  final value = path.toLowerCase();
  return value.endsWith('.${extension.toLowerCase().replaceFirst('.', '')}');
}

String fileNameWithoutExtension(String path) {
  final file = File(path).uri.pathSegments.last;
  final index = file.lastIndexOf('.');
  return index > 0 ? file.substring(0, index) : file;
}
