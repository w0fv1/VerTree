import 'dart:async';
import 'package:path/path.dart' as p;

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

/// A mutation describes its entire footprint before acquiring any resource.
/// Windows paths compare conservatively case-insensitively: this may serialize
/// two case-sensitive names, but never makes a deletion lock less restrictive.
enum MutationScopeKind { file, directoryEntries, subtree, task }

class MutationScope {
  MutationScope.file(String path) : this._(MutationScopeKind.file, path);
  MutationScope.directoryEntries(String path)
    : this._(MutationScopeKind.directoryEntries, path);
  MutationScope.subtree(String path) : this._(MutationScopeKind.subtree, path);
  MutationScope.task(String key) : this._(MutationScopeKind.task, key);
  MutationScope._(this.kind, String value)
    : value = kind == MutationScopeKind.task ? value : normalizePath(value);
  final MutationScopeKind kind;
  final String value;

  static String normalizePath(String value) {
    final windows =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');
    if (windows) {
      var normalized = p.Context(style: p.Style.windows).normalize(value);
      if (normalized.startsWith(r'\\?\UNC\')) {
        normalized = r'\\' + normalized.substring(8);
      } else if (normalized.startsWith(r'\\?\')) {
        normalized = normalized.substring(4);
      }
      return normalized.replaceAll('\\', '/').toLowerCase();
    }
    return p.posix.normalize(value);
  }

  static bool containsPath(String parent, String child) {
    final a = normalizePath(parent), b = normalizePath(child);
    return a == b || b.startsWith(a.endsWith('/') ? a : '$a/');
  }

  bool overlaps(MutationScope other) {
    if (kind == MutationScopeKind.task ||
        other.kind == MutationScopeKind.task) {
      return kind == other.kind && value == other.value;
    }
    if (value == other.value) return true;
    if (kind == MutationScopeKind.subtree && containsPath(value, other.value)) {
      return true;
    }
    if (other.kind == MutationScopeKind.subtree &&
        containsPath(other.value, value)) {
      return true;
    }
    if (kind == MutationScopeKind.directoryEntries &&
        p.posix.dirname(other.value) == value) {
      return true;
    }
    if (other.kind == MutationScopeKind.directoryEntries &&
        p.posix.dirname(value) == other.value) {
      return true;
    }
    return false;
  }
}

class MutationReservation {
  MutationReservation._(this.scopes, this._owner);
  final List<MutationScope> scopes;
  final FileMutationCoordinator _owner;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _owner._reservations.remove(this);
  }
}

class _MutationTicket {
  _MutationTicket(this.scopes);
  final List<MutationScope> scopes;
  final done = Completer<void>();
}

/// One instance is shared by all writers. Multi-resource acquisition is atomic,
/// FIFO among conflicting requests, and never locks unrelated ancestors.
/// A reservation rejects NEW overlapping operations while existing work drains.
class FileMutationCoordinator {
  final _pending = <_MutationTicket>[];
  final _reservations = <MutationReservation>[];
  bool _accepting = true;

  static bool _overlap(List<MutationScope> a, List<MutationScope> b) =>
      a.any((left) => b.any(left.overlaps));

  bool isReserved(String path) =>
      _reservations.any((r) => _overlap(r.scopes, [MutationScope.file(path)]));

  MutationReservation reserve(Iterable<MutationScope> resources) {
    if (!_accepting) throw StateError('Application is stopping');
    final scopes = List<MutationScope>.unmodifiable(resources);
    if (scopes.isEmpty) throw ArgumentError('Empty mutation reservation');
    if (_reservations.any((r) => _overlap(r.scopes, scopes))) {
      throw StateError(
        'PATH_BUSY: another destructive operation reserved this range',
      );
    }
    final reservation = MutationReservation._(scopes, this);
    _reservations.add(reservation);
    return reservation;
  }

  Future<T> run<T>(
    Iterable<MutationScope> resources,
    Future<T> Function() action, {
    MutationReservation? reservation,
  }) async {
    if (!_accepting) throw StateError('Application is stopping');
    if (Zone.current[this] == true) {
      throw StateError('Nested acquisition of the mutation coordinator');
    }
    final scopes = List<MutationScope>.unmodifiable(resources);
    if (reservation != null &&
        (reservation._released || !identical(reservation._owner, this))) {
      throw StateError('Invalid mutation reservation');
    }
    if (_reservations.any(
      (r) => !identical(r, reservation) && _overlap(r.scopes, scopes),
    )) {
      throw StateError('PATH_BUSY: path is reserved for deletion');
    }
    final ticket = _MutationTicket(scopes);
    final predecessors = _pending
        .where((other) => _overlap(other.scopes, scopes))
        .map((other) => other.done.future)
        .toList();
    _pending.add(ticket);
    try {
      await Future.wait(predecessors);
      return await runZoned(action, zoneValues: {this: true});
    } finally {
      _pending.remove(ticket);
      ticket.done.complete();
    }
  }

  Future<void> close() async {
    _accepting = false;
    await Future.wait(_pending.map((entry) => entry.done.future).toList());
  }
}
