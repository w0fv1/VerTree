import 'dart:async';
import 'package:uuid/uuid.dart';

class AppEvent {
  AppEvent(this.id, this.type, Map<String, dynamic> data, this.sessionId)
    : data = Map.unmodifiable(data),
      at = DateTime.now().toUtc();
  final int id;
  final String sessionId;
  final String type;
  final DateTime at;
  final Map<String, dynamic> data;
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'schemaVersion': 1,
    'type': type,
    'at': at.toIso8601String(),
    'data': data,
  };
}

class AppEvents {
  AppEvents({this.capacity = 256});
  final String sessionId = const Uuid().v4();
  final int capacity;
  int _sequence = 0;
  final _history = <AppEvent>[];
  final _live = StreamController<AppEvent>.broadcast(sync: true);
  int get lastId => _sequence;
  List<AppEvent> get recent => List.unmodifiable(_history);

  void emit(String type, Map<String, dynamic> data) {
    final event = AppEvent(++_sequence, type, data, sessionId);
    _history.add(event);
    if (_history.length > capacity) _history.removeAt(0);
    _live.add(event);
  }

  Future<void> dispose() => _live.close();

  Stream<AppEvent> watch({int? after, String? session}) {
    if (session != null && session != sessionId) {
      throw StateError('EVENT_CURSOR_EXPIRED: application restarted');
    }
    if (after != null &&
        (after > _sequence ||
            after < 0 ||
            (_history.isNotEmpty && after < _history.first.id - 1))) {
      throw StateError(
        'EVENT_CURSOR_EXPIRED: reload state and reconnect without a cursor',
      );
    }
    late StreamController<AppEvent> controller;
    StreamSubscription<AppEvent>? subscription;
    controller = StreamController<AppEvent>(
      onListen: () {
        subscription = _live.stream.listen(controller.add);
        if (after != null) {
          for (final event in _history.where((event) => event.id > after)) {
            controller.add(event);
          }
        }
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
