import 'dart:async';

import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:test/test.dart';

import 'support/fake_connector.dart';
import 'support/fake_provider.dart';

const _timeouts = CaptureTimeouts(
  startup: Duration(milliseconds: 1000),
  endpoint: Duration(milliseconds: 500),
  finalize: Duration(milliseconds: 500),
  shutdown: Duration(milliseconds: 200),
  warmHold: Duration(milliseconds: 1000),
);

void main() {
  group('startup', () {
    test(
      'connects, opens the provider, and publishes ordered events',
      () async {
        final h = _Harness();
        final started = h.coordinator.start(source: fakeSource());
        await pumpEventQueue();
        expect(h.snapshot.state, CaptureState.starting);
        expect(h.snapshot.sessionId, 'session-1');

        h.connector.completeConnect();
        await pumpEventQueue();
        expect(h.provider.pendingOpens, 1);
        expect(h.provider.startedFormats.single, same(fakeFormat));

        h.provider.completeOpen();
        await started;
        await pumpEventQueue();
        expect(h.states, [CaptureState.starting, CaptureState.listening]);
        expect(h.kinds, [
          RuntimePayloadKind.sessionStateChanged,
          RuntimePayloadKind.sessionStateChanged,
        ]);
        expect(h.events.map((event) => event.sequence.toInt()), [1, 2]);
        expect(
          h.events.every((event) => event.sessionId == 'session-1'),
          isTrue,
        );
        expect(h.events.last.payload, {
          'previous': 'SESSION_STATE_STARTING',
          'current': 'SESSION_STATE_LISTENING',
        });
        expect(h.scheduler.pendingTimers, 0);
      },
    );

    test('rejects modes the coordinator does not police', () {
      final h = _Harness();
      for (final mode in [CaptureMode.unspecified, CaptureMode.wakePhrase]) {
        expect(
          () => h.coordinator.start(source: fakeSource(), mode: mode),
          throwsArgumentError,
        );
      }
      expect(h.snapshot.state, CaptureState.idle);
    });

    test(
      'startup timeout fails the generation and releases late work',
      () async {
        final h = _Harness();
        final started = h.coordinator.start(source: fakeSource());
        final failed = expectLater(
          started,
          throwsA(_voiceError('startup_timeout')),
        );
        await pumpEventQueue();
        h.scheduler.advance(_timeouts.startup);
        await failed;
        await pumpEventQueue();
        expect(h.snapshot.state, CaptureState.error);
        expect(h.snapshot.error?.retryable, isTrue);
        expect(h.kinds.last, RuntimePayloadKind.sessionStateChanged);
        expect(h.kinds[h.kinds.length - 2], RuntimePayloadKind.error);
        expect(h.events[1].payload, {
          'code': 'startup_timeout',
          'message': 'The source or provider did not start in time.',
          'retryable': true,
        });

        final late = h.connector.completeConnect();
        await pumpEventQueue();
        expect(late.stopCalls, 1);
        expect(h.events, hasLength(3));
      },
    );

    test('connect and provider failures publish their cause', () async {
      final h = _Harness();
      final failure = VoiceError(
        code: 'connect_failed',
        message: 'The synthetic source did not connect.',
        retryable: true,
        metadata: {'transport': 'synthetic'},
      );
      final started = h.coordinator.start(source: fakeSource());
      final failed = expectLater(started, throwsA(same(failure)));
      await pumpEventQueue();
      h.connector.failConnect(failure);
      await failed;
      await pumpEventQueue();
      expect(h.snapshot.error, same(failure));
      expect(h.events[1].payload['metadata'], {'transport': 'synthetic'});
      expect(h.scheduler.pendingTimers, 0);

      final second = h.coordinator.start(source: fakeSource());
      final secondFailed = expectLater(
        second,
        throwsA(_voiceError('open_failed')),
      );
      await pumpEventQueue();
      h.connector.completeConnect();
      await pumpEventQueue();
      h.provider.failOpen(
        VoiceError(code: 'open_failed', message: 'no', retryable: false),
      );
      await secondFailed;
      await pumpEventQueue();
      expect(h.connector.latestSession.stopCalls, 1);
      expect(h.snapshot.sessionId, 'session-2');
    });
  });

  group('input gating', () {
    test('pre-roll drains in order and merges with live frames', () async {
      final h = _Harness();
      final started = h.coordinator.start(source: fakeSource());
      await pumpEventQueue();
      final session = h.connector.completeConnect();
      await pumpEventQueue();
      expect(session.emitFrame(1), isTrue);
      expect(session.emitFrame(2), isTrue);

      final provider = h.provider.completeOpen()..holdFrames = true;
      await started;
      await pumpEventQueue();
      expect(provider.frames.map(_seq), [1]);
      session.emitFrame(3);
      provider.releaseFrame();
      await pumpEventQueue();
      provider.releaseFrame();
      await pumpEventQueue();
      provider.releaseFrame();
      await pumpEventQueue();
      expect(provider.frames.map(_seq), [1, 2, 3]);
    });

    test('pre-roll is bounded and drops the oldest frame', () async {
      final h = _Harness(preRoll: const PreRoll(maxFrames: 2));
      final started = h.coordinator.start(source: fakeSource());
      await pumpEventQueue();
      final session = h.connector.completeConnect();
      await pumpEventQueue();
      for (var sequence = 1; sequence <= 4; sequence++) {
        session.emitFrame(sequence);
      }
      final provider = h.provider.completeOpen();
      await started;
      await pumpEventQueue();
      expect(provider.frames.map(_seq), [3, 4]);
    });

    test('a rejected frame fails the generation', () async {
      final h = _Harness();
      final (session, provider) = await h.listen();
      provider.rejectFrames = true;
      session.emitFrame(1);
      await pumpEventQueue();
      expect(h.snapshot.state, CaptureState.error);
      expect(h.snapshot.error?.code, 'provider_frame_rejected');
    });

    test('release gates new input immediately and keeps the tail', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (session, provider) = await h.listen(mode: CaptureMode.holdToTalk);
      session.emitFrame(1);
      provider.emit(const ProviderPartial('synthetic hel'));
      final released = h.coordinator.release();
      expect(h.snapshot.state, CaptureState.finalizing);
      expect(h.snapshot.partialText, isEmpty);
      expect(h.snapshot.finalizePending, isTrue);
      session.emitFrame(2);
      await pumpEventQueue();
      expect(provider.frames.map(_seq), [1]);
      expect(provider.finalizeCalls, 1);

      provider.emit(const ProviderFinal('synthetic hello'));
      provider.completeFinalize();
      await released;
      await pumpEventQueue();
      expect(utterances, ['synthetic hello']);
      expect(h.snapshot.state, CaptureState.stopped);
      expect(h.snapshot.finalizePending, isFalse);
      expect(h.states, [
        CaptureState.starting,
        CaptureState.listening,
        CaptureState.finalizing,
        CaptureState.stopped,
      ]);
      expect(session.stopCalls, 1);
      expect(provider.stopCalls, 1);
      expect(h.scheduler.pendingTimers, 0);
    });

    test('release during startup cancels the generation', () async {
      final h = _Harness();
      final started = h.coordinator.start(
        source: fakeSource(),
        mode: CaptureMode.holdToTalk,
      );
      final cancelled = expectLater(started, throwsA(_voiceError('cancelled')));
      await pumpEventQueue();
      await h.coordinator.release();
      await cancelled;
      expect(h.snapshot.state, CaptureState.stopped);

      final late = h.connector.completeConnect();
      await pumpEventQueue();
      expect(late.stopCalls, 1);
      expect(h.provider.pendingOpens, 0);
      await pumpEventQueue();
      expect(h.states, [CaptureState.starting, CaptureState.stopped]);
    });

    test('release is a no-op outside a held utterance', () async {
      final h = _Harness();
      await h.coordinator.release();
      expect(h.snapshot.state, CaptureState.idle);
      final (_, provider) = await h.listen(mode: CaptureMode.tapToSpeak);
      final finalizing = h.coordinator.finalize();
      await h.coordinator.release();
      expect(provider.finalizeCalls, 1);
      provider.completeFinalize();
      await finalizing;
      await h.coordinator.release();
      expect(h.snapshot.state, CaptureState.stopped);
    });
  });

  group('warm push-to-talk', () {
    test('release parks warm-muted, delivers the tail, and resumes', () async {
      final h = _Harness(
        capabilities: {
          ProviderCapability.gracefulFinalize,
          ProviderCapability.warmGate,
        },
      );
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (session, provider) = await h.listen(mode: CaptureMode.holdToTalk);
      session.emitFrame(1);
      final released = h.coordinator.release();
      expect(h.snapshot.state, CaptureState.warmMuted);
      expect(h.snapshot.finalizePending, isTrue);
      session.emitFrame(2);
      await pumpEventQueue();
      expect(provider.frames.map(_seq), [1]);
      expect(provider.gateCalls, [(open: false, flush: true)]);

      provider.emit(const ProviderFinal('synthetic one'));
      provider.completeFlush();
      await released;
      expect(utterances, ['synthetic one']);
      expect(h.snapshot.finalizePending, isFalse);
      expect(h.snapshot.state, CaptureState.warmMuted);
      expect(h.scheduler.pendingTimers, 1);

      provider.emit(const ProviderFinal('synthetic late'));
      await h.coordinator.start(
        source: fakeSource(),
        mode: CaptureMode.holdToTalk,
      );
      expect(h.snapshot.state, CaptureState.listening);
      expect(h.snapshot.sessionId, 'session-1');
      expect(h.snapshot.bufferedFinalText, isEmpty);
      expect(provider.gateCalls.last, (open: true, flush: false));
      expect(h.scheduler.pendingTimers, 0);
      session.emitFrame(3);
      await pumpEventQueue();
      expect(provider.frames.map(_seq), [1, 3]);

      final secondRelease = h.coordinator.release();
      provider.emit(const ProviderFinal('synthetic two'));
      provider.completeFlush();
      await secondRelease;
      expect(utterances, ['synthetic one', 'synthetic two']);

      h.scheduler.advance(_timeouts.warmHold);
      await pumpEventQueue();
      expect(h.snapshot.state, CaptureState.stopped);
      expect(h.states, [
        CaptureState.starting,
        CaptureState.listening,
        CaptureState.warmMuted,
        CaptureState.listening,
        CaptureState.warmMuted,
        CaptureState.stopped,
      ]);
      expect(h.scheduler.pendingTimers, 0);
    });

    test('resume waits for the pending flush before reopening', () async {
      final h = _Harness(capabilities: {ProviderCapability.warmGate});
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (session, provider) = await h.listen(mode: CaptureMode.holdToTalk);
      final released = h.coordinator.release();
      final resumed = h.coordinator.start(
        source: fakeSource(),
        mode: CaptureMode.holdToTalk,
      );
      expect(h.snapshot.state, CaptureState.listening);
      session.emitFrame(1);
      await pumpEventQueue();
      expect(provider.gateCalls, [(open: false, flush: true)]);
      expect(provider.frames, isEmpty);

      provider.emit(const ProviderFinal('synthetic first'));
      provider.completeFlush();
      await released;
      await resumed;
      await pumpEventQueue();
      expect(utterances, ['synthetic first']);
      expect(provider.gateCalls.last, (open: true, flush: false));
      expect(provider.frames.map(_seq), [1]);
      expect(h.scheduler.pendingTimers, 0);
    });

    test('flush timeout delivers what arrived', () async {
      final h = _Harness(capabilities: {ProviderCapability.warmGate});
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen(mode: CaptureMode.holdToTalk);
      final released = h.coordinator.release();
      provider.emit(const ProviderFinal('synthetic partial tail'));
      h.scheduler.advance(_timeouts.finalize);
      await pumpEventQueue();
      expect(utterances, ['synthetic partial tail']);
      expect(h.snapshot.state, CaptureState.warmMuted);
      provider.completeFlush();
      await released;
      expect(utterances, hasLength(1));
    });

    test('without a warm gate release finalizes and stops', () async {
      final h = _Harness(capabilities: {ProviderCapability.gracefulFinalize});
      final (_, provider) = await h.listen(mode: CaptureMode.holdToTalk);
      final released = h.coordinator.release();
      expect(h.snapshot.state, CaptureState.finalizing);
      provider.completeFinalize();
      await released;
      expect(h.snapshot.state, CaptureState.stopped);
      expect(provider.gateCalls, isEmpty);
    });
  });

  group('finalization', () {
    test('concurrent finalize shares one result and one utterance', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      provider.emit(const ProviderFinal('synthetic a'));
      provider.emit(const ProviderFinal('synthetic b'));
      final first = h.coordinator.finalize();
      final second = h.coordinator.finalize();
      expect(identical(first, second), isTrue);
      expect(provider.finalizeCalls, 1);
      provider.completeFinalize();
      final outcome = await first;
      expect(outcome.timedOut, isFalse);
      expect(utterances, ['synthetic a synthetic b']);
      expect(h.snapshot.state, CaptureState.stopped);
      expect(await h.coordinator.finalize(), isA<FinalizationOutcome>());
    });

    test('finalize timeout is graceful', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      provider.emit(const ProviderFinal('synthetic kept'));
      final finalizing = h.coordinator.finalize();
      h.scheduler.advance(_timeouts.finalize);
      final outcome = await finalizing;
      expect(outcome.timedOut, isTrue);
      expect(utterances, ['synthetic kept']);
      expect(h.snapshot.state, CaptureState.stopped);
      expect(h.snapshot.error, isNull);
      await pumpEventQueue();
      expect(provider.stopCalls, 1);
    });

    test('stop during finalization cancels the utterance', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      provider.emit(const ProviderFinal('synthetic dropped'));
      final finalizing = h.coordinator.finalize();
      final stopped = h.coordinator.stop();
      expect(identical(stopped, h.coordinator.stop()), isTrue);
      await Future.wait([finalizing, stopped]);
      provider.completeFinalize();
      await pumpEventQueue();
      expect(utterances, isEmpty);
      expect(h.snapshot.state, CaptureState.stopped);
      expect(h.states.last, CaptureState.stopped);
      expect(h.states.where((s) => s == CaptureState.stopped), hasLength(1));
    });

    test('without graceful finalize the provider is stopped', () async {
      final h = _Harness(capabilities: const {});
      final (_, provider) = await h.listen();
      provider.emit(const ProviderFinal('synthetic hard'));
      final outcome = await h.coordinator.finalize();
      expect(outcome.timedOut, isFalse);
      expect(provider.finalizeCalls, 0);
      expect(provider.stopCalls, 1);
      expect(h.snapshot.state, CaptureState.stopped);
    });

    test('an empty final is emitted but never buffered', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      provider.emit(const ProviderFinal(''));
      await pumpEventQueue();
      expect(h.events.last.payload, {
        'kind': 'TRANSCRIPT_KIND_FINAL',
        'text': '',
      });
      expect(h.snapshot.bufferedFinalText, isEmpty);
      final finalizing = h.coordinator.finalize();
      provider.completeFinalize();
      await finalizing;
      expect(utterances, isEmpty);
    });

    test('rejected text is emitted but never enters the utterance', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      provider.emit(const ProviderPartial('synthetic maybe'));
      expect(h.snapshot.partialText, 'synthetic maybe');
      provider.emit(const ProviderRejected('synthetic maybe'));
      expect(h.snapshot.partialText, isEmpty);
      provider.emit(const ProviderFinal('synthetic yes'));
      await pumpEventQueue();
      expect(
        h.events.map((event) => event.payload['kind']).whereType<String>(),
        [
          'TRANSCRIPT_KIND_PARTIAL',
          'TRANSCRIPT_KIND_REJECTED',
          'TRANSCRIPT_KIND_FINAL',
        ],
      );
      final finalizing = h.coordinator.finalize();
      provider.completeFinalize();
      await finalizing;
      expect(utterances, ['synthetic yes']);
    });

    test('a late final from an ended generation is dropped', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      await h.coordinator.stop();
      provider.emit(const ProviderFinal('synthetic late'));
      await pumpEventQueue();
      expect(h.kinds.where((k) => k == RuntimePayloadKind.transcript), isEmpty);
      expect(h.snapshot.bufferedFinalText, isEmpty);
      expect(utterances, isEmpty);
    });

    test('a final during finalization is kept', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      final finalizing = h.coordinator.finalize();
      provider.emit(const ProviderFinal('synthetic tail'));
      provider.completeFinalize();
      await finalizing;
      expect(utterances, ['synthetic tail']);
    });
  });

  group('hands-free', () {
    test('combines finals across a pause and finalizes once', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen(mode: CaptureMode.handsFree);
      provider.emit(const ProviderFinal('synthetic one'));
      h.scheduler.advance(const Duration(milliseconds: 300));
      provider.emit(const ProviderPartial('synthetic tw'));
      h.scheduler.advance(_timeouts.endpoint);
      expect(h.snapshot.state, CaptureState.listening);
      provider.emit(const ProviderFinal('synthetic two'));
      h.scheduler.advance(const Duration(milliseconds: 300));
      provider.emit(const ProviderFinal('synthetic three'));
      h.scheduler.advance(_timeouts.endpoint);
      await pumpEventQueue();
      expect(h.snapshot.state, CaptureState.finalizing);
      expect(provider.finalizeCalls, 1);
      provider.completeFinalize();
      await pumpEventQueue();
      expect(utterances, ['synthetic one synthetic two synthetic three']);
      expect(h.snapshot.state, CaptureState.stopped);
      expect(h.scheduler.pendingTimers, 0);
    });
  });

  group('stop and supersede', () {
    test('stop is safe before, during, and after startup', () async {
      final h = _Harness();
      await h.coordinator.stop();
      expect(h.snapshot.state, CaptureState.idle);

      final started = h.coordinator.start(source: fakeSource());
      final cancelled = expectLater(started, throwsA(_voiceError('cancelled')));
      await pumpEventQueue();
      final first = h.coordinator.stop();
      expect(identical(first, h.coordinator.stop()), isTrue);
      await first;
      await cancelled;
      expect(h.snapshot.state, CaptureState.stopped);

      final late = h.connector.completeConnect();
      await pumpEventQueue();
      expect(late.stopCalls, 1);
      await h.coordinator.stop();
      expect(h.states, [CaptureState.starting, CaptureState.stopped]);
    });

    test('stop after listening cleans up once', () async {
      final h = _Harness();
      final (session, provider) = await h.listen();
      await h.coordinator.stop();
      await h.coordinator.stop();
      expect(session.stopCalls, 1);
      expect(provider.stopCalls, 1);
      expect(h.states.last, CaptureState.stopped);
      expect(h.snapshot.state, CaptureState.stopped);
    });

    test('shutdown timeout detaches cleanup without publishing', () async {
      final h = _Harness();
      final (_, provider) = await h.listen();
      final hang = Completer<void>();
      provider.stopGate = hang.future;
      final stopped = h.coordinator.stop();
      var done = false;
      unawaited(stopped.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);
      h.scheduler.advance(_timeouts.shutdown);
      await stopped;
      final eventCount = h.events.length;
      hang.complete();
      await pumpEventQueue();
      expect(h.events, hasLength(eventCount));
    });

    test('rapid restart supersedes and ignores the old generation', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (oldSession, oldProvider) = await h.listen();
      final second = h.coordinator.start(source: fakeSource());
      expect(h.snapshot.sessionId, 'session-2');
      expect(h.snapshot.state, CaptureState.starting);
      oldProvider.emit(const ProviderFinal('synthetic late'));
      await pumpEventQueue();
      expect(oldSession.stopCalls, 1);
      expect(oldProvider.stopCalls, 1);
      await pumpEventQueue();
      h.connector.completeConnect();
      await pumpEventQueue();
      h.provider.completeOpen();
      await second;
      await pumpEventQueue();
      expect(h.snapshot.bufferedFinalText, isEmpty);
      expect(h.kinds.where((k) => k == RuntimePayloadKind.transcript), isEmpty);
      final ids = h.events.map((event) => event.sessionId).toList();
      expect(ids, [
        'session-1',
        'session-1',
        'session-1',
        'session-2',
        'session-2',
      ]);
      expect(h.events.map((event) => event.sequence.toInt()), [1, 2, 3, 1, 2]);
      expect(h.events[2].payload['current'], 'SESSION_STATE_STOPPED');
      expect(h.events[3].payload['previous'], 'SESSION_STATE_IDLE');
      expect(utterances, isEmpty);
    });

    test('start after an unfinished stop waits for its cleanup', () async {
      final h = _Harness();
      final (_, provider) = await h.listen();
      final hang = Completer<void>();
      provider.stopGate = hang.future;
      final stopped = h.coordinator.stop();
      final restarted = h.coordinator.start(source: fakeSource());
      await pumpEventQueue();
      expect(h.connector.connectCalls, 1);
      hang.complete();
      await stopped;
      await pumpEventQueue();
      expect(h.connector.connectCalls, 2);
      h.connector.completeConnect();
      await pumpEventQueue();
      h.provider.completeOpen();
      await restarted;
      expect(h.snapshot.state, CaptureState.listening);
    });
  });

  group('source and provider signals', () {
    test('provider disconnect ends the generation with an error', () async {
      final h = _Harness();
      final (_, provider) = await h.listen();
      provider.emit(const ProviderClosed(expected: false));
      await pumpEventQueue();
      expect(h.snapshot.state, CaptureState.error);
      expect(h.snapshot.error?.code, 'provider_closed');
      expect(h.kinds.sublist(2), [
        RuntimePayloadKind.error,
        RuntimePayloadKind.sessionStateChanged,
      ]);
    });

    test('provider failure publishes its cause', () async {
      final h = _Harness();
      final (_, provider) = await h.listen();
      final failure = VoiceError(
        code: 'provider_failed',
        message: 'decoder crashed',
        retryable: false,
      );
      provider.emit(ProviderFailure(failure));
      await pumpEventQueue();
      expect(h.snapshot.error, same(failure));
      expect(h.events[2].payload['retryable'], isFalse);
    });

    test('an unexpected close during finalization completes it', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (_, provider) = await h.listen();
      provider.emit(const ProviderFinal('synthetic done'));
      final finalizing = h.coordinator.finalize();
      provider.emit(const ProviderClosed(expected: false));
      expect((await finalizing).timedOut, isFalse);
      expect(utterances, ['synthetic done']);
      expect(h.snapshot.state, CaptureState.stopped);
    });

    test('a source failure ends the generation with its error', () async {
      final h = _Harness();
      final (session, _) = await h.listen();
      final failure = VoiceError(
        code: 'device_lost',
        message: 'gone',
        retryable: true,
      );
      session.fail(failure);
      await pumpEventQueue();
      expect(h.snapshot.state, CaptureState.error);
      expect(h.snapshot.error, same(failure));
    });

    test('a source that ends on its own finalizes the utterance', () async {
      final h = _Harness();
      final utterances = <String>[];
      h.onUtterance = utterances.add;
      final (session, provider) = await h.listen();
      provider.emit(const ProviderFinal('synthetic file'));
      session.endFromSource();
      expect(h.snapshot.state, CaptureState.finalizing);
      provider.completeFinalize();
      await pumpEventQueue();
      expect(utterances, ['synthetic file']);
      expect(h.snapshot.state, CaptureState.stopped);
    });
  });

  group('readiness and level', () {
    test('frame readiness ignores silence and reports once', () async {
      final h = _Harness();
      final (session, _) = await h.listen();
      session.emitFrame(1, silent: true);
      await pumpEventQueue();
      expect(h.snapshot.captureLive, isFalse);
      session.emitFrame(2);
      session.emitFrame(3);
      await pumpEventQueue();
      expect(h.snapshot.captureLive, isTrue);
      final readiness = h.events.where(
        (event) => event.kind == RuntimePayloadKind.captureReadiness,
      );
      expect(readiness.single.payload, {'live': true});
    });

    test('provider readiness replaces the frame predicate', () async {
      final h = _Harness(capabilities: {ProviderCapability.realAudioReadiness});
      final (session, provider) = await h.listen();
      session.emitFrame(1);
      await pumpEventQueue();
      expect(h.snapshot.captureLive, isFalse);
      provider.emit(const ProviderReadiness(live: true));
      provider.emit(const ProviderReadiness(live: true));
      provider.emit(const ProviderReadiness(live: false));
      await pumpEventQueue();
      expect(h.snapshot.captureLive, isFalse);
      final readiness = h.events
          .where((event) => event.kind == RuntimePayloadKind.captureReadiness)
          .map((event) => event.payload['live']);
      expect(readiness, [true, false]);
    });

    test('amplitude updates the snapshot and emits audio levels', () async {
      final h = _Harness();
      final (_, provider) = await h.listen();
      provider.emit(ProviderAmplitude(0.25));
      await pumpEventQueue();
      expect(h.snapshot.amplitude, 0.25);
      expect(h.events.last.payload, {'amplitude': 0.25});
      expect(() => ProviderAmplitude(1.5), throwsArgumentError);
    });
  });

  group('stream semantics', () {
    test(
      'streams have no replay and the snapshot is readable after end',
      () async {
        final h = _Harness();
        final (_, provider) = await h.listen();
        final lateStates = <CaptureState>[];
        final subscription = h.coordinator.stateChanges.listen(lateStates.add);
        expect(h.snapshot.state, CaptureState.listening);
        expect(lateStates, isEmpty);
        provider.emit(ProviderAmplitude(0.5));
        await h.coordinator.stop();
        await pumpEventQueue();
        expect(lateStates, [CaptureState.stopped]);
        expect(h.snapshot.amplitude, 0.5);
        expect(h.snapshot.mode, CaptureMode.tapToSpeak);
        await subscription.cancel();
      },
    );

    test('monotonic time follows the injected clock', () async {
      final h = _Harness();
      h.scheduler.advance(const Duration(milliseconds: 5));
      final (_, provider) = await h.listen();
      h.scheduler.advance(const Duration(milliseconds: 7));
      provider.emit(ProviderAmplitude(0.1));
      await pumpEventQueue();
      expect(h.events.map((event) => event.monotonicTimeUs.toInt()), [
        5000,
        5000,
        12000,
      ]);
    });
  });
}

Matcher _voiceError(String code) =>
    isA<VoiceError>().having((error) => error.code, 'code', code);

int _seq(AudioFrame frame) => frame.sequence.toInt();

final class _Harness {
  _Harness({
    Set<ProviderCapability> capabilities = const {
      ProviderCapability.partialTranscripts,
      ProviderCapability.gracefulFinalize,
    },
    PreRoll preRoll = const PreRoll(),
  }) : connector = FakeConnector(),
       provider = FakeProvider(capabilities: capabilities),
       scheduler = ManualScheduler() {
    var sessions = 0;
    coordinator = VoiceCaptureCoordinator(
      connector,
      provider,
      onUtteranceFinalized: (text) => onUtterance?.call(text),
      timeouts: _timeouts,
      preRoll: preRoll,
      sessionIdFactory: () => 'session-${++sessions}',
      scheduler: scheduler,
    );
    coordinator.events.listen(events.add);
    coordinator.stateChanges.listen(states.add);
  }

  final FakeConnector connector;
  final FakeProvider provider;
  final ManualScheduler scheduler;
  late final VoiceCaptureCoordinator coordinator;
  final List<RuntimeEvent> events = [];
  final List<CaptureState> states = [];
  void Function(String text)? onUtterance;

  CaptureSnapshot get snapshot => coordinator.snapshot;
  List<RuntimePayloadKind> get kinds =>
      events.map((event) => event.kind).toList();

  /// Starts a generation and drives it to listening.
  Future<(FakeSession, FakeProviderSession)> listen({
    CaptureMode mode = CaptureMode.tapToSpeak,
  }) async {
    final started = coordinator.start(source: fakeSource(), mode: mode);
    await pumpEventQueue();
    final session = connector.completeConnect();
    await pumpEventQueue();
    final providerSession = provider.completeOpen();
    await started;
    await pumpEventQueue();
    return (session, providerSession);
  }
}
