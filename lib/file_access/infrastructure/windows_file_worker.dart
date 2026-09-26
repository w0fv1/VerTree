import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../foundation/operation_control.dart';

class FileWorkerException implements Exception {
  const FileWorkerException(this.code, this.message, {this.nativeCode});
  final String code, message;
  final int? nativeCode;
  @override
  String toString() => '$code: $message';
}

class _DeviceTicket {
  _DeviceTicket(this.keys);
  final Set<String> keys;
  final done = Completer<void>();
}

/// One application-owned native bridge. There is no shell invocation and no
/// privileged long-lived service. A reservation must remain held until run()
/// returns: cancellation waits for the actual worker process to exit.
class WindowsFileWorker {
  WindowsFileWorker({String? executable, this.protectedPaths = const []})
    : executable =
          executable ??
          p.join(
            p.dirname(Platform.resolvedExecutable),
            'vertree_file_worker.exe',
          );
  final String executable;
  final List<String> protectedPaths;
  final _active = <Process, OperationControl>{};
  final _deviceTickets = <_DeviceTicket>[];
  int _workerTokens = 0;
  Completer<void> _budgetChanged = Completer<void>();
  bool _closed = false;
  int get activeProcessCount => _active.length;

  Future<T> withDeviceBudget<T>(
    Iterable<String> keys,
    int desired,
    OperationControl control,
    Future<T> Function(int maximumWorkers) action,
  ) async {
    if (_closed) throw StateError('File worker is stopping');
    final normalized = keys.map((key) => key.toLowerCase()).toSet();
    if (normalized.isEmpty) normalized.add('unknown');
    final ticket = _DeviceTicket(normalized);
    final predecessors = _deviceTickets
        .where((other) => other.keys.any(normalized.contains))
        .map((other) => other.done.future)
        .toList();
    _deviceTickets.add(ticket);
    int allocation = 0;
    try {
      final ready = Future.wait(predecessors).then((_) {});
      await _waitCancellable(ready, control);
      while (_workerTokens >= 8) {
        await _waitCancellable(_budgetChanged.future, control);
      }
      control.checkCancelled();
      allocation = math.min(desired.clamp(1, 8), 8 - _workerTokens);
      _workerTokens += allocation;
      return await action(allocation);
    } finally {
      _workerTokens -= allocation;
      _deviceTickets.remove(ticket);
      ticket.done.complete();
      final previous = _budgetChanged;
      _budgetChanged = Completer<void>();
      previous.complete();
    }
  }

  Future<void> _waitCancellable(
    Future<void> future,
    OperationControl control,
  ) async {
    final cancelled = Completer<void>();
    final subscription = control.changes.listen((_) {
      if (control.cancelled && !cancelled.isCompleted) {
        cancelled.completeError(OperationCancelled());
      }
    });
    try {
      control.checkCancelled();
      await Future.any([future, cancelled.future]);
      control.checkCancelled();
    } finally {
      await subscription.cancel();
    }
  }

  Future<Map<String, dynamic>> run(
    Map<String, dynamic> request, {
    OperationControl? control,
    FutureOr<void> Function(Map<String, dynamic> event)? onEvent,
  }) async {
    if (_closed) throw StateError('File worker is stopping');
    if (!Platform.isWindows) {
      throw const FileWorkerException(
        'UNSUPPORTED_PLATFORM',
        'Windows file tools are available only on Windows',
      );
    }
    if (!await File(executable).exists()) {
      throw FileWorkerException(
        'WORKER_NOT_FOUND',
        'Native helper is missing: $executable. Rebuild the Windows application.',
      );
    }
    final ownControl = control == null;
    final operationControl = control ?? OperationControl();
    operationControl.checkCancelled();
    final op = request['op'] as String;
    final elevated = op.startsWith('elevated');
    final encoded = utf8.encode(
      '${jsonEncode({...request, 'v': 1, 'hostPid': pid, 'initialPaused': operationControl.paused, 'protectedPaths': protectedPaths})}\n',
    );
    if (encoded.length > 4 * 1024 * 1024) {
      throw const FileWorkerException(
        'PROTOCOL_LIMIT',
        'The selected paths exceed the request-size limit',
      );
    }
    final process = await Process.start(
      executable,
      ['--stdio'],
      workingDirectory: p.dirname(executable),
      runInShell: false,
    );
    _active[process] = operationControl;
    final started = DateTime.now();
    var lastMessage = started;
    DateTime? cancelAt;
    String? abortCode;
    var sentCancel = false;
    bool? sentPause;
    var processExited = false;
    Map<String, dynamic>? result;
    FileWorkerException? remoteError;
    var terminal = false;
    var stderrText = '';
    final exitFuture = process.exitCode.then((code) {
      processExited = true;
      return code;
    });
    final errors = process.stderr.listen((bytes) {
      if (stderrText.length < 8192) {
        stderrText += utf8.decode(
          bytes.take(8192 - stderrText.length).toList(),
          allowMalformed: true,
        );
      }
    });
    void sendControl() {
      if (processExited) return;
      try {
        if (operationControl.cancelled && !sentCancel) {
          sentCancel = true;
          cancelAt = DateTime.now();
          process.stdin.writeln(jsonEncode({'v': 1, 'control': 'cancel'}));
        }
        if (!sentCancel && sentPause != operationControl.paused) {
          sentPause = operationControl.paused;
          if (sentPause == true) {
            process.stdin.writeln(jsonEncode({'v': 1, 'control': 'pause'}));
          } else if (sentPause == false) {
            process.stdin.writeln(jsonEncode({'v': 1, 'control': 'resume'}));
          }
        }
      } catch (_) {
        // Broken input is reconciled with the actual exit code below.
      }
    }

    final subscription = operationControl.changes.listen((_) => sendControl());
    final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (processExited || terminal) return;
      final now = DateTime.now();
      final elapsed = now.difference(started);
      final idle = now.difference(lastMessage);
      if (!operationControl.paused && !operationControl.cancelled) {
        final idleLimit = Duration(
          seconds: elevated
              ? 110
              : op == 'delete'
              ? 90
              : 8,
        );
        final totalLimit = Duration(
          seconds: elevated
              ? 185
              : op == 'prepare'
              ? 35
              : op == 'process'
              ? 110
              : 70,
        );
        if (idle > idleLimit || (op != 'delete' && elapsed > totalLimit)) {
          abortCode = 'WORKER_TIMEOUT';
          operationControl.cancel();
        }
      }
      sendControl();
      if (cancelAt != null &&
          now.difference(cancelAt!) > const Duration(seconds: 11)) {
        abortCode ??= 'WORKER_INTERRUPTED';
        process
            .kill(); // This is only our own isolated child, never an occupying application.
      }
    });
    try {
      process.stdin.add(encoded);
      await process.stdin.flush();
      sendControl();
      await for (final frame in _frames(process.stdout)) {
        lastMessage = DateTime.now();
        final event = jsonDecode(frame);
        if (event is! Map<String, dynamic> || event['v'] != 1 || terminal) {
          throw const FileWorkerException(
            'PROTOCOL_ERROR',
            'Invalid or post-terminal worker message',
          );
        }
        switch (event['type']) {
          case 'result':
            if (event['result'] is! Map<String, dynamic>) {
              throw const FileWorkerException(
                'PROTOCOL_ERROR',
                'Invalid terminal result',
              );
            }
            terminal = true;
            result = event['result'] as Map<String, dynamic>;
          case 'error':
            terminal = true;
            remoteError = FileWorkerException(
              event['code'] as String? ?? 'NATIVE_ERROR',
              event['message'] as String? ?? 'Native operation failed',
              nativeCode: event['win32'] as int?,
            );
          case 'progress':
          case 'failure':
          case 'warning':
          case 'scanProgress':
          case 'process':
            await onEvent?.call(event);
          default:
            throw const FileWorkerException(
              'PROTOCOL_ERROR',
              'Unknown worker message type',
            );
        }
      }
      final exit = await exitFuture;
      if (abortCode != null) {
        throw FileWorkerException(
          abortCode!,
          'The isolated worker was stopped; completed deletions are not rolled back.',
        );
      }
      if (remoteError != null) throw remoteError;
      if (exit != 0 || result == null) {
        throw FileWorkerException(
          'WORKER_INTERRUPTED',
          'Worker exited without a verified result (exit $exit). $stderrText',
        );
      }
      return result;
    } catch (_) {
      if (!processExited) {
        operationControl.cancel();
        sendControl();
        process.kill();
      }
      // Do not release filesystem range reservations while a native process can
      // still make changes. Waiting here is intentional even after cancellation.
      await exitFuture;
      rethrow;
    } finally {
      timer.cancel();
      await subscription.cancel();
      await errors.cancel();
      try {
        await process.stdin.close();
      } catch (_) {}
      _active.remove(process);
      if (ownControl) await operationControl.dispose();
    }
  }

  static Stream<String> _frames(Stream<List<int>> source) async* {
    final pending = BytesBuilder(copy: false);
    const maximum = 4 * 1024 * 1024;
    await for (final chunk in source) {
      var start = 0;
      for (var index = 0; index < chunk.length; ++index) {
        if (chunk[index] != 10) continue;
        if (pending.length + index - start > maximum) {
          throw const FileWorkerException(
            'PROTOCOL_LIMIT',
            'Native output frame exceeded 4 MiB',
          );
        }
        pending.add(chunk.sublist(start, index));
        yield utf8.decode(pending.takeBytes());
        start = index + 1;
      }
      if (start < chunk.length) pending.add(chunk.sublist(start));
      if (pending.length > maximum) {
        throw const FileWorkerException(
          'PROTOCOL_LIMIT',
          'Native output frame exceeded 4 MiB',
        );
      }
    }
    if (pending.length != 0) {
      throw const FileWorkerException(
        'PROTOCOL_TRUNCATED',
        'Native process ended in the middle of a message',
      );
    }
  }

  Future<void> dispose() async {
    _closed = true;
    for (final control in _active.values.toList()) {
      control.cancel();
    }
    await Future.wait(_active.keys.map((process) => process.exitCode).toList());
  }
}
