import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'events.dart';
import 'protocol.dart';
import 'provider.dart';
import 'runtime.dart';
import 'scheduler.dart';
import 'session.dart';
import 'source.dart';

/// The lifecycle state of a capture generation.
///
/// [stopped] and [error] are terminal for a generation. The next
/// [VoiceCaptureCoordinator.start] begins a new generation whose first wire
/// transition is from [idle]; no `STOPPED -> IDLE` event is manufactured for
/// the old session.
enum CaptureState {
  idle('SESSION_STATE_IDLE'),
  starting('SESSION_STATE_STARTING'),
  listening('SESSION_STATE_LISTENING'),
  warmMuted('SESSION_STATE_WARM_MUTED'),
  finalizing('SESSION_STATE_FINALIZING'),
  stopped('SESSION_STATE_STOPPED'),
  error('SESSION_STATE_ERROR');

  const CaptureState(this.protoJsonName);

  /// The `murmur.v1.SessionState` ProtoJSON enum name.
  final String protoJsonName;
}

/// Deadlines for every wait the coordinator performs, each with a typed
/// outcome.
final class CaptureTimeouts {
  const CaptureTimeouts({
    this.startup = const Duration(seconds: 10),
    this.endpoint = const Duration(milliseconds: 1500),
    this.finalize = const Duration(seconds: 3),
    this.shutdown = const Duration(seconds: 2),
    this.warmHold = const Duration(seconds: 8),
  });

  /// Connect plus provider open. Elapsing fails the generation with a
  /// retryable `startup_timeout` error.
  final Duration startup;

  /// How long hands-free capture waits after a final segment before it
  /// finalizes the utterance. A partial segment restarts the wait.
  final Duration endpoint;

  /// How long finalization or a warm flush waits for the provider. Elapsing
  /// is graceful: the segments already delivered form the utterance.
  final Duration finalize;

  /// How long [VoiceCaptureCoordinator.stop] and a superseding start wait for
  /// cleanup. Elapsing detaches cleanup, which then never publishes.
  final Duration shutdown;

  /// How long a released hold-to-talk session stays warm-muted before it
  /// stops.
  final Duration warmHold;
}

/// The bound on frames waiting for the provider.
///
/// The same bound covers pre-roll while the provider opens and backpressure
/// while it decodes. When either limit is exceeded the oldest frame is dropped.
final class PreRoll {
  const PreRoll({this.maxFrames = 100, this.maxBytes = 512 * 1024});

  final int maxFrames;
  final int maxBytes;
}

/// Decides when a frame proves that real audio is arriving.
///
/// Used only when the provider lacks [ProviderCapability.realAudioReadiness].
abstract interface class CaptureReadinessPolicy {
  bool isMeaningful(AudioFrame frame);
}

/// Treats a PCM frame as meaningful when any sample exceeds [threshold] of
/// full scale.
///
/// Opus payloads cannot be inspected and count as meaningful; hosts with Opus
/// sources should prefer a provider that reports readiness.
final class PcmReadinessPolicy implements CaptureReadinessPolicy {
  const PcmReadinessPolicy({this.threshold = 0.01});

  final double threshold;

  @override
  bool isMeaningful(AudioFrame frame) {
    final bytes = base64Decode(base64.normalize(frame.payloadBase64));
    final data = ByteData.sublistView(bytes);
    switch (frame.format.encoding) {
      case AudioEncoding.pcmS16le:
        final limit = threshold * 32767;
        for (var offset = 0; offset + 2 <= bytes.length; offset += 2) {
          if (data.getInt16(offset, Endian.little).abs() > limit) return true;
        }
        return false;
      case AudioEncoding.pcmF32le:
        for (var offset = 0; offset + 4 <= bytes.length; offset += 4) {
          if (data.getFloat32(offset, Endian.little).abs() > threshold) {
            return true;
          }
        }
        return false;
      case AudioEncoding.opus:
        return true;
    }
  }
}

/// Produces the wire session identifier for each generation.
typedef SessionIdFactory = String Function();

/// Receives each assembled utterance exactly once.
typedef UtteranceCallback = void Function(String text);

/// An immutable view of the coordinator that any UI can render.
final class CaptureSnapshot {
  const CaptureSnapshot({
    required this.state,
    required this.mode,
    required this.sessionId,
    required this.amplitude,
    required this.partialText,
    required this.bufferedFinalText,
    required this.captureLive,
    required this.finalizePending,
    required this.error,
  });

  const CaptureSnapshot.idle()
    : this(
        state: CaptureState.idle,
        mode: null,
        sessionId: null,
        amplitude: 0,
        partialText: '',
        bufferedFinalText: '',
        captureLive: false,
        finalizePending: false,
        error: null,
      );

  final CaptureState state;

  /// The mode of the current generation, or `null` before the first start.
  final CaptureMode? mode;

  /// The wire session identifier, or `null` before the first start.
  final String? sessionId;

  /// The latest normalized input level.
  final double amplitude;

  /// The latest partial hypothesis.
  final String partialText;

  /// Accepted final segments joined by single spaces.
  final String bufferedFinalText;

  /// Whether meaningful audio has reached the provider.
  final bool captureLive;

  /// Whether a flush or finalization is waiting for the provider.
  final bool finalizePending;

  /// The failure that ended the generation, or `null`.
  final VoiceError? error;
}

/// The single owner of one capture generation at a time.
///
/// Per generation it connects a fresh [VoiceSession], opens a
/// [ProviderSession], gates and finalizes input, assembles the utterance, and
/// emits ordered `murmur.v1` events. Late work from a superseded generation
/// never publishes state or delivers an utterance.
final class VoiceCaptureCoordinator {
  VoiceCaptureCoordinator(
    this._connector,
    this._provider, {
    this.onUtteranceFinalized,
    this.timeouts = const CaptureTimeouts(),
    this.preRoll = const PreRoll(),
    this.readinessPolicy = const PcmReadinessPolicy(),
    SessionIdFactory? sessionIdFactory,
    Scheduler? scheduler,
  }) : _sessionIdFactory = sessionIdFactory ?? _defaultSessionId,
       _scheduler = scheduler ?? SystemScheduler();

  final VoiceConnector _connector;
  final VoiceProvider _provider;

  /// Called synchronously with each non-empty assembled utterance.
  final UtteranceCallback? onUtteranceFinalized;
  final CaptureTimeouts timeouts;
  final PreRoll preRoll;
  final CaptureReadinessPolicy readinessPolicy;
  final SessionIdFactory _sessionIdFactory;
  final Scheduler _scheduler;
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final StreamController<CaptureState> _states =
      StreamController<CaptureState>.broadcast();
  _Generation? _current;

  static int _sessionCounter = 0;

  static String _defaultSessionId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'capture-$stamp-${++_sessionCounter}';
  }

  /// Ordered `murmur.v1` events, without replay.
  ///
  /// Subscribe first and then read [snapshot]; the snapshot may be newer than
  /// an event still in delivery. Cleanup never waits for consumers.
  Stream<RuntimeEvent> get events => _events.stream;

  /// Lifecycle transitions of the current generation, without replay.
  Stream<CaptureState> get stateChanges => _states.stream;

  /// The current view of the coordinator.
  ///
  /// Reports [CaptureState.idle] before the first start. After a generation
  /// ends its terminal snapshot stays readable until the next start.
  CaptureSnapshot get snapshot =>
      _current?.snapshot ?? const CaptureSnapshot.idle();

  /// Begins a new capture generation.
  ///
  /// An active generation is superseded: it stops synchronously and its
  /// cleanup is awaited for at most [CaptureTimeouts.shutdown] before the new
  /// session connects. A warm-muted hold-to-talk generation for the same source
  /// and mode resumes instead. Completes when audio is live, or with a
  /// [VoiceError] whose code is `cancelled` when a stop wins first, or with
  /// the failure that ended startup.
  Future<void> start({
    required VoiceSource source,
    CaptureMode mode = CaptureMode.tapToSpeak,
    AudioFormat? requestedFormat,
  }) {
    if (mode == CaptureMode.unspecified || mode == CaptureMode.wakePhrase) {
      throw ArgumentError.value(mode, 'mode', 'is not a coordinator policy');
    }
    final previous = _current;
    var previousCleanup = Future<void>.value();
    if (previous != null) {
      if (!previous.ended) {
        if (previous.state == CaptureState.warmMuted &&
            previous.source.id == source.id &&
            previous.mode == mode) {
          return previous.resume();
        }
        previousCleanup = previous.end(CaptureState.stopped);
      } else {
        previousCleanup = previous.cleanupBounded;
      }
    }
    final generation = _Generation(
      this,
      sessionId: _sessionIdFactory(),
      source: source,
      mode: mode,
      requestedFormat: requestedFormat,
    );
    _current = generation;
    return generation.begin(previousCleanup);
  }

  /// Ends the held utterance.
  ///
  /// The input gate closes synchronously; audio accepted before the release
  /// still reaches the utterance within [CaptureTimeouts.finalize]. With a
  /// warm-gate provider in hold-to-talk mode the session parks warm-muted for
  /// [CaptureTimeouts.warmHold]; otherwise this finalizes. During startup it
  /// cancels the generation. A no-op before start, while parked, or after stop.
  Future<void> release() {
    final generation = _current;
    if (generation == null || generation.ended) return Future.value();
    return generation.release();
  }

  /// Finalizes the current generation.
  ///
  /// Concurrent calls share one operation and one utterance. During startup
  /// it cancels the generation. A no-op before start or after stop.
  Future<FinalizationOutcome> finalize() {
    final generation = _current;
    if (generation == null || generation.ended) {
      return Future.value(const FinalizationOutcome(timedOut: false));
    }
    return generation.finalizeTerminal();
  }

  /// Cancels the current generation without delivering an utterance.
  ///
  /// Safe before, during, and after startup. Repeated calls share one cleanup
  /// bounded by [CaptureTimeouts.shutdown].
  Future<void> stop() {
    final generation = _current;
    if (generation == null) return Future.value();
    return generation.end(CaptureState.stopped);
  }

  Future<void> _bounded(Future<void> future, Duration deadline) {
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final timer = _scheduler.schedule(deadline, finish);
    future.whenComplete(() {
      timer.cancel();
      finish();
    }).ignore();
    return completer.future;
  }
}

sealed class _LaneItem {
  const _LaneItem();
}

final class _FrameItem extends _LaneItem {
  const _FrameItem(this.frame, this.bytes);

  final AudioFrame frame;
  final int bytes;
}

final class _ControlItem extends _LaneItem {
  _ControlItem(this.run);

  final Future<void> Function() run;
  final Completer<void> done = Completer<void>();
}

final class _Generation {
  _Generation(
    this._owner, {
    required this.sessionId,
    required this.source,
    required this.mode,
    required this.requestedFormat,
  });

  final VoiceCaptureCoordinator _owner;
  final String sessionId;
  final VoiceSource source;
  final CaptureMode mode;
  final AudioFormat? requestedFormat;

  CaptureState state = CaptureState.idle;
  VoiceError? error;
  double amplitude = 0;
  String partialText = '';
  final List<String> _finals = [];
  bool captureLive = false;
  bool finalizePending = false;
  bool ended = false;

  bool _gateOpen = true;
  BigInt _sequence = BigInt.zero;
  VoiceSession? _session;
  ProviderSession? _providerSession;
  StreamSubscription<SessionState>? _sessionStates;
  StreamSubscription<AudioFrame>? _frames;
  StreamSubscription<ProviderEvent>? _providerEvents;
  Timer? _startupTimer;
  Timer? _endpointTimer;
  Timer? _finalizeTimer;
  Timer? _warmHoldTimer;
  Completer<void>? _startCompleter;
  Completer<FinalizationOutcome>? _finalizeCompleter;
  Future<void>? _cleanupBounded;
  final Queue<_LaneItem> _lane = Queue<_LaneItem>();
  int _laneFrames = 0;
  int _laneBytes = 0;
  bool _pumping = false;

  CaptureTimeouts get _timeouts => _owner.timeouts;
  Scheduler get _scheduler => _owner._scheduler;
  Set<ProviderCapability> get _capabilities => _owner._provider.capabilities;

  /// The bounded cleanup of an ended generation.
  Future<void> get cleanupBounded => _cleanupBounded ?? Future.value();

  CaptureSnapshot get snapshot => CaptureSnapshot(
    state: state,
    mode: mode,
    sessionId: sessionId,
    amplitude: amplitude,
    partialText: partialText,
    bufferedFinalText: _finals.join(' '),
    captureLive: captureLive,
    finalizePending: finalizePending,
    error: error,
  );

  // Startup ---------------------------------------------------------------

  Future<void> begin(Future<void> previousCleanup) {
    final completer = Completer<void>();
    _startCompleter = completer;
    _transition(CaptureState.starting);
    _startupTimer = _scheduler.schedule(_timeouts.startup, () {
      _fail(
        VoiceError(
          code: 'startup_timeout',
          message: 'The source or provider did not start in time.',
          retryable: true,
        ),
      );
    });
    unawaited(_acquire(previousCleanup));
    return completer.future;
  }

  Future<void> _acquire(Future<void> previousCleanup) async {
    try {
      await previousCleanup;
      if (ended) return;
      final session = await _owner._connector.connect(source);
      if (ended) {
        session.close().ignore();
        return;
      }
      _session = session;
      _sessionStates = session.stateChanges.listen(_onSessionState);
      _frames = session.frames.listen(_onFrame);
      await session.start(requestedFormat: requestedFormat);
      if (ended) return;
      final format = session.format;
      if (format == null) {
        throw VoiceError(
          code: 'format_unavailable',
          message: 'The session started without a negotiated format.',
          retryable: false,
        );
      }
      final providerSession = await _owner._provider.start(format);
      if (ended) {
        providerSession.stop().ignore();
        return;
      }
      _providerSession = providerSession;
      _providerEvents = providerSession.events.listen(_onProviderEvent);
      _startupTimer?.cancel();
      _transition(CaptureState.listening);
      _startCompleter?.complete();
      _startCompleter = null;
      _pump();
    } on Object catch (cause) {
      if (ended) return;
      _fail(
        cause is VoiceError
            ? cause
            : VoiceError(
                code: 'startup_failed',
                message: cause.toString(),
                retryable: false,
              ),
      );
    }
  }

  // Input -----------------------------------------------------------------

  void _onFrame(AudioFrame frame) {
    if (ended || !_gateOpen) return;
    if (!captureLive &&
        !_capabilities.contains(ProviderCapability.realAudioReadiness) &&
        _owner.readinessPolicy.isMeaningful(frame)) {
      _setCaptureLive(true);
    }
    final bytes = _payloadBytes(frame.payloadBase64);
    _lane.addLast(_FrameItem(frame, bytes));
    _laneFrames++;
    _laneBytes += bytes;
    final bound = _owner.preRoll;
    while (_laneFrames > 0 &&
        (_laneFrames > bound.maxFrames || _laneBytes > bound.maxBytes)) {
      final oldest = _lane.whereType<_FrameItem>().first;
      _lane.remove(oldest);
      _laneFrames--;
      _laneBytes -= oldest.bytes;
    }
    _pump();
  }

  Future<void> _enqueueControl(Future<void> Function() run) {
    final item = _ControlItem(run);
    _lane.addLast(item);
    _pump();
    return item.done.future;
  }

  void _pump() {
    if (_pumping || ended || _providerSession == null) return;
    _pumping = true;
    unawaited(_runLane());
  }

  Future<void> _runLane() async {
    try {
      while (!ended && _lane.isNotEmpty) {
        final item = _lane.removeFirst();
        switch (item) {
          case _FrameItem(:final frame, :final bytes):
            _laneFrames--;
            _laneBytes -= bytes;
            try {
              await _providerSession!.addFrame(frame);
            } on Object catch (cause) {
              _fail(
                VoiceError(
                  code: 'provider_frame_rejected',
                  message: cause.toString(),
                  retryable: true,
                ),
              );
              return;
            }
          case _ControlItem(:final run, :final done):
            try {
              await run();
            } on Object catch (_) {
              // A provider that fails a control call also reports the failure
              // on its event stream; the bounded wait still completes.
            }
            done.complete();
        }
      }
    } finally {
      _pumping = false;
    }
  }

  // Provider and session events -------------------------------------------

  void _onProviderEvent(ProviderEvent event) {
    if (ended) return;
    switch (event) {
      case ProviderPartial(:final text):
        partialText = text;
        _endpointTimer?.cancel();
        _emitTranscript('TRANSCRIPT_KIND_PARTIAL', text);
      case ProviderFinal(:final text):
        partialText = '';
        if (text.isNotEmpty && (_gateOpen || finalizePending)) {
          _finals.add(text);
        }
        _emitTranscript('TRANSCRIPT_KIND_FINAL', text);
        if (mode == CaptureMode.handsFree && state == CaptureState.listening) {
          _endpointTimer?.cancel();
          _endpointTimer = _scheduler.schedule(_timeouts.endpoint, () {
            if (state == CaptureState.listening) finalizeTerminal().ignore();
          });
        }
      case ProviderRejected(:final text):
        partialText = '';
        _emitTranscript('TRANSCRIPT_KIND_REJECTED', text);
      case ProviderReadiness(:final live):
        if (_capabilities.contains(ProviderCapability.realAudioReadiness) &&
            live != captureLive) {
          _setCaptureLive(live);
        }
      case ProviderAmplitude(:final value):
        amplitude = value;
        _emit(RuntimePayloadKind.audioLevel, {'amplitude': value});
      case ProviderFailure(:final error):
        _fail(error);
      case ProviderClosed(:final expected):
        if (expected) return;
        if (state == CaptureState.finalizing) {
          _completeFinalization(timedOut: false);
        } else {
          _fail(
            VoiceError(
              code: 'provider_closed',
              message: 'The provider closed before capture ended.',
              retryable: true,
            ),
          );
        }
    }
  }

  void _onSessionState(SessionState sessionState) {
    if (ended) return;
    switch (sessionState) {
      case SessionState.error:
        _fail(
          _session?.error ??
              VoiceError(
                code: 'source_failed',
                message: 'The source failed without a cause.',
                retryable: true,
              ),
        );
      case SessionState.stopped:
        if (state == CaptureState.listening ||
            state == CaptureState.warmMuted) {
          finalizeTerminal().ignore();
        }
      case SessionState.idle:
      case SessionState.starting:
      case SessionState.listening:
      case SessionState.finalizing:
        break;
    }
  }

  // Release, finalize, stop ----------------------------------------------

  Future<void> release() {
    switch (state) {
      case CaptureState.starting:
        return end(CaptureState.stopped);
      case CaptureState.listening:
        if (mode == CaptureMode.holdToTalk &&
            _capabilities.contains(ProviderCapability.warmGate)) {
          return _parkWarm();
        }
        return finalizeTerminal().then((_) {});
      case CaptureState.idle:
      case CaptureState.warmMuted:
      case CaptureState.finalizing:
      case CaptureState.stopped:
      case CaptureState.error:
        return Future.value();
    }
  }

  Future<void> _parkWarm() {
    _gateOpen = false;
    partialText = '';
    finalizePending = true;
    _transition(CaptureState.warmMuted);
    final deadline = _scheduler.schedule(_timeouts.finalize, () {
      _completeWarmFlush();
    });
    return _enqueueControl(
      () =>
          _providerSession!.setInputGate(open: false, flushAcceptedAudio: true),
    ).then((_) {
      deadline.cancel();
      _completeWarmFlush();
    });
  }

  void _completeWarmFlush() {
    if (ended || state == CaptureState.finalizing || !finalizePending) return;
    finalizePending = false;
    final text = _takeUtterance();
    if (state == CaptureState.warmMuted) {
      _warmHoldTimer = _scheduler.schedule(_timeouts.warmHold, () {
        end(CaptureState.stopped);
      });
    }
    _deliver(text);
  }

  Future<void> resume() {
    _warmHoldTimer?.cancel();
    _gateOpen = true;
    partialText = '';
    _transition(CaptureState.listening);
    return _enqueueControl(
      () =>
          _providerSession!.setInputGate(open: true, flushAcceptedAudio: false),
    );
  }

  Future<FinalizationOutcome> finalizeTerminal() {
    final existing = _finalizeCompleter;
    if (existing != null) return existing.future;
    if (state == CaptureState.starting) {
      end(CaptureState.stopped);
      return Future.value(const FinalizationOutcome(timedOut: false));
    }
    final completer = Completer<FinalizationOutcome>();
    _finalizeCompleter = completer;
    _warmHoldTimer?.cancel();
    _endpointTimer?.cancel();
    _gateOpen = false;
    partialText = '';
    finalizePending = true;
    _transition(CaptureState.finalizing);
    _finalizeTimer = _scheduler.schedule(_timeouts.finalize, () {
      _completeFinalization(timedOut: true);
    });
    final graceful = _capabilities.contains(
      ProviderCapability.gracefulFinalize,
    );
    _enqueueControl(() async {
      final provider = _providerSession!;
      if (graceful) {
        await provider.finalize();
      } else {
        await provider.stop();
      }
    }).then((_) => _completeFinalization(timedOut: false)).ignore();
    return completer.future;
  }

  void _completeFinalization({required bool timedOut}) {
    if (ended || state != CaptureState.finalizing) return;
    _finalizeTimer?.cancel();
    finalizePending = false;
    final text = _takeUtterance();
    _finalizeCompleter?.complete(FinalizationOutcome(timedOut: timedOut));
    end(CaptureState.stopped);
    _deliver(text);
  }

  /// Ends this generation synchronously and returns its bounded cleanup.
  Future<void> end(CaptureState terminal) {
    if (ended) return cleanupBounded;
    ended = true;
    _startupTimer?.cancel();
    _endpointTimer?.cancel();
    _finalizeTimer?.cancel();
    _warmHoldTimer?.cancel();
    _gateOpen = false;
    partialText = '';
    finalizePending = false;
    _transition(terminal);
    final start = _startCompleter;
    _startCompleter = null;
    if (start != null && !start.isCompleted) {
      start.completeError(
        error ??
            VoiceError(
              code: 'cancelled',
              message: 'Capture start was cancelled.',
              retryable: true,
            ),
      );
    }
    final finalize = _finalizeCompleter;
    if (finalize != null && !finalize.isCompleted) {
      finalize.complete(const FinalizationOutcome(timedOut: false));
    }
    for (final item in _lane) {
      if (item is _ControlItem) item.done.complete();
    }
    _lane.clear();
    _laneFrames = 0;
    _laneBytes = 0;
    final bounded = _owner._bounded(_cleanup(), _timeouts.shutdown);
    _cleanupBounded = bounded;
    return bounded;
  }

  Future<void> _cleanup() async {
    await _sessionStates?.cancel();
    await _frames?.cancel();
    await _providerEvents?.cancel();
    final session = _session;
    final provider = _providerSession;
    await Future.wait([
      if (session != null) session.stop().catchError((_) {}),
      if (provider != null) provider.stop().catchError((_) {}),
    ]);
  }

  void _fail(VoiceError failure) {
    if (ended) return;
    error = failure;
    _emit(RuntimePayloadKind.error, {
      'code': failure.code,
      'message': failure.message,
      'retryable': failure.retryable,
      if (failure.metadata.isNotEmpty) 'metadata': failure.metadata,
    });
    end(CaptureState.error);
  }

  // Utterance and publishing ------------------------------------------------

  String _takeUtterance() {
    final text = _finals.join(' ');
    _finals.clear();
    partialText = '';
    return text;
  }

  void _deliver(String text) {
    if (text.isEmpty) return;
    _owner.onUtteranceFinalized?.call(text);
  }

  void _setCaptureLive(bool live) {
    captureLive = live;
    _emit(RuntimePayloadKind.captureReadiness, {'live': live});
  }

  void _transition(CaptureState next) {
    final previous = state;
    state = next;
    _emit(RuntimePayloadKind.sessionStateChanged, {
      'previous': previous.protoJsonName,
      'current': next.protoJsonName,
    });
    _owner._states.add(next);
  }

  void _emitTranscript(String kind, String text) {
    _emit(RuntimePayloadKind.transcript, {'kind': kind, 'text': text});
  }

  void _emit(RuntimePayloadKind kind, Map<String, Object?> payload) {
    _sequence += BigInt.one;
    _owner._events.add(
      RuntimeEvent(
        protocol: ProtocolVersion.current,
        sessionId: sessionId,
        sequence: _sequence,
        monotonicTimeUs: BigInt.from(_scheduler.monotonicTimeUs),
        kind: kind,
        payload: payload,
      ),
    );
  }
}

int _payloadBytes(String base64Text) {
  var padding = 0;
  if (base64Text.endsWith('==')) {
    padding = 2;
  } else if (base64Text.endsWith('=')) {
    padding = 1;
  }
  return (base64Text.length * 3) ~/ 4 - padding;
}
