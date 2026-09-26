import '../../../file_access/infrastructure/windows_file_worker.dart';
import '../../../foundation/operation_control.dart';
import '../domain/file_usage.dart';
import '../ports/file_lock_backend.dart';

class WindowsFileLockBackend implements FileLockBackend {
  WindowsFileLockBackend(this.worker);
  final WindowsFileWorker worker;
  @override
  Future<FileUsageSnapshot> scan(
    List<String> paths,
    OperationControl control,
    void Function(Map<String, dynamic>) onProgress, {
    bool elevated = false,
  }) async {
    final partial = <String, FileUsageProcess>{};
    try {
      final result = await worker.run(
        {'op': elevated ? 'elevatedScan' : 'scan', 'paths': paths},
        control: control,
        onEvent: (event) {
          if (event['type'] == 'process') {
            final process = FileUsageProcess(
              Map<String, dynamic>.from(event['process'] as Map),
            );
            partial['${process.pid}:${process.creationTime}'] = process;
          }
          onProgress({...event, 'foundProcesses': partial.length});
        },
      );
      return FileUsageSnapshot(
        processes: List.unmodifiable(
          (result['processes'] as List).map(
            (value) =>
                FileUsageProcess(Map<String, dynamic>.from(value as Map)),
          ),
        ),
        complete: result['complete'] == true,
        warnings: (result['warnings'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(),
        details: Map.unmodifiable(result),
      );
    } on FileWorkerException catch (error) {
      if (error.code != 'WORKER_TIMEOUT' && error.code != 'WORKER_INTERRUPTED') {
        rethrow;
      }
      return FileUsageSnapshot(
        processes: List.unmodifiable(partial.values),
        complete: false,
        warnings: [
          {'code': error.code, 'message': error.message},
        ],
        details: {'cancelled': control.cancelled, 'scope': 'local-machine'},
      );
    }
  }

  @override
  Future<Map<String, dynamic>> act(
    List<String> paths,
    FileUsageProcess process,
    FileProcessAction action,
    OperationControl control, {
    required bool confirmed,
    bool elevated = false,
  }) {
    if (!confirmed) throw StateError('CONFIRMATION_REQUIRED');
    return worker.run({
      'op': elevated ? 'elevatedProcess' : 'process',
      'paths': paths,
      'pid': process.pid,
      'creationTime': process.creationTime,
      'action': action.name,
      'confirmed': true,
    }, control: control);
  }
}
