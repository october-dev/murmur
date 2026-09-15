import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:murmur_protocol/murmur_protocol.dart';

/// The synthetic frame format shared by the fakes and the scenario fixtures.
final fakeFormat = AudioFormat(
  sampleRateHz: 16000,
  channels: 1,
  encoding: AudioEncoding.pcmS16le,
  frameDurationMs: 10,
);

/// One 10 ms frame of a 1 kHz sine wave, as documented in conformance/README.
final String sinePayload = () {
  final bytes = ByteData(320);
  for (var n = 0; n < 160; n++) {
    final sample = (8000 * sin(2 * pi * 1000 * n / 16000)).round();
    bytes.setInt16(n * 2, sample, Endian.little);
  }
  return base64Encode(bytes.buffer.asUint8List());
}();

/// One 10 ms frame of digital silence.
final String silencePayload = base64Encode(Uint8List(320));

VoiceSource fakeSource([String id = 'source-1']) => VoiceSource(
  id: id,
  displayName: 'Synthetic microphone',
  transport: VoiceSourceTransport.synthetic,
  capabilities: {VoiceSourceCapability.liveAudio},
);

/// A scriptable connector whose connects stay pending until the test decides.
final class FakeConnector implements VoiceConnector {
  FakeConnector({this.autoConnect = false});

  /// Completes every connect immediately with a new session.
  final bool autoConnect;
  final Queue<Completer<VoiceSession>> _pending = Queue();
  final List<FakeSession> sessions = [];
  int connectCalls = 0;

  FakeSession get latestSession => sessions.last;
  int get pendingConnects => _pending.length;

  @override
  Stream<VoiceSource> discoverSources() => const Stream.empty();

  @override
  Future<VoiceSession> connect(VoiceSource source) {
    connectCalls++;
    if (autoConnect) return Future.value(_newSession(source));
    final completer = Completer<VoiceSession>();
    _pending.addLast(completer);
    return completer.future;
  }

  /// Completes the oldest pending connect with a new idle session.
  FakeSession completeConnect([VoiceSource? source]) {
    final session = _newSession(source ?? fakeSource());
    _takePending().complete(session);
    return session;
  }

  /// Fails the oldest pending connect.
  void failConnect(VoiceError error) => _takePending().completeError(error);

  Completer<VoiceSession> _takePending() {
    if (_pending.isEmpty) throw StateError('no pending connect');
    return _pending.removeFirst();
  }

  FakeSession _newSession(VoiceSource source) {
    final session = FakeSession(
      source: source,
      sessionId: 'connector-${sessions.length + 1}',
    );
    sessions.add(session);
    return session;
  }
}

/// A minimal [VoiceSession] that emits frames and terminal states on demand.
final class FakeSession implements VoiceSession {
  FakeSession({required this.source, required this.sessionId});

  @override
  final VoiceSource source;

  @override
  final String sessionId;

  final StreamController<SessionState> _states =
      StreamController<SessionState>.broadcast(sync: true);
  final StreamController<AudioFrame> _frames = StreamController<AudioFrame>(
    sync: true,
  );
  SessionState _state = SessionState.idle;
  AudioFormat? _format;
  VoiceError? _error;
  int stopCalls = 0;

  @override
  AudioFormat? get format => _format;

  @override
  SessionState get state => _state;

  @override
  Stream<SessionState> get stateChanges => _states.stream;

  @override
  VoiceError? get error => _error;

  @override
  Stream<AudioFrame> get frames => _frames.stream;

  @override
  Future<void> start({AudioFormat? requestedFormat}) async {
    if (_state != SessionState.idle) {
      throw StateError('capture can only start from an idle session');
    }
    _transition(SessionState.starting);
    await Future<void>.value();
    if (_state != SessionState.starting) {
      throw VoiceError(
        code: 'cancelled',
        message: 'Session start was cancelled.',
        retryable: true,
      );
    }
    _format = requestedFormat ?? fakeFormat;
    _transition(SessionState.listening);
  }

  @override
  Future<void> stop({String? reason}) async {
    stopCalls++;
    _terminate(SessionState.stopped);
  }

  @override
  Future<void> close() => stop();

  /// Emits one frame; returns `false` when the session is not listening.
  bool emitFrame(int sequence, {bool silent = false}) {
    if (_state != SessionState.listening) return false;
    _frames.add(
      AudioFrame(
        protocol: ProtocolVersion.current,
        sessionId: sessionId,
        sequence: BigInt.from(sequence),
        monotonicTimeUs: BigInt.from(sequence * 10000),
        format: _format ?? fakeFormat,
        payloadBase64: silent ? silencePayload : sinePayload,
      ),
    );
    return true;
  }

  /// Ends the session as the source would on its own, for example at EOF.
  void endFromSource() => _terminate(SessionState.stopped);

  /// Fails the session with [failure].
  void fail(VoiceError failure) {
    _error = failure;
    _terminate(SessionState.error);
  }

  void _terminate(SessionState terminal) {
    if (_state == SessionState.stopped || _state == SessionState.error) return;
    _transition(terminal);
    unawaited(_frames.close());
    unawaited(_states.close());
  }

  void _transition(SessionState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}
