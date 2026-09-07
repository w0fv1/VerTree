import 'dart:async';

abstract interface class ScheduledCall {
  void cancel();
}

abstract interface class Clock {
  DateTime now();
  ScheduledCall schedule(Duration delay, void Function() callback);
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
  @override
  ScheduledCall schedule(Duration delay, void Function() callback) =>
      _TimerCall(Timer(delay, callback));
}

class _TimerCall implements ScheduledCall {
  _TimerCall(this.timer);
  final Timer timer;
  @override
  void cancel() => timer.cancel();
}
