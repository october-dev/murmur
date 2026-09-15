import 'dart:async';
import 'dart:collection';

import 'package:murmur_protocol/murmur_protocol.dart';

/// A scriptable provider whose opens stay pending until the test decides.
final class FakeProvider implements VoiceProvider {
  FakeProvider({
    Set<ProviderCapability> capabilities = const {
      ProviderCapability.partialTranscripts,
      ProviderCapability.gracefulFinalize,
    },
    this.autoOpen = false,
  }) : capabilities = Set.unmodifiable(capabilities);

  @override
  final Set<ProviderCapability> capabilities;

  /// Completes every open immediately with a new session.
  final bool autoOpen;
  final Queue<Completer<ProviderSession>> _pending = Queue();
  final List<FakeProviderSession> sessions = [];
  final List<AudioFormat> startedFormats = [];

  FakeProviderSession get latestSession => sessions.last;
  int get pendingOpens => _pending.length;

  @override
  Future<ProviderSession> start(AudioFormat negotiated) {
    startedFormats.add(negotiated);
    if (autoOpen) return Future.value(_newSession());
    final completer = Completer<ProviderSession>();
    _pending.addLast(completer);
    return completer.future;
  }

  /// Completes the oldest pending open with a new session.
  FakeProviderSession completeOpen() {
    final session = _newSession();
    _takePending().complete(session);
    return session;
  }

  /// Fails the oldest pending open.
  void failOpen(VoiceError error) => _takePending().completeError(error);

  Completer<ProviderSession> _takePending() {
    if (_pending.isEmpty) throw StateError('no pending provider open');
    return _pending.removeFirst();
  }

  FakeProviderSession _newSession() {
    final session = FakeProviderSession();
    sessions.add(session);
    return session;
  }
}

/// A recorded gate call.
typedef GateCall = ({bool open, bool flush});

/// A [ProviderSession] that records every call and emits events on demand.
///
/// Finalization and flushes stay pending until [completeFinalize] or
/// [completeFlush] is called, so bounded waits can be exercised.
final class FakeProviderSession implements ProviderSession {
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>(sync: true);
  final List<AudioFrame> frames = [];
  final List<GateCall> gateCalls = [];
  final Queue<Completer<void>> _heldFrames = Queue();
  Completer<void>? _flush;
  Completer<FinalizationOutcome>? _finalize;
  int finalizeCalls = 0;
  int stopCalls = 0;

  /// When set, every [addFrame] waits until [releaseFrame] is called.
  bool holdFrames = false;

  /// When set, every [addFrame] throws.
  bool rejectFrames = false;

  /// When set, [stop] waits for this future before completing.
  Future<void>? stopGate;

  int get heldFrames => _heldFrames.length;
  bool get flushPending => _flush != null;
  bool get finalizePending => _finalize != null;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> addFrame(AudioFrame frame) async {
    if (rejectFrames) {
      throw StateError('frame rejected by the fake provider');
    }
    frames.add(frame);
    if (holdFrames) {
      final gate = Completer<void>();
      _heldFrames.addLast(gate);
      await gate.future;
    }
  }

  /// Lets the oldest held frame complete.
  void releaseFrame() => _heldFrames.removeFirst().complete();

  @override
  Future<void> setInputGate({
    required bool open,
    bool flushAcceptedAudio = false,
  }) {
    gateCalls.add((open: open, flush: flushAcceptedAudio));
    if (open || !flushAcceptedAudio) return Future.value();
    final flush = _flush ??= Completer<void>();
    return flush.future;
  }

  /// Acknowledges the pending flush.
  void completeFlush() {
    final flush = _flush;
    if (flush == null) throw StateError('no pending flush');
    _flush = null;
    flush.complete();
  }

  @override
  Future<FinalizationOutcome> finalize() {
    finalizeCalls++;
    final pending = _finalize ??= Completer<FinalizationOutcome>();
    return pending.future;
  }

  /// Acknowledges the pending finalization.
  void completeFinalize() {
    final pending = _finalize;
    if (pending == null) throw StateError('no pending finalize');
    _finalize = null;
    pending.complete(const FinalizationOutcome(timedOut: false));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate;
    if (!_events.isClosed) unawaited(_events.close());
  }

  /// Delivers [event] to the coordinator.
  void emit(ProviderEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
