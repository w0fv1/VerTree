import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import '../../foundation/operation_failure.dart';

@Native<Int32 Function(Pointer<Void>, Pointer<Void>)>(
  symbol: 'vertree_publish_file',
)
external int _publish(Pointer<Void> source, Pointer<Void> destination);

/// Publish an already complete file without replacing an existing destination.
/// Windows: MoveFileExW without REPLACE_EXISTING. POSIX: link + unlink.
/// Unsupported filesystems fail; there is no unsafe copy-to-final fallback.
Future<void> publishFile(String source, String destination) => Isolate.run(() {
  if (Platform.isWindows) {
    String extended(String path) => path.startsWith(r'\\?\')
        ? path
        : path.startsWith(r'\\')
        ? '\\\\?\\UNC\\${path.substring(2)}'
        : '\\\\?\\$path';
    final from = extended(source).toNativeUtf16(),
        to = extended(destination).toNativeUtf16();
    try {
      final code = _publish(from.cast(), to.cast());
      if (code != 0) {
        if (code == 80 || code == 183) {
          throw const OperationFailure(
            'VERSION_EXISTS',
            'Target already exists',
          );
        }
        throw FileSystemException(
          'Cannot publish file',
          destination,
          OSError('MoveFileExW failed', code),
        );
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
    return;
  }
  final from = source.toNativeUtf8(), to = destination.toNativeUtf8();
  try {
    final code = _publish(from.cast(), to.cast());
    if (code != 0) {
      if (code == 17) {
        throw const OperationFailure('VERSION_EXISTS', 'Target already exists');
      }
      throw FileSystemException(
        'Cannot publish file',
        destination,
        OSError('link failed', code),
      );
    }
    try {
      File(source).deleteSync();
    } catch (_) {
      throw const OperationFailure(
        'RECOVERY_REQUIRED',
        'Target committed; source link could not be removed',
      );
    }
  } finally {
    calloc.free(from);
    calloc.free(to);
  }
});
