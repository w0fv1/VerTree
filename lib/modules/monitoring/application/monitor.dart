import 'dart:async';
import '../../../foundation/clock.dart';
import '../ports/file_watcher.dart';

class Monitor {
  Monitor({
    required this.filePath,
    required this.backupDirPath,
    required this.watcher,
    required this.createSnapshot,
    required this.interval,
    required this.emit,
    this.onChanged,
    this.clock = const SystemClock(),
  });
  final String filePath, backupDirPath;
  final FileWatcher watcher;
  final Future<String> Function() createSnapshot;
  final Duration Function() interval;
  final void Function(String, Map<String, dynamic>) emit;
  final void Function()? onChanged;
  final Clock clock;
  StreamSubscription<FileChange>? _subscription;
  ScheduledCall? _scheduled, _watchRetry;
  Future<void>? _inFlight;
  bool _enabled = false, _dirty = false;
  DateTime? startedAt, lastObservedEventAt, lastBackupTime;
  String? lastObservedEventPath, lastBackupPath;
  String? _watchError, _backupError;
  String? get lastError => _watchError ?? _backupError;
  int observedEventCount = 0, createdBackupCount = 0;
  bool get isHandlingFileChange => _inFlight != null;
  String get status => !_enabled
      ? 'stopped'
      : lastError != null
      ? 'degraded'
      : 'running';

  void start() {
    if (_enabled) return;
    _enabled = true;
    startedAt = clock.now();
    _attach();
    emit('monitor.started', {'path': filePath});
    onChanged?.call();
  }

  void _attach() {
    try {
      _watchError = null;
      _subscription = watcher
          .watch(filePath)
          .listen(
            (event) {
              observedEventCount++;
              lastObservedEventAt = clock.now();
              lastObservedEventPath = event.path;
              _dirty = true;
              emit('file.changed', {'path': filePath, 'eventType': event.type});
              _schedule();
            },
            onError: (Object error) {
              _watchFailed(error);
            },
            onDone: () {
              if (_enabled) _watchFailed(StateError('File watcher ended'));
            },
            cancelOnError: true,
          );
    } catch (error) {
      _watchFailed(error);
    }
  }

  void _watchFailed(Object error) {
    _subscription = null;
    _watchError = error.toString();
    _error(error);
    _watchRetry?.cancel();
    if (_enabled) {
      _watchRetry = clock.schedule(const Duration(seconds: 2), () {
        if (_enabled) {
          _attach();
          _dirty = true;
          _schedule();
        }
      });
    }
  }

  void _error(Object error) {
    emit('monitor.error', {'path': filePath, 'message': lastError});
    onChanged?.call();
  }

  void _schedule({Duration? retry}) {
    if (!_enabled || !_dirty || _inFlight != null) return;
    _scheduled?.cancel();
    var delay = retry ?? const Duration(milliseconds: 150);
    if (retry == null && lastBackupTime != null) {
      final remaining = interval() - clock.now().difference(lastBackupTime!);
      if (remaining > delay) delay = remaining;
    }
    _scheduled = clock.schedule(delay, () {
      if (!_enabled) return;
      _inFlight = _backup();
      unawaited(
        _inFlight!.whenComplete(() {
          _inFlight = null;
          _schedule(
            retry: _backupError == null ? null : const Duration(seconds: 2),
          );
        }),
      );
    });
  }

  Future<void> _backup() async {
    _dirty = false;
    try {
      lastBackupPath = await createSnapshot();
      lastBackupTime = clock.now();
      createdBackupCount++;
      _backupError = null;
    } catch (error) {
      _dirty = true;
      _backupError = error.toString();
      _error(error);
    }
    onChanged?.call();
  }

  Future<void> stop() async {
    _enabled = false;
    _dirty = false;
    _scheduled?.cancel();
    _watchRetry?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _inFlight;
    emit('monitor.stopped', {'path': filePath});
    onChanged?.call();
  }
}
