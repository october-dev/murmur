import 'dart:async';
import 'dart:collection';

/// The clock and timer seam used by every bounded wait in the runtime.
///
/// Production hosts use [SystemScheduler]. Tests inject [ManualScheduler] so
/// every startup, endpoint, finalization, and shutdown deadline is exercised
/// under virtual time without real timers escaping into the event loop.
abstract interface class Scheduler {
  /// Elapsed microseconds on a monotonic clock.
  ///
  /// Emitted `RuntimeEvent.monotonicTimeUs` values read this clock.
  int get monotonicTimeUs;

  /// Runs [callback] once after [delay] unless the returned timer is cancelled.
  Timer schedule(Duration delay, void Function() callback);
}

/// A [Scheduler] backed by the process monotonic clock and `dart:async`.
final class SystemScheduler implements Scheduler {
  /// Creates a scheduler whose clock starts at zero.
  SystemScheduler() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  int get monotonicTimeUs => _stopwatch.elapsedMicroseconds;

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

/// A [Scheduler] whose clock only moves when [advance] is called.
///
/// Timers fire in due order, then in scheduling order, during [advance]. A
/// callback that schedules another timer within the advanced window fires in
/// the same call.
final class ManualScheduler implements Scheduler {
  final SplayTreeMap<int, Queue<_ManualTimer>> _due = SplayTreeMap();
  int _nowUs = 0;

  @override
  int get monotonicTimeUs => _nowUs;

  /// The number of timers that have not fired or been cancelled.
  int get pendingTimers =>
      _due.values.fold(0, (count, queue) => count + queue.length);

  @override
  Timer schedule(Duration delay, void Function() callback) {
    final dueUs = _nowUs + (delay.isNegative ? 0 : delay.inMicroseconds);
    final timer = _ManualTimer(this, dueUs, callback);
    _due.putIfAbsent(dueUs, Queue.new).addLast(timer);
    return timer;
  }

  /// Moves the clock forward by [duration], firing every timer that comes due.
  void advance(Duration duration) {
    final targetUs = _nowUs + duration.inMicroseconds;
    while (true) {
      final nextDue = _due.firstKey();
      if (nextDue == null || nextDue > targetUs) break;
      _nowUs = nextDue;
      final queue = _due[nextDue]!;
      final timer = queue.removeFirst();
      if (queue.isEmpty) _due.remove(nextDue);
      timer._fire();
    }
    _nowUs = targetUs;
  }

  void _cancel(_ManualTimer timer) {
    final queue = _due[timer._dueUs];
    if (queue == null) return;
    queue.remove(timer);
    if (queue.isEmpty) _due.remove(timer._dueUs);
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this._scheduler, this._dueUs, this._callback);

  final ManualScheduler _scheduler;
  final int _dueUs;
  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _scheduler._cancel(this);
  }

  void _fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}
