import '../../../foundation/operation_control.dart';
import '../domain/file_usage.dart';

abstract interface class FileLockBackend {
  Future<FileUsageSnapshot> scan(
    List<String> paths,
    OperationControl control,
    void Function(Map<String, dynamic>) onProgress, {
    bool elevated = false,
  });
  Future<Map<String, dynamic>> act(
    List<String> paths,
    FileUsageProcess process,
    FileProcessAction action,
    OperationControl control, {
    required bool confirmed,
    bool elevated = false,
  });
}
