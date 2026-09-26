import 'dart:async';

class OperationCancelled implements Exception {}

/// Cooperative control. A cancelled operation never implies rollback.
class OperationControl {
  bool _cancelled = false, _paused = false;
  final _changes = StreamController<void>.broadcast(sync: true);
  bool get cancelled => _cancelled;
  bool get paused => _paused;
  Stream<void> get changes => _changes.stream;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _paused = false;
    if (!_changes.isClosed) _changes.add(null);
  }

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    if (!_changes.isClosed) _changes.add(null);
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    if (!_changes.isClosed) _changes.add(null);
  }

  void checkCancelled() {
    if (_cancelled) throw OperationCancelled();
  }

  Future<void> dispose() => _changes.close();
}

abstract interface class JobResult {
  String get outcome;
  Object? toJson();
}
