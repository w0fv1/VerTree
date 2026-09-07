import 'dart:async';
import 'package:test/test.dart';
import 'package:vertree/foundation/clock.dart';
import 'package:vertree/modules/monitoring/monitoring.dart';

class _Call implements ScheduledCall {
  _Call(this.at, this.callback);
  final DateTime at;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }
}

class _Clock implements Clock {
  DateTime time = DateTime.utc(2026);
  final calls = <_Call>[];
  @override
  DateTime now() => time;
  @override
  ScheduledCall schedule(Duration delay, void Function() callback) {
    final call = _Call(time.add(delay), callback);
    calls.add(call);
    return call;
  }

  Future<void> advance(Duration duration) async {
    time = time.add(duration);
    final due = calls.where((call) => !call.at.isAfter(time)).toList();
    calls.removeWhere((call) => due.contains(call));
    for (final call in due) {
      if (!call.cancelled) call.callback();
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _Watcher implements FileWatcher {
  final changes = StreamController<FileChange>.broadcast(sync: true);
  @override
  Stream<FileChange> watch(String path) => changes.stream;
}

class _RecoveringWatcher implements FileWatcher {
  int attempts = 0;
  final changes = StreamController<FileChange>.broadcast(sync: true);
  @override
  Stream<FileChange> watch(String path) {
    if (++attempts < 4) throw StateError('directory unavailable');
    return changes.stream;
  }
}

void main() {
  test(
    'watcher retry survives successful snapshots and stop cancels retries',
    () async {
      final clock = _Clock(), watcher = _RecoveringWatcher();
      final monitor = Monitor(
        filePath: '/file.txt',
        backupDirPath: '/snapshots',
        watcher: watcher,
        clock: clock,
        interval: () => Duration.zero,
        emit: (_, _) {},
        createSnapshot: () async => '/snapshot',
      );
      monitor.start();
      for (var i = 0; i < 2; i++) {
        await clock.advance(const Duration(seconds: 2));
        await clock.advance(const Duration(milliseconds: 150));
        expect(monitor.status, 'degraded');
      }
      await clock.advance(const Duration(seconds: 2));
      await clock.advance(const Duration(milliseconds: 150));
      expect(watcher.attempts, 4);
      expect(monitor.status, 'running');
      await monitor.stop();
      await clock.advance(const Duration(seconds: 10));
      expect(watcher.attempts, 4);
      await watcher.changes.close();
    },
  );
  test(
    'failed copy does not advance success clock; retries and trailing changes are retained',
    () async {
      final clock = _Clock(), watcher = _Watcher();
      var attempts = 0;
      final monitor = Monitor(
        filePath: '/file.txt',
        backupDirPath: '/snapshots',
        watcher: watcher,
        clock: clock,
        interval: () => const Duration(minutes: 5),
        emit: (_, _) {},
        createSnapshot: () async {
          attempts++;
          if (attempts == 1) throw StateError('busy');
          return '/snapshot-$attempts';
        },
      );
      monitor.start();
      monitor.start();
      watcher.changes.add(const FileChange('/file.txt', 2));
      await clock.advance(const Duration(milliseconds: 150));
      expect(monitor.lastBackupTime, isNull);
      expect(monitor.status, 'degraded');
      await clock.advance(const Duration(seconds: 2));
      expect(attempts, 2);
      expect(monitor.createdBackupCount, 1);
      expect(monitor.status, 'running');
      watcher.changes.add(const FileChange('/file.txt', 2));
      await clock.advance(const Duration(minutes: 1));
      expect(attempts, 2);
      await clock.advance(const Duration(minutes: 4));
      expect(attempts, 3);
      watcher.changes.add(const FileChange('/file.txt', 2));
      await monitor.stop();
      await clock.advance(const Duration(minutes: 10));
      expect(attempts, 3);
      await watcher.changes.close();
    },
  );
}
