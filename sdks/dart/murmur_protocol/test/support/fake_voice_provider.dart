import 'dart:async';
import 'dart:collection';

import 'package:murmur_protocol/murmur_protocol.dart';

/// A deterministic, manually driven [VoiceProvider] for tests.
///
/// Nothing happens on a timer: tests complete held operations and emit events
/// explicitly. By default every session enforces the [ProviderSession]
/// contract. [ignoreCancellation] opts into a broken provider whose [stop]
/// neither closes events nor settles pending operations.
final class FakeVoiceProvider implements VoiceProvider {
  /// Creates a fake provider.
  ///
  /// [supportedEncodings] defaults to every [AudioEncoding]. With [holdStart],
  /// each session's start stays pending until [FakeProviderSession.completeStart]
  /// or [FakeProviderSession.failStart]. Declaring
  /// [ProviderCapability.warmUnmute] without [ProviderCapability.immediateMute]
  /// throws [ArgumentError].
  FakeVoiceProvider({
    this.id = 'fake',
    Set<ProviderCapability> capabilities = const {},
    Set<AudioEncoding>? supportedEncodings,
    this.holdStart = false,
    this.ignoreCancellation = false,
  }) : capabilities = Set.unmodifiable(capabilities),
       _supportedEncodings = Set.unmodifiable(
         supportedEncodings ?? AudioEncoding.values,
       ) {
    if (capabilities.contains(ProviderCapability.warmUnmute) &&
        !capabilities.contains(ProviderCapability.immediateMute)) {
      throw ArgumentError.value(
        capabilities,
        'capabilities',
        'warmUnmute requires immediateMute',
      );
    }
  }

  @override
  final String id;

  @override
  final Set<ProviderCapability> capabilities;

  final bool holdStart;
  final bool ignoreCancellation;
  final Set<AudioEncoding> _supportedEncodings;
  final List<FakeProviderSession> _sessions = [];

  /// Every session created so far, oldest first.
  List<FakeProviderSession> get sessions => UnmodifiableListView(_sessions);

  @override
  FakeProviderSession createSession(ProviderSessionRequest request) {
    if (!_supportedEncodings.contains(request.format.encoding)) {
      throw VoiceError(
        code: 'unsupported_format',
        message: 'The fake provider cannot decode this audio format.',
        retryable: false,
      );
    }
    final session = FakeProviderSession._(this, request);
    _sessions.add(session);
    return session;
  }
}

/// A session of [FakeVoiceProvider] with test controls.
///
/// Controls that settle an operation throw [StateError] when nothing is
/// pending on a live session, and do nothing after the session ended, which
/// models a late provider callback.
final class FakeProviderSession implements ProviderSession {
  FakeProviderSession._(this._provider, this.request);

  final FakeVoiceProvider _provider;

  /// The request this session was created for.
  final ProviderSessionRequest request;

  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>(sync: true);
  final List<AudioFrame> _frames = [];

  Completer<void>? _start;
  var _started = false;
  Completer<void>? _heldFrame;
  AudioFrame? _heldFrameValue;
  BigInt? _lastSequence;
  var _muted = false;
  Completer<void>? _mute;
  Completer<void>? _unmute;
  Completer<void>? _finalize;
  var _finalized = false;
  VoiceError? _endError;
  Future<void>? _stop;

  /// Whether each [addFrame] stays pending until [releaseFrame].
  bool holdFrames = false;

  var _startCalls = 0;
  var _finalizeCalls = 0;
  var _stopCalls = 0;

  /// Every [start] call, including shared and rejected ones.
  int get startCalls => _startCalls;

  /// Every [finalize] call, including shared and rejected ones.
  int get finalizeCalls => _finalizeCalls;

  /// Every [stop] call, including shared and ignored ones.
  int get stopCalls => _stopCalls;

  /// Frames the session accepted, in order. Discarded frames are absent.
  List<AudioFrame> get frames => UnmodifiableListView(_frames);

  /// The number of frames waiting for [releaseFrame], either 0 or 1.
  int get heldFrames => _heldFrame == null ? 0 : 1;

  /// Whether the input gate is closed by [mute] and not yet reopened.
  bool get muted => _muted;

  /// Whether [events] has been closed.
  bool get isClosed => _events.isClosed;

  bool get startPending => _isPending(_start);
  bool get mutePending => _isPending(_mute);
  bool get unmutePending => _isPending(_unmute);
  bool get finalizePending => _isPending(_finalize);

  bool get _ended => _finalized || _endError != null;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> start() {
    _startCalls++;
    final pending = _start;
    if (pending != null && !pending.isCompleted) return pending.future;
    if (pending != null || _ended) {
      throw StateError('a provider session starts only once');
    }
    final start = _start = Completer<void>();
    if (!_provider.holdStart) completeStart();
    return start.future;
  }

  /// Completes a start held by [FakeVoiceProvider.holdStart].
  void completeStart() {
    if (_ended) return;
    final start = _requirePending(_start, 'start');
    _started = true;
    start.complete();
  }

  /// Fails a pending start with [error] and closes [events].
  void failStart(VoiceError error) {
    if (_ended) return;
    _requirePending(_start, 'start');
    _end(error);
  }

  @override
  Future<void> addFrame(AudioFrame frame) {
    final endError = _endError;
    if (endError != null) return Future.error(endError);
    if (_finalized) return Future.value();
    if (!_started) {
      throw StateError('frames are accepted only after start completes');
    }
    if (unmutePending) {
      throw StateError('frames are not accepted while unmute is pending');
    }
    if (_heldFrame != null) {
      throw StateError('another frame is still outstanding');
    }
    _validate(frame);
    if (_muted || finalizePending) return Future.value();
    if (!holdFrames) {
      _frames.add(frame);
      return Future.value();
    }
    _heldFrameValue = frame;
    return (_heldFrame = Completer<void>()).future;
  }

  /// Accepts the frame held by [holdFrames].
  void releaseFrame() {
    if (_ended) return;
    final held = _requirePending(_heldFrame, 'frame');
    _frames.add(_heldFrameValue!);
    _heldFrame = null;
    _heldFrameValue = null;
    held.complete();
  }

  @override
  Future<void> mute() {
    _requireCapability(ProviderCapability.immediateMute, 'mute');
    final endError = _endError;
    if (endError != null) return Future.error(endError);
    _requireGateTransition();
    final pending = _mute;
    if (pending != null) return pending.future;
    if (unmutePending) {
      throw StateError('mute cannot start while unmute is pending');
    }
    if (_muted) return Future.value();
    _muted = true;
    return (_mute = Completer<void>()).future;
  }

  /// Completes a pending mute flush.
  ///
  /// Throws [StateError] while a frame is held, because it belongs to the
  /// flushed tail.
  void completeMute() {
    if (_ended) return;
    final mute = _requirePending(_mute, 'mute');
    _requireNoHeldFrame();
    _mute = null;
    mute.complete();
  }

  @override
  Future<void> unmute() {
    _requireCapability(ProviderCapability.warmUnmute, 'unmute');
    final endError = _endError;
    if (endError != null) return Future.error(endError);
    _requireGateTransition();
    final pending = _unmute;
    if (pending != null) return pending.future;
    if (mutePending) {
      throw StateError('unmute cannot start while a mute flush is pending');
    }
    if (!_muted) return Future.value();
    return (_unmute = Completer<void>()).future;
  }

  /// Completes a pending unmute and reopens the input gate.
  void completeUnmute() {
    if (_ended) return;
    final unmute = _requirePending(_unmute, 'unmute');
    _unmute = null;
    _muted = false;
    unmute.complete();
  }

  @override
  Future<void> finalize() {
    _finalizeCalls++;
    final existing = _finalize;
    if (existing != null) return existing.future;
    final endError = _endError;
    if (endError != null) {
      // Later calls replay this identical terminal outcome.
      return (_finalize = Completer<void>()..completeError(endError)).future;
    }
    if (!_started) {
      throw StateError('finalize requires a started session');
    }
    if (mutePending || unmutePending) {
      throw StateError('finalize cannot start while a gate change is pending');
    }
    return (_finalize = Completer<void>()).future;
  }

  /// Completes a pending finalize, then closes [events].
  ///
  /// Throws [StateError] while a frame is held, because it belongs to the
  /// finalized tail.
  void completeFinalize() {
    if (_ended) return;
    final finalize = _requirePending(_finalize, 'finalize');
    _requireNoHeldFrame();
    _finalized = true;
    finalize.complete();
    unawaited(_events.close());
  }

  @override
  Future<void> stop() {
    _stopCalls++;
    if (_provider.ignoreCancellation) return Future.value();
    final existing = _stop;
    if (existing != null) return existing;
    // Cache first: closing the sync stream notifies listeners reentrantly.
    final stop = _stop = Future.value();
    if (!_ended) {
      _end(
        VoiceError(
          code: 'cancelled',
          message: 'The provider session was cancelled.',
          retryable: true,
        ),
      );
    }
    return stop;
  }

  /// Fails the session with [error].
  ///
  /// While start is pending this acts like [failStart]. After start it emits
  /// one [ProviderFailure], completes pending operations with [error], and
  /// closes [events].
  void fail(VoiceError error) {
    if (_ended) return;
    if (startPending) {
      _end(error);
      return;
    }
    _requireStartCalled();
    _end(error, lastEvent: ProviderFailure(error));
  }

  /// Fails the session with a retryable `provider_disconnected` error.
  void disconnect() {
    fail(
      VoiceError(
        code: 'provider_disconnected',
        message: 'The provider connection closed unexpectedly.',
        retryable: true,
      ),
    );
  }

  // Each emit checks termination before building its event, so a late
  // callback with an invalid value adds nothing instead of throwing.

  void emitPartial(String text) {
    if (_canEmit()) _events.add(ProviderPartial(text));
  }

  void emitFinal(String text) {
    if (_canEmit()) _events.add(ProviderFinal(text));
  }

  void rejectFinal(String text) {
    if (_canEmit(ProviderCapability.rejectedFinals)) {
      _events.add(ProviderRejected(text));
    }
  }

  void emitReadiness({required bool live}) {
    if (_canEmit(ProviderCapability.realAudioReadiness)) {
      _events.add(ProviderReadiness(live: live));
    }
  }

  void emitAmplitude(double value) {
    if (_canEmit(ProviderCapability.amplitude)) {
      _events.add(ProviderAmplitude(value));
    }
  }

  /// Whether an event may be added now.
  ///
  /// An undeclared [capability] throws [StateError] in every state.
  bool _canEmit([ProviderCapability? capability]) {
    if (capability != null && !_provider.capabilities.contains(capability)) {
      throw StateError('this event requires ${capability.name}');
    }
    if (_ended) return false;
    _requireStartCalled();
    return true;
  }

  /// Ends the session with [error] and settles every pending operation.
  ///
  /// The terminal state is recorded before [lastEvent] and done are delivered,
  /// so a listener that reenters the session observes the ended session.
  void _end(VoiceError error, {ProviderEvent? lastEvent}) {
    _endError = error;
    for (final pending in [_start, _heldFrame, _mute, _unmute, _finalize]) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(error);
      }
    }
    _heldFrame = null;
    _heldFrameValue = null;
    if (lastEvent != null) _events.add(lastEvent);
    unawaited(_events.close());
  }

  void _validate(AudioFrame frame) {
    final expected = request.format;
    final actual = frame.format;
    if (actual.sampleRateHz != expected.sampleRateHz ||
        actual.channels != expected.channels ||
        actual.encoding != expected.encoding ||
        actual.frameDurationMs != expected.frameDurationMs) {
      throw ArgumentError.value(frame, 'frame', 'does not match the format');
    }
    final last = _lastSequence;
    if (last != null && frame.sequence <= last) {
      throw ArgumentError.value(
        frame,
        'frame',
        'sequence must be strictly increasing',
      );
    }
    _lastSequence = frame.sequence;
  }

  void _requireCapability(ProviderCapability capability, String operation) {
    if (!_provider.capabilities.contains(capability)) {
      throw UnsupportedError('$operation requires ${capability.name}');
    }
  }

  void _requireGateTransition() {
    if (_finalize != null) {
      throw StateError('the input gate cannot change after finalize');
    }
    if (!_started) {
      throw StateError('the input gate changes only after start completes');
    }
  }

  void _requireStartCalled() {
    if (_start == null) {
      throw StateError('the session has not been started');
    }
  }

  void _requireNoHeldFrame() {
    if (_heldFrame != null) {
      throw StateError('a held frame must be released first');
    }
  }

  Completer<void> _requirePending(Completer<void>? operation, String name) {
    if (!_isPending(operation)) {
      throw StateError('no $name is pending');
    }
    return operation!;
  }

  static bool _isPending(Completer<void>? operation) =>
      operation != null && !operation.isCompleted;
}
