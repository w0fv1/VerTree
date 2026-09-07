import 'app_events.dart';

class PreviewActivity {
  static final instance = PreviewActivity();
  int _sequence = 0;
  Map<String, dynamic>? _current;
  Map<String, dynamic> get snapshot => {
    'current': _current == null ? null : Map<String, dynamic>.from(_current!),
  };
  int open(String path) {
    final id = ++_sequence;
    _current = {'id': id, 'path': path, 'status': 'loading'};
    AppEvents.instance.emit('preview.loading', _current!);
    return id;
  }

  void update(int id, String status, {String? message}) {
    if (_current?['id'] != id ||
        (_current?['status'] == status && _current?['message'] == message)) {
      return;
    }
    _current = {..._current!, 'status': status, 'message': ?message};
    AppEvents.instance.emit('preview.$status', _current!);
  }

  void close(int id) {
    if (_current?['id'] != id) return;
    final previous = _current!;
    _current = null;
    AppEvents.instance.emit('preview.closed', previous);
  }
}
