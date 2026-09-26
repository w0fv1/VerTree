class FileUsageProcess {
  FileUsageProcess(Map<String, dynamic> value) : data = Map.unmodifiable(value);
  final Map<String, dynamic> data;
  int get pid => data['pid'] as int;
  String get creationTime => data['creationTime'] as String? ?? '';
  String get name => data['name'] as String? ?? 'PID $pid';
  String get imagePath => data['imagePath'] as String? ?? '';
  String get user => data['user'] as String? ?? '';
  bool get actionAllowed => data['actionAllowed'] == true;
  String get restriction => data['restriction'] as String? ?? '';
  List<Map<String, dynamic>> get files => (data['files'] as List? ?? [])
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
  Map<String, dynamic> toJson() => data;
}

class FileUsageSnapshot {
  FileUsageSnapshot({
    required this.processes,
    required this.complete,
    this.warnings = const [],
    this.details = const {},
  });
  final List<FileUsageProcess> processes;
  final bool complete;
  final List<Map<String, dynamic>> warnings;
  final Map<String, dynamic> details;
}

enum FileProcessAction { close, terminate }
