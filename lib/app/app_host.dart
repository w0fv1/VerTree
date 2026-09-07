import 'dart:async';

class HostedResource {
  const HostedResource(this.name, {required this.start, required this.stop});
  final String name;
  final Future<void> Function() start, stop;
}

/// Starts dependencies in order and stops them in reverse, including a
/// partially-started resource. stop waits for actual cleanup, not just timeout.
class AppHost {
  AppHost(this.resources, {this.onCleanupError});
  final List<HostedResource> resources;
  final void Function(String name, Object error)? onCleanupError;
  final _started = <HostedResource>[];
  Future<void>? _starting, _stopping;
  bool _stopRequested = false;
  bool get ready => _started.length == resources.length && !_stopRequested;

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    try {
      for (final resource in resources) {
        if (_stopRequested) break;
        _started.add(resource);
        await resource.start();
      }
    } catch (_) {
      await _cleanup();
      rethrow;
    }
  }

  Future<void> stop() {
    _stopRequested = true;
    return _stopping ??= _stop();
  }

  Future<void> _stop() async {
    try {
      await _starting;
    } catch (_) {
      /* start already performs rollback */
    }
    await _cleanup();
  }

  Future<void> _cleanup() async {
    while (_started.isNotEmpty) {
      final resource = _started.removeLast();
      try {
        await resource.stop();
      } catch (error) {
        onCleanupError?.call(resource.name, error);
      }
    }
  }
}
