import 'dart:async';

/// File metadata used for optimistic conflict detection, not a content lock.
class FileFingerprint {
  const FileFingerprint(this.size, this.modified, this.changed);
  final int size;
  final DateTime modified;
  final DateTime changed;
  @override
  bool operator ==(Object other) =>
      other is FileFingerprint &&
      size == other.size &&
      modified == other.modified &&
      changed == other.changed;
  @override
  int get hashCode => Object.hash(size, modified, changed);
}

abstract interface class FileAccess {
  Future<String> canonicalize(String path);
  Future<bool> exists(String path);
  Future<List<String>> files(String directory);
  Future<FileFingerprint> fingerprint(String path);
  Future<void> copyNew(String source, String destination);
  Future<void> renameNew(String source, String destination);
  Future<void> replace(String source, String target, FileFingerprint? expected);
}

/// One instance is shared by all application writers. Acquire all resources
/// together; a callback must not recursively acquire this coordinator.
class FileMutationCoordinator {
  final Map<String, Future<void>> _tails = {};
  bool _accepting = true;

  Future<T> run<T>(
    Iterable<String> resources,
    Future<T> Function() action,
  ) async {
    if (!_accepting) throw StateError('Application is stopping');
    final keys = resources.toSet().toList()..sort();
    final predecessors = keys
        .map((key) => _tails[key])
        .whereType<Future<void>>()
        .toList();
    final done = Completer<void>();
    for (final key in keys) {
      _tails[key] = done.future;
    }
    try {
      await Future.wait(predecessors);
      return await action();
    } finally {
      done.complete();
      for (final key in keys) {
        if (identical(_tails[key], done.future)) _tails.remove(key);
      }
    }
  }

  Future<void> close() async {
    _accepting = false;
    await Future.wait(_tails.values.toSet());
  }
}
