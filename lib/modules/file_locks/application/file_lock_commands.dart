import '../../../foundation/operation_control.dart';
import '../domain/file_usage.dart';
import '../ports/file_lock_backend.dart';

class FileLockCommands {
  FileLockCommands(this.backend);
  final FileLockBackend backend;
  Future<FileUsageSnapshot> scan(
    List<String> paths,
    OperationControl control,
    void Function(Map<String, dynamic>) onProgress, {
    bool elevated = false,
  }) {
    if (paths.isEmpty || paths.length > 1024) {
      throw ArgumentError('Select 1 to 1024 paths');
    }
    return backend.scan(
      List.unmodifiable(paths),
      control,
      onProgress,
      elevated: elevated,
    );
  }

  Future<Map<String, dynamic>> act(
    List<String> paths,
    FileUsageProcess process,
    FileProcessAction action,
    OperationControl control, {
    required bool confirmed,
    bool elevated = false,
  }) {
    if (!confirmed || !process.actionAllowed || process.creationTime.isEmpty) {
      throw StateError('PROCESS_ACTION_NOT_CONFIRMED_OR_ALLOWED');
    }
    return backend.act(
      List.unmodifiable(paths),
      process,
      action,
      control,
      confirmed: true,
      elevated: elevated,
    );
  }
}
