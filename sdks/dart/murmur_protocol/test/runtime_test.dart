import 'dart:async';
import 'dart:collection';

import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('typed wire models', () {
    test('constructs and serializes an audio format', () {
      final format = AudioFormat(
        sampleRateHz: 48000,
        channels: 2,
        encoding: AudioEncoding.pcmF32le,
        frameDurationMs: 0,
      );

      expect(format.toJson(), {
        'sampleRateHz': 48000,
        'channels': 2,
        'encoding': 'AUDIO_ENCODING_PCM_F32LE',
        'frameDurationMs': 0,
      });
      expect(
        AudioFormat(
          sampleRateHz: 16000,
          channels: 1,
          encoding: AudioEncoding.opus,
        ).toJson(),
        isNot(contains('frameDurationMs')),
      );
    });

    test('validates audio format construction and parsing', () {
      const uint32Max = 0xffffffff;
      expect(
        AudioFormat(
          sampleRateHz: uint32Max,
          channels: uint32Max,
          encoding: AudioEncoding.pcmS16le,
          frameDurationMs: uint32Max,
        ).toJson(),
        containsPair('frameDurationMs', uint32Max),
      );

      for (final constructor in <AudioFormat Function()>[
        () => AudioFormat(
          sampleRateHz: 0,
          channels: 1,
          encoding: AudioEncoding.pcmS16le,
        ),
        () => AudioFormat(
          sampleRateHz: uint32Max + 1,
          channels: 1,
          encoding: AudioEncoding.pcmS16le,
        ),
        () => AudioFormat(
          sampleRateHz: 16000,
          channels: 0,
          encoding: AudioEncoding.pcmS16le,
        ),
        () => AudioFormat(
          sampleRateHz: 16000,
          channels: uint32Max + 1,
          encoding: AudioEncoding.pcmS16le,
        ),
        () => AudioFormat(
          sampleRateHz: 16000,
          channels: 1,
          encoding: AudioEncoding.pcmS16le,
          frameDurationMs: -1,
        ),
        () => AudioFormat(
          sampleRateHz: 16000,
          channels: 1,
          encoding: AudioEncoding.pcmS16le,
          frameDurationMs: uint32Max + 1,
        ),
      ]) {
        expect(constructor, throwsFormatException);
      }

      expect(
        () => AudioFormat.fromJson({
          'sampleRateHz': 16000,
          'channels': 1,
          'encoding': 'AUDIO_ENCODING_UNSPECIFIED',
        }),
        throwsFormatException,
      );
    });

    test('constructs each typed session command', () {
      final source = _source();
      final format = _format();
      final controls = [
        SessionControl(
          protocol: ProtocolVersion.current,
          sessionId: 'session-1',
          requestSequence: BigInt.one,
          command: StartSession(
            source: source,
            mode: CaptureMode.holdToTalk,
            requestedFormat: format,
          ),
        ),
        SessionControl(
          protocol: ProtocolVersion.current,
          sessionId: 'session-1',
          requestSequence: BigInt.two,
          command: const StopSession(reason: 'done'),
        ),
        SessionControl(
          protocol: ProtocolVersion.current,
          sessionId: 'session-1',
          requestSequence: BigInt.from(3),
          command: const SetInputGate(open: false, flushAcceptedAudio: false),
        ),
        SessionControl(
          protocol: ProtocolVersion.current,
          sessionId: 'session-1',
          requestSequence: BigInt.from(4),
          command: const FinalizeSession(),
        ),
      ];

      expect(controls[0].toJson()['start'], {
        'source': source.toJson(),
        'mode': 'CAPTURE_MODE_HOLD_TO_TALK',
        'requestedFormat': format.toJson(),
      });
      expect(controls[1].toJson()['stop'], {'reason': 'done'});
      expect(controls[2].toJson()['inputGate'], {
        'open': false,
        'flushAcceptedAudio': false,
      });
      expect(controls[3].toJson()['finalize'], isEmpty);
    });

    test('preserves present default-valued command fields', () {
      for (final entry in <String, Map<String, Object?>>{
        'inputGate': {'open': false},
        'emptyInputGate': <String, Object?>{},
        'stop': <String, Object?>{},
        'start': <String, Object?>{},
      }.entries) {
        final field = entry.key == 'emptyInputGate' ? 'inputGate' : entry.key;
        final json = _controlJson(field, entry.value);
        expect(SessionControl.fromJson(json).toJson(), json);
      }

      final explicitUnspecified = _controlJson('start', {
        'mode': 'CAPTURE_MODE_UNSPECIFIED',
      });
      expect(
        SessionControl.fromJson(explicitUnspecified).toJson(),
        explicitUnspecified,
      );
    });

    test('rejects invalid typed command fields', () {
      for (final json in [
        _controlJson('inputGate', {'open': 0}),
        _controlJson('stop', {'reason': false}),
        _controlJson('start', {'mode': 'CAPTURE_MODE_UNKNOWN'}),
        _controlJson('start', {'requestedFormat': <String, Object?>{}}),
      ]) {
        expect(() => SessionControl.fromJson(json), throwsFormatException);
      }
    });

    test('keeps audio payload text verbatim with a typed format', () {
      final json = <String, Object?>{
        'protocol': {'major': 1, 'minor': 0},
        'sessionId': 'session-1',
        'sequence': '1',
        'monotonicTimeUs': '25',
        'format': {
          'sampleRateHz': 16000,
          'channels': 1,
          'encoding': 'AUDIO_ENCODING_PCM_S16LE',
        },
        'payload': '__8',
      };

      final frame = AudioFrame.fromJson(json);
      expect(frame.format, isA<AudioFormat>());
      expect(frame.payloadBase64, '__8');
      expect(frame.toJson(), json);
    });
  });

  group('runtime interfaces', () {
    test('discovers until cancellation and connects an idle session', () async {
      final connector = _FakeConnector();
      final discovered = Completer<VoiceSource>();
      final subscription = connector.discoverSources().listen(
        discovered.complete,
      );

      expect(await discovered.future, same(connector.source));
      await subscription.cancel();
      expect(connector.scanStops, 1);

      final session = await connector.connect(connector.source) as _FakeSession;
      expect(session.state, SessionState.idle);
      expect(session.format, isNull);
      expect(session.error, isNull);

      final received = <AudioFrame>[];
      final framesSubscription = session.frames.listen(received.add);
      expect(session.emitFrame(1), isFalse);
      expect(received, isEmpty);

      await session.start();
      expect(session.state, SessionState.listening);
      expect(session.format, same(_defaultFormat));
      expect(session.emitFrame(2), isTrue);
      expect(received.single.sequence, BigInt.two);

      await session.close();
      await framesSubscription.cancel();
    });

    test('connect failure releases partial acquisition', () async {
      final connector = _FakeConnector(failConnect: true);

      await expectLater(
        connector.connect(connector.source),
        throwsA(
          isA<VoiceError>()
              .having((error) => error.code, 'code', 'connect_failed')
              .having((error) => error.retryable, 'retryable', true),
        ),
      );
      expect(connector.partialAcquisitions, 1);
      expect(connector.partialReleases, 1);
    });

    test('stop is terminal and keeps snapshots readable', () async {
      final session = _FakeSession(source: _source(), sessionId: 'session-1');
      final states = <SessionState>[];
      final stateSubscription = session.stateChanges.listen(states.add);
      final framesDone = session.frames.drain<void>();

      await session.start(requestedFormat: _format());
      await session.stop(reason: 'test complete');

      expect(states, [
        SessionState.starting,
        SessionState.listening,
        SessionState.stopped,
      ]);
      expect(session.state, SessionState.stopped);
      expect(session.source.id, 'source-1');
      expect(session.sessionId, 'session-1');
      expect(session.format?.frameDurationMs, 10);
      expect(session.error, isNull);
      await framesDone;
      expect(() => session.start(), throwsStateError);
      await stateSubscription.cancel();
    });

    test(
      'state changes have no replay and support subscribe-then-read',
      () async {
        final session = _FakeSession(source: _source(), sessionId: 'session-1');
        await session.start();

        final states = <SessionState>[];
        final subscription = session.stateChanges.listen(states.add);
        final snapshot = session.state;
        expect(snapshot, SessionState.listening);
        expect(states, isEmpty);

        await session.close();
        expect(states, [SessionState.stopped]);
        await subscription.cancel();
      },
    );

    for (final terminator in ['close', 'stop']) {
      test(
        '$terminator wins against a pending start without resurrection',
        () async {
          final acquisitionGate = Completer<_FakeAcquisition>();
          final session = _FakeSession(
            source: _source(),
            sessionId: 'session-race',
            acquisitionGate: acquisitionGate,
          );
          final states = <SessionState>[];
          final stateSubscription = session.stateChanges.listen(states.add);
          final startFuture = session.start();
          final cancelled = expectLater(
            startFuture,
            throwsA(
              isA<VoiceError>().having(
                (error) => error.code,
                'code',
                'cancelled',
              ),
            ),
          );

          final cleanup = terminator == 'close'
              ? session.close()
              : session.stop(reason: 'cancel startup');
          await cleanup;
          await cancelled;
          expect(session.state, SessionState.stopped);
          expect(session.cleanupRuns, 1);

          final lateAcquisition = _FakeAcquisition();
          acquisitionGate.complete(lateAcquisition);
          await lateAcquisition.released;

          expect(lateAcquisition.releaseCalls, 1);
          expect(session.state, SessionState.stopped);
          expect(session.format, isNull);
          expect(session.emitFrame(1), isFalse);
          expect(states, [SessionState.starting, SessionState.stopped]);
          await stateSubscription.cancel();
        },
      );
    }

    test('concurrent stop and close share one pending cleanup', () async {
      final releaseGate = Completer<void>();
      final acquisition = _FakeAcquisition(releaseGate: releaseGate);
      final session = _FakeSession(
        source: _source(),
        sessionId: 'session-1',
        acquisitionGate: Completer<_FakeAcquisition>()..complete(acquisition),
      );
      await session.start();

      final first = session.close();
      final second = session.stop();
      final third = session.close();
      expect(identical(first, second), isTrue);
      expect(identical(second, third), isTrue);

      var completed = false;
      unawaited(first.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(session.cleanupRuns, 1);
      expect(acquisition.releaseCalls, 1);

      releaseGate.complete();
      await Future.wait([first, second, third]);
      expect(completed, isTrue);
      expect(acquisition.releaseCalls, 1);
    });

    test('device failure publishes its cause before terminal state', () async {
      final acquisition = _FakeAcquisition();
      final session = _FakeSession(
        source: _source(),
        sessionId: 'session-1',
        acquisitionGate: Completer<_FakeAcquisition>()..complete(acquisition),
      );
      final failure = VoiceError(
        code: 'device_lost',
        message: 'The source disconnected.',
        retryable: true,
        metadata: {'transport': 'synthetic'},
      );
      final observedErrors = <VoiceError?>[];
      final stateSubscription = session.stateChanges.listen((state) {
        if (state == SessionState.error) observedErrors.add(session.error);
      });
      final framesDone = session.frames.drain<void>();
      await session.start();

      await session.failDevice(failure);

      expect(session.state, SessionState.error);
      expect(session.error, same(failure));
      expect(observedErrors, [same(failure)]);
      expect(acquisition.releaseCalls, 1);
      await framesDone;
      expect(() => session.start(), throwsStateError);
      await stateSubscription.cancel();
    });

    test('cleanup does not wait for never-listened streams', () async {
      final session = _FakeSession(source: _source(), sessionId: 'session-1');

      await session.close().timeout(const Duration(seconds: 1));

      expect(session.state, SessionState.stopped);
      expect(session.cleanupRuns, 1);
    });

    test('cleanup does not wait for paused stream consumers', () async {
      final session = _FakeSession(source: _source(), sessionId: 'session-1');
      final frameSubscription = session.frames.listen((_) {});
      final stateSubscription = session.stateChanges.listen((_) {});
      frameSubscription.pause();
      stateSubscription.pause();

      await session.close().timeout(const Duration(seconds: 1));

      expect(session.state, SessionState.stopped);
      await frameSubscription.cancel();
      await stateSubscription.cancel();
    });

    test(
      'paused frame delivery is bounded and drops the oldest frame',
      () async {
        final session = _FakeSession(source: _source(), sessionId: 'session-1');
        final received = <BigInt>[];
        final subscription = session.frames.listen(
          (frame) => received.add(frame.sequence),
        );
        await session.start();

        expect(session.emitFrame(1), isTrue);
        subscription.pause();
        expect(session.emitFrame(2), isTrue);
        expect(session.emitFrame(3), isTrue);
        expect(session.emitFrame(4), isTrue);
        expect(session.bufferedFrames, 2);
        expect(session.droppedFrames, 1);

        subscription.resume();
        await Future<void>.delayed(Duration.zero);
        expect(received, [BigInt.one, BigInt.from(3), BigInt.from(4)]);
        expect(session.bufferedFrames, 0);

        await session.close();
        expect(session.emitFrame(5), isFalse);
        await subscription.cancel();
      },
    );
  });
}

final _defaultFormat = AudioFormat(
  sampleRateHz: 16000,
  channels: 1,
  encoding: AudioEncoding.pcmS16le,
);

AudioFormat _format() => AudioFormat(
  sampleRateHz: 16000,
  channels: 1,
  encoding: AudioEncoding.pcmS16le,
  frameDurationMs: 10,
);

VoiceSource _source() => VoiceSource(
  id: 'source-1',
  displayName: 'Synthetic microphone',
  transport: VoiceSourceTransport.synthetic,
  capabilities: {VoiceSourceCapability.liveAudio},
);

Map<String, Object?> _controlJson(
  String commandField,
  Map<String, Object?> body,
) => {
  'protocol': {'major': 1, 'minor': 0},
  'sessionId': 'session-1',
  'requestSequence': '1',
  commandField: body,
};

final class _FakeConnector implements VoiceConnector {
  _FakeConnector({this.failConnect = false}) : source = _source();

  final bool failConnect;
  final VoiceSource source;
  int scanStops = 0;
  int partialAcquisitions = 0;
  int partialReleases = 0;
  int _nextSession = 0;

  @override
  Stream<VoiceSource> discoverSources() {
    late final StreamController<VoiceSource> controller;
    controller = StreamController<VoiceSource>(
      sync: true,
      onListen: () {
        scheduleMicrotask(() {
          if (!controller.isClosed && controller.hasListener) {
            controller.add(source);
          }
        });
      },
      onCancel: () {
        scanStops++;
      },
    );
    return controller.stream;
  }

  @override
  Future<VoiceSession> connect(VoiceSource source) async {
    if (failConnect) {
      partialAcquisitions++;
      try {
        throw VoiceError(
          code: 'connect_failed',
          message: 'The synthetic source did not connect.',
          retryable: true,
        );
      } finally {
        partialReleases++;
      }
    }
    return _FakeSession(
      source: source,
      sessionId: 'fake-session-${++_nextSession}',
    );
  }
}

final class _FakeSession implements VoiceSession {
  _FakeSession({
    required this.source,
    required this.sessionId,
    Completer<_FakeAcquisition>? acquisitionGate,
    Completer<void>? cleanupGate,
  }) : _acquisitionGate = acquisitionGate,
       _cleanupGate = cleanupGate {
    _frameController = StreamController<AudioFrame>(
      sync: true,
      onListen: () {
        _frameConsumerReady = true;
        _flushFrames();
      },
      onPause: () {
        _frameConsumerReady = false;
      },
      onResume: () {
        _frameConsumerReady = true;
        _flushFrames();
      },
      onCancel: () {
        _frameConsumerReady = false;
        _pendingFrames.clear();
      },
    );
  }

  // This fake buffers at most two undelivered frames and drops the oldest.
  static const _frameCapacity = 2;

  @override
  final VoiceSource source;

  @override
  final String sessionId;

  final Completer<_FakeAcquisition>? _acquisitionGate;
  final Completer<void>? _cleanupGate;
  final Queue<AudioFrame> _pendingFrames = Queue<AudioFrame>();
  final StreamController<SessionState> _stateController =
      StreamController<SessionState>.broadcast(sync: true);
  late final StreamController<AudioFrame> _frameController;

  SessionState _state = SessionState.idle;
  AudioFormat? _format;
  VoiceError? _error;
  _FakeAcquisition? _activeAcquisition;
  Completer<void>? _pendingStart;
  Future<void>? _cleanupFuture;
  var _generation = 0;
  var _terminal = false;
  var _frameConsumerReady = false;
  var _frameControllerClosed = false;
  var cleanupRuns = 0;
  var droppedFrames = 0;

  int get bufferedFrames => _pendingFrames.length;

  @override
  AudioFormat? get format => _format;

  @override
  SessionState get state => _state;

  @override
  Stream<SessionState> get stateChanges => _stateController.stream;

  @override
  VoiceError? get error => _error;

  @override
  Stream<AudioFrame> get frames => _frameController.stream;

  @override
  Future<void> start({AudioFormat? requestedFormat}) {
    if (_state != SessionState.idle || _terminal) {
      throw StateError('capture can only start from an idle session');
    }
    final operation = Completer<void>();
    _pendingStart = operation;
    final generation = ++_generation;
    _transition(SessionState.starting);
    unawaited(_finishStart(generation, operation, requestedFormat));
    return operation.future;
  }

  Future<void> _finishStart(
    int generation,
    Completer<void> operation,
    AudioFormat? requestedFormat,
  ) async {
    try {
      final gate = _acquisitionGate;
      final acquisition = gate == null ? _FakeAcquisition() : await gate.future;
      if (_terminal || generation != _generation) {
        await acquisition.release();
        return;
      }
      _activeAcquisition = acquisition;
      _format = requestedFormat ?? _defaultFormat;
      _pendingStart = null;
      _transition(SessionState.listening);
      operation.complete();
    } on Object catch (cause, stackTrace) {
      if (_terminal || generation != _generation) return;
      final failure = cause is VoiceError
          ? cause
          : VoiceError(
              code: 'start_failed',
              message: cause.toString(),
              retryable: false,
            );
      unawaited(
        _terminate(
          terminalState: SessionState.error,
          startFailure: failure,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> stop({String? reason}) {
    return _terminate(
      terminalState: SessionState.stopped,
      startFailure: VoiceError(
        code: 'cancelled',
        message: 'Session start was cancelled.',
        retryable: true,
      ),
    );
  }

  @override
  Future<void> close() => stop();

  Future<void> failDevice(VoiceError failure) {
    return _terminate(terminalState: SessionState.error, startFailure: failure);
  }

  Future<void> _terminate({
    required SessionState terminalState,
    required VoiceError startFailure,
    StackTrace? stackTrace,
  }) {
    final existing = _cleanupFuture;
    if (existing != null) return existing;

    final cleanup = Completer<void>();
    final future = cleanup.future;
    _cleanupFuture = future;
    _terminal = true;
    _generation++;

    final pendingStart = _pendingStart;
    _pendingStart = null;
    if (pendingStart != null && !pendingStart.isCompleted) {
      pendingStart.completeError(startFailure, stackTrace);
    }
    if (terminalState == SessionState.error) {
      _error = startFailure;
    }
    _transition(terminalState);

    _pendingFrames.clear();
    _frameControllerClosed = true;
    unawaited(_frameController.close());
    unawaited(_stateController.close());
    unawaited(_finishCleanup(cleanup));
    return future;
  }

  Future<void> _finishCleanup(Completer<void> cleanup) async {
    cleanupRuns++;
    try {
      final acquisition = _activeAcquisition;
      _activeAcquisition = null;
      if (acquisition != null) {
        await acquisition.release();
      }
      final gate = _cleanupGate;
      if (gate != null) await gate.future;
      cleanup.complete();
    } on Object catch (error, stackTrace) {
      cleanup.completeError(error, stackTrace);
    }
  }

  bool emitFrame(int sequence) {
    if (_terminal || _state != SessionState.listening) return false;
    final frame = AudioFrame(
      protocol: ProtocolVersion.current,
      sessionId: sessionId,
      sequence: BigInt.from(sequence),
      monotonicTimeUs: BigInt.from(sequence * 10000),
      format: _format ?? _defaultFormat,
      payloadBase64: 'AA==',
    );
    if (_frameConsumerReady && _pendingFrames.isEmpty) {
      _frameController.add(frame);
    } else {
      if (_pendingFrames.length == _frameCapacity) {
        _pendingFrames.removeFirst();
        droppedFrames++;
      }
      _pendingFrames.addLast(frame);
    }
    return true;
  }

  void _flushFrames() {
    while (_frameConsumerReady &&
        !_frameControllerClosed &&
        _pendingFrames.isNotEmpty) {
      _frameController.add(_pendingFrames.removeFirst());
    }
  }

  void _transition(SessionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}

final class _FakeAcquisition {
  _FakeAcquisition({Completer<void>? releaseGate}) : _releaseGate = releaseGate;

  final Completer<void>? _releaseGate;
  final Completer<void> _released = Completer<void>();
  Future<void>? _releaseFuture;
  var releaseCalls = 0;

  Future<void> get released => _released.future;

  Future<void> release() {
    final existing = _releaseFuture;
    if (existing != null) return existing;
    releaseCalls++;
    final future = _release();
    _releaseFuture = future;
    return future;
  }

  Future<void> _release() async {
    final gate = _releaseGate;
    if (gate != null) await gate.future;
    if (!_released.isCompleted) _released.complete();
  }
}
