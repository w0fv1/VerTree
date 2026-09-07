import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import '../../foundation/operation_failure.dart';

/// Publish an already complete file without replacing an existing destination.
/// Windows: MoveFileExW without REPLACE_EXISTING. POSIX: link + unlink.
/// Unsupported filesystems fail; there is no unsafe copy-to-final fallback.
Future<void> publishFile(String source, String destination) => Isolate.run(() {
  if (Platform.isWindows) {
    final library = DynamicLibrary.open('kernel32.dll');
    final move = library
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('MoveFileExW');
    final lastError = library.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
    String extended(String path) => path.startsWith(r'\\?\')
        ? path
        : path.startsWith(r'\\')
        ? '\\\\?\\UNC\\${path.substring(2)}'
        : '\\\\?\\$path';
    final from = extended(source).toNativeUtf16(),
        to = extended(destination).toNativeUtf16();
    try {
      if (move(from, to, 8) == 0) {
        final code = lastError();
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
  final library = DynamicLibrary.process();
  final link = library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)
      >('link');
  final errno = library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );
  final from = source.toNativeUtf8(), to = destination.toNativeUtf8();
  try {
    if (link(from, to) != 0) {
      final code = errno().value;
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
