import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vertree/service/app_events.dart';
import 'package:vertree/service/automation_jobs.dart';

void main() {
  test('cancels queued work and preserves results of completed work', () async {
    final jobs = AutomationJobs(AppEvents());
    var ran = false;
    final cancelled = jobs.start('test', (_) async { ran = true; return null; });
    jobs.cancel(cancelled.id);
    await Future<void>.delayed(Duration.zero);
    expect(ran, false); expect(cancelled.status, 'cancelled');
    final done = jobs.start('test', (_) async => 'saved');
    await Future<void>.delayed(Duration.zero);
    jobs.cancel(done.id);
    expect(done.status, 'succeeded'); expect(done.result, 'saved');
  });
  test('limits concurrent work', () async {
    final jobs = AutomationJobs(AppEvents());
    final finish = Completer<void>();
    for (var i = 0; i < 4; i++) { jobs.start('wait', (_) => finish.future); }
    expect(() => jobs.start('overflow', (_) async => null), throwsStateError);
    finish.complete();
    await Future<void>.delayed(Duration.zero);
  });
}
