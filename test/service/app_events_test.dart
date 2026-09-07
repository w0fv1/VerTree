import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/foundation/app_events.dart';

void main() {
  test('replays events and then delivers live events without gaps', () async {
    final events = AppEvents(capacity: 3);
    events.emit('first', {'value': 1});
    events.emit('second', {});
    final received = <AppEvent>[];
    final subscription = events.watch(after: 1).listen(received.add);
    events.emit('third', {});
    await Future<void>.delayed(Duration.zero);
    expect(received.map((e) => e.id), [2, 3]);
    await subscription.cancel();
  });
  test(
    'rejects expired replay cursors instead of silently dropping history',
    () {
      final events = AppEvents(capacity: 2);
      for (var i = 0; i < 5; i++) {
        events.emit('event', {});
      }
      expect(() => events.watch(after: 1), throwsStateError);
    },
  );
}
