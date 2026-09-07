import 'package:test/test.dart';
import 'package:vertree/app/app_host.dart';

void main() {
  test(
    'partial startup rolls back in reverse order and stop is idempotent',
    () async {
      final calls = <String>[];
      final host = AppHost([
        HostedResource(
          'a',
          start: () async {
            calls.add('start a');
          },
          stop: () async {
            calls.add('stop a');
          },
        ),
        HostedResource(
          'b',
          start: () async {
            calls.add('start b');
            throw StateError('failed');
          },
          stop: () async {
            calls.add('stop b');
          },
        ),
      ]);
      await expectLater(host.start(), throwsStateError);
      await host.stop();
      await host.stop();
      expect(calls, ['start a', 'start b', 'stop b', 'stop a']);
      expect(host.ready, isFalse);
    },
  );
}
