import 'dart:async';

import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:test/test.dart';

import 'support/fake_voice_provider.dart';

void main() {
  group('provider values', () {
    test('rejects a blank session id', () {
      for (final id in ['', '  ']) {
        expect(
          () => ProviderSessionRequest(sessionId: id, format: _format()),
          throwsArgumentError,
        );
      }
    });

    test('rejects empty final and rejected text', () {
      expect(() => ProviderFinal(''), throwsArgumentError);
      expect(() => ProviderRejected(''), throwsArgumentError);
      expect(ProviderFinal(' hi').text, ' hi');
      expect(const ProviderPartial('').text, isEmpty);
    });

    test('bounds amplitude to 0..1 and rejects NaN', () {
      expect(ProviderAmplitude(0).value, 0);
      expect(ProviderAmplitude(1).value, 1);
      for (final value in [-0.01, 1.01, double.nan, double.infinity]) {
        expect(() => ProviderAmplitude(value), throwsArgumentError);
      }
    });

    test('exposes unmodifiable capabilities and sessions', () {
      final capabilities = {ProviderCapability.amplitude};
      final provider = FakeVoiceProvider(capabilities: capabilities);
      capabilities.add(ProviderCapability.immediateMute);

      expect(provider.capabilities, {ProviderCapability.amplitude});
      expect(
        () => provider.capabilities.add(ProviderCapability.rejectedFinals),
        throwsUnsupportedError,
      );
      provider.createSession(_request());
      expect(provider.sessions, hasLength(1));
      expect(provider.sessions.clear, throwsUnsupportedError);
    });
  });

  group('request, format, and startup', () {
    test('carries every documented audio encoding', () {
      final provider = FakeVoiceProvider();
      for (final encoding in AudioEncoding.values) {
        final session = provider.createSession(
          _request(format: _format(encoding: encoding)),
        );
        expect(session.request.format.encoding, encoding);
        expect(session.request.sessionId, 'capture-1');
      }
    });

    test('rejects an unsupported format synchronously', () {
      final provider = FakeVoiceProvider(
        supportedEncodings: {AudioEncoding.pcmS16le},
      );
      expect(
        () => provider.createSession(
          _request(format: _format(encoding: AudioEncoding.opus)),
        ),
        throwsA(_voiceError('unsupported_format', retryable: false)),
      );
      expect(provider.sessions, isEmpty);
    });

    test('creates an inert session that emits nothing', () async {
      final run = _Run(FakeVoiceProvider().createSession(_request()));
      await pumpEventQueue();

      expect(run.events, isEmpty);
      expect(run.done, isFalse);
      expect(run.session.startCalls, 0);
    });

    test('a held start stays pending and concurrent starts share it', () async {
      final run = _Run(
        FakeVoiceProvider(
          holdStart: true,
          capabilities: {ProviderCapability.realAudioReadiness},
        ).createSession(_request()),
      );
      var started = false;
      final first = run.session.start()..then((_) => started = true);
      final second = run.session.start();
      await pumpEventQueue();

      expect(identical(first, second), isTrue);
      expect(run.session.startPending, isTrue);
      expect(started, isFalse);

      run.session.emitReadiness(live: false);
      run.session.completeStart();
      await first;
      expect(started, isTrue);
      expect(run.session.startPending, isFalse);
      expect(run.session.startCalls, 2);
      expect(run.events.single, isA<ProviderReadiness>());
    });

    test('a startup failure surfaces its exact error and closes', () async {
      final run = _Run(
        FakeVoiceProvider(holdStart: true).createSession(_request()),
      );
      final start = run.session.start();
      final rateLimited = VoiceError(
        code: 'rate_limited',
        message: 'Too many sessions.',
        retryable: true,
        metadata: {'retryAfterMs': '1500'},
      );
      run.session.failStart(rateLimited);

      await expectLater(start, throwsA(same(rateLimited)));
      await pumpEventQueue();
      expect(run.events, isEmpty);
      expect(run.done, isTrue);
      expect(run.session.isClosed, isTrue);
    });

    test('stop during a pending start cancels it', () async {
      final run = _Run(
        FakeVoiceProvider(holdStart: true).createSession(_request()),
      );
      final start = run.session.start();
      final startExpectation = expectLater(
        start,
        throwsA(_voiceError('cancelled')),
      );
      await run.session.stop();
      await startExpectation;
      await pumpEventQueue();
      expect(run.done, isTrue);
      // A late acquisition after cancellation is ignored.
      run.session.completeStart();
    });

    test(
      'disconnect during a pending start fails it without an event',
      () async {
        final run = _Run(
          FakeVoiceProvider(holdStart: true).createSession(_request()),
        );
        final start = run.session.start();
        run.session.disconnect();

        await expectLater(start, throwsA(_voiceError('provider_disconnected')));
        await pumpEventQueue();
        expect(run.events, isEmpty);
        expect(run.done, isTrue);
      },
    );

    test('start is one-shot after every settled outcome', () async {
      final provider = FakeVoiceProvider(holdStart: true);

      final succeeded = await _started(provider);
      expect(succeeded.session.start, throwsStateError);
      expect(succeeded.session.startCalls, 2);

      final failed = _Run(provider.createSession(_request()));
      final failedStart = failed.session.start();
      failed.session.failStart(_failure('unauthorized', retryable: false));
      await expectLater(failedStart, throwsA(_voiceError('unauthorized')));
      expect(failed.session.start, throwsStateError);

      final cancelled = _Run(provider.createSession(_request()));
      final cancelledStart = cancelled.session.start();
      final cancelledStartExpectation = expectLater(
        cancelledStart,
        throwsA(_voiceError('cancelled')),
      );
      await cancelled.session.stop();
      await cancelledStartExpectation;
      expect(cancelled.session.start, throwsStateError);

      final finalized = await _started(provider);
      final finalize = finalized.session.finalize();
      finalized.session.completeFinalize();
      await finalize;
      expect(finalized.session.start, throwsStateError);
    });

    test('stop before start takes precedence over pre-start rules', () async {
      final run = _Run(FakeVoiceProvider().createSession(_request()));
      await run.session.stop();

      await expectLater(
        run.session.finalize(),
        throwsA(_voiceError('cancelled')),
      );
      await expectLater(
        run.session.addFrame(_frame(1)),
        throwsA(_voiceError('cancelled')),
      );
      expect(run.session.start, throwsStateError);
      run.session.emitPartial('late');
      await pumpEventQueue();
      expect(run.events, isEmpty);
      expect(run.done, isTrue);
    });

    test('a live session rejects driver events before start', () {
      final session = FakeVoiceProvider().createSession(_request());

      expect(() => session.emitPartial('early'), throwsStateError);
      expect(() => session.fail(_failure('boom')), throwsStateError);
      expect(session.disconnect, throwsStateError);
    });

    test('rejects frames before start completes', () async {
      final session = FakeVoiceProvider(
        holdStart: true,
      ).createSession(_request());
      expect(() => session.addFrame(_frame(1)), throwsStateError);

      final start = session.start();
      expect(() => session.addFrame(_frame(1)), throwsStateError);
      session.completeStart();
      await start;
      await session.addFrame(_frame(1));
      expect(session.frames, hasLength(1));
    });
  });

  group('partials', () {
    test('each partial replaces the open hypothesis in order', () async {
      final run = await _started(FakeVoiceProvider());
      run.session
        ..emitPartial('he')
        ..emitPartial('hello')
        ..emitPartial('')
        ..emitFinal('Hello.')
        ..emitPartial(' wor');

      expect(run.partials, ['he', 'hello', '', ' wor']);
      expect(run.openHypothesis, ' wor');
      expect(run.transcript, 'Hello.');
    });

    test('a final clears the open hypothesis', () async {
      final run = await _started(FakeVoiceProvider());
      run.session
        ..emitPartial('hel')
        ..emitFinal('Hello');

      expect(run.openHypothesis, isEmpty);
    });
  });

  group('multi-final assembly', () {
    test('concatenates finals verbatim across partials and finalize', () async {
      final run = await _started(FakeVoiceProvider());
      run.session
        ..emitPartial('Turn')
        ..emitFinal('Turn on')
        ..emitPartial(' the')
        ..emitFinal(' the lights.');
      final finalize = run.session.finalize();
      run.session
        ..emitPartial('你')
        ..emitFinal('你好')
        ..emitFinal('。')
        ..completeFinalize();
      await finalize;

      expect(run.transcript, 'Turn on the lights.你好。');
    });

    test('every final arrives before finalize completes and done', () async {
      final run = await _started(FakeVoiceProvider());
      final finalize = run.session.finalize()
        ..then((_) => run.order.add('finalized'));
      run.session
        ..emitFinal('one')
        ..emitFinal(' two')
        ..completeFinalize();
      await finalize;
      await pumpEventQueue();

      expect(run.order, ['final', 'final', 'done', 'finalized']);
    });
  });

  group('finalization', () {
    test('discards frames offered while and after finalizing', () async {
      final run = await _started(FakeVoiceProvider());
      await run.session.addFrame(_frame(1));
      final finalize = run.session.finalize();

      await run.session.addFrame(_frame(2));
      run.session.completeFinalize();
      await finalize;
      await run.session.addFrame(_frame(3));

      expect(run.session.frames.map((frame) => frame.sequence), [BigInt.one]);
    });

    test('a finalized session rejects gate changes and allows stop', () async {
      final run = await _started(
        FakeVoiceProvider(
          capabilities: {
            ProviderCapability.immediateMute,
            ProviderCapability.warmUnmute,
          },
        ),
      );
      final finalize = run.session.finalize();
      expect(run.session.mute, throwsStateError);
      expect(run.session.unmute, throwsStateError);
      run.session.completeFinalize();
      await finalize;

      expect(run.session.mute, throwsStateError);
      expect(run.session.unmute, throwsStateError);
      expect(run.session.start, throwsStateError);
      await run.session.stop();
      await expectLater(run.session.finalize(), completes);
    });

    test('a held frame belongs to the finalized tail', () async {
      final run = await _started(FakeVoiceProvider());
      run.session.holdFrames = true;
      final tail = run.session.addFrame(_frame(1));
      final finalize = run.session.finalize();

      expect(run.session.completeFinalize, throwsStateError);
      run.session.releaseFrame();
      await tail;
      run.session
        ..emitFinal('tail')
        ..completeFinalize();
      await finalize;

      expect(run.session.frames, hasLength(1));
      expect(run.transcript, 'tail');
    });

    test('a late finalize stays pending until completed', () async {
      final run = await _started(FakeVoiceProvider());
      var finalized = false;
      final finalize = run.session.finalize()..then((_) => finalized = true);
      await pumpEventQueue();

      expect(run.session.finalizePending, isTrue);
      expect(finalized, isFalse);
      expect(run.done, isFalse);

      run.session.completeFinalize();
      await finalize;
      expect(finalized, isTrue);
    });

    test('an empty finalize completes with zero finals', () async {
      final run = await _started(FakeVoiceProvider());
      final finalize = run.session.finalize();
      run.session.completeFinalize();
      await finalize;
      await pumpEventQueue();

      expect(run.events, isEmpty);
      expect(run.transcript, isEmpty);
      expect(run.done, isTrue);
    });

    test('finalize before start completes throws', () async {
      final session = FakeVoiceProvider(
        holdStart: true,
      ).createSession(_request());
      expect(session.finalize, throwsStateError);
      final start = session.start();
      expect(session.finalize, throwsStateError);
      session.completeStart();
      await start;
    });
  });

  group('duplicate finalize', () {
    test('replays one terminal future after stop and failures', () async {
      final stopped = await _started(FakeVoiceProvider());
      await stopped.session.stop();

      final failed = await _started(FakeVoiceProvider());
      failed.session.fail(_failure('decoder_crashed'));

      final startFailed = FakeVoiceProvider(
        holdStart: true,
      ).createSession(_request());
      final start = startFailed.start();
      startFailed.failStart(_failure('unauthorized', retryable: false));
      await expectLater(start, throwsA(_voiceError('unauthorized')));

      for (final (session, code) in [
        (stopped.session, 'cancelled'),
        (failed.session, 'decoder_crashed'),
        (startFailed, 'unauthorized'),
      ]) {
        final first = session.finalize();
        final second = session.finalize();
        expect(identical(first, second), isTrue);
        await expectLater(first, throwsA(_voiceError(code)));
        await expectLater(second, throwsA(_voiceError(code)));
      }
    });

    test('concurrent and repeated calls share one future', () async {
      final run = await _started(FakeVoiceProvider());
      final first = run.session.finalize();
      final second = run.session.finalize();
      expect(identical(first, second), isTrue);

      run.session.completeFinalize();
      await first;
      final replay = run.session.finalize();
      expect(identical(first, replay), isTrue);
      await replay;
      expect(run.session.finalizeCalls, 3);
    });
  });

  group('cancellation', () {
    test('stop is idempotent, shared, and closes events', () async {
      final run = await _started(FakeVoiceProvider());
      final first = run.session.stop();
      final second = run.session.stop();
      expect(identical(first, second), isTrue);
      await first;
      await pumpEventQueue();

      expect(run.done, isTrue);
      expect(run.session.isClosed, isTrue);
      expect(run.session.stopCalls, 2);
    });

    test('stop settles a held frame with cancelled', () async {
      final run = await _started(FakeVoiceProvider());
      run.session.holdFrames = true;
      final frame = run.session.addFrame(_frame(1));
      expect(run.session.heldFrames, 1);
      final frameExpectation = expectLater(
        frame,
        throwsA(_voiceError('cancelled')),
      );
      await run.session.stop();
      await frameExpectation;
      expect(run.session.frames, isEmpty);
      expect(run.session.heldFrames, 0);
    });

    test('stop settles pending mute, unmute, and finalize', () async {
      final provider = _warmProvider();
      final muting = await _started(provider);
      final mute = muting.session.mute();
      final muteExpectation = expectLater(
        mute,
        throwsA(_voiceError('cancelled')),
      );
      await muting.session.stop();
      await muteExpectation;

      final unmuting = await _started(provider);
      final muted = unmuting.session.mute();
      unmuting.session.completeMute();
      await muted;
      final unmute = unmuting.session.unmute();
      final unmuteExpectation = expectLater(
        unmute,
        throwsA(_voiceError('cancelled')),
      );
      await unmuting.session.stop();
      await unmuteExpectation;

      final finalizing = await _started(provider);
      final finalize = finalizing.session.finalize();
      final finalizeExpectation = expectLater(
        finalize,
        throwsA(_voiceError('cancelled')),
      );
      await finalizing.session.stop();
      await finalizeExpectation;
    });

    test('operations after stop complete with cancelled', () async {
      final run = await _started(_warmProvider());
      await run.session.stop();

      for (final operation in <Future<void> Function()>[
        () => run.session.addFrame(_frame(1)),
        run.session.mute,
        run.session.unmute,
        run.session.finalize,
      ]) {
        await expectLater(operation(), throwsA(_voiceError('cancelled')));
      }
      expect(run.session.start, throwsStateError);
    });

    test('the ending cause decides after stop overtakes finalize', () async {
      final run = await _started(_warmProvider());
      final finalize = run.session.finalize();
      final stop = run.session.stop();

      await expectLater(finalize, throwsA(_voiceError('cancelled')));
      await expectLater(stop, completes);
      await expectLater(run.session.mute(), throwsA(_voiceError('cancelled')));
      expect(identical(run.session.finalize(), finalize), isTrue);
    });

    test('a stop reentered from onDone shares the future', () async {
      final session = FakeVoiceProvider().createSession(_request());
      Future<void>? reentered;
      session.events.listen(null, onDone: () => reentered = session.stop());
      await session.start();

      final stop = session.stop();
      expect(reentered, isNotNull);
      expect(identical(stop, reentered), isTrue);
      await stop;
      expect(session.stopCalls, 2);
    });

    test('cleanup completes without a listener', () async {
      final session = FakeVoiceProvider().createSession(_request());
      await session.start();
      await session.stop();

      expect(session.isClosed, isTrue);
    });

    test('cleanup completes with a paused listener', () async {
      final run = await _started(FakeVoiceProvider());
      run.subscription.pause();
      await run.session.stop();

      expect(run.session.isClosed, isTrue);
      expect(run.done, isFalse);
      run.subscription.resume();
      await pumpEventQueue();
      expect(run.done, isTrue);
    });
  });

  group('late events', () {
    test('driver events after termination add nothing', () async {
      final provider = FakeVoiceProvider(
        capabilities: {
          ProviderCapability.amplitude,
          ProviderCapability.realAudioReadiness,
          ProviderCapability.rejectedFinals,
        },
      );

      final stopped = await _started(provider);
      await stopped.session.stop();

      final finalized = await _started(provider);
      final finalize = finalized.session.finalize();
      finalized.session.completeFinalize();
      await finalize;

      final failed = await _started(provider);
      failed.session.fail(_failure('boom'));

      for (final run in [stopped, finalized, failed]) {
        final before = run.events.length;
        run.session
          ..emitPartial('late')
          ..emitFinal('late')
          ..rejectFinal('late')
          ..emitReadiness(live: true)
          ..emitAmplitude(0.5)
          ..emitFinal('')
          ..rejectFinal('')
          ..emitAmplitude(2)
          ..fail(_failure('again'))
          ..disconnect();
        await pumpEventQueue();
        expect(run.events, hasLength(before));
        expect(run.done, isTrue);
      }
    });

    test('an undeclared late event still throws', () async {
      final run = await _started(FakeVoiceProvider());
      await run.session.stop();

      expect(() => run.session.emitAmplitude(0.5), throwsStateError);
      expect(() => run.session.rejectFinal(''), throwsStateError);
    });

    test('stop cannot revoke events queued for a paused listener', () async {
      final run = await _started(FakeVoiceProvider());
      run.subscription.pause();
      run.session.emitPartial('queued');
      await run.session.stop();
      run.session.emitFinal('after stop');
      run.subscription.resume();
      await pumpEventQueue();

      expect(run.partials, ['queued']);
      expect(run.transcript, isEmpty);
      expect(run.order, ['partial', 'done']);
    });

    test('ignoreCancellation keeps delivering after stop', () async {
      final run = await _started(FakeVoiceProvider(ignoreCancellation: true));
      run.session.holdFrames = true;
      var frameSettled = false;
      var finalizeSettled = false;
      unawaited(
        run.session.addFrame(_frame(1)).whenComplete(() => frameSettled = true),
      );
      unawaited(
        run.session.finalize().whenComplete(() => finalizeSettled = true),
      );

      await run.session.stop();
      run.session.emitFinal('still here');
      await pumpEventQueue();

      expect(run.session.stopCalls, 1);
      expect(run.transcript, 'still here');
      expect(run.done, isFalse);
      expect(run.session.isClosed, isFalse);
      expect(frameSettled, isFalse);
      expect(finalizeSettled, isFalse);
    });
  });

  group('failure and disconnect', () {
    test('a failure emits exactly one event and then done', () async {
      final run = await _started(FakeVoiceProvider());
      final failure = _failure('decoder_crashed');
      run.session.fail(failure);
      await pumpEventQueue();

      expect(run.events, hasLength(1));
      expect((run.events.single as ProviderFailure).error, same(failure));
      expect(run.order, ['failure', 'done']);
    });

    test('a listener reentering on failure sees the failed session', () async {
      final session = _warmProvider().createSession(_request());
      final failure = _failure('decoder_crashed');
      final order = <String>[];
      final reentered = <Future<void>>[];
      final subscription = session.events.listen((event) {
        order.add('failure');
        reentered
          ..add(session.addFrame(_frame(1)))
          ..add(session.stop())
          ..add(session.finalize());
      }, onDone: () => order.add('done'));
      addTearDown(subscription.cancel);
      await session.start();
      final mute = session.mute();

      session.fail(failure);

      expect(order, ['failure', 'done']);
      await expectLater(mute, throwsA(same(failure)));
      await expectLater(reentered[0], throwsA(same(failure)));
      await expectLater(reentered[1], completes);
      await expectLater(reentered[2], throwsA(same(failure)));
      expect(session.frames, isEmpty);
      await expectLater(session.finalize(), throwsA(same(failure)));
      await expectLater(session.unmute(), throwsA(same(failure)));
    });

    test('pending operations complete with the failure error', () async {
      final run = await _started(_warmProvider());
      run.session.holdFrames = true;
      final frame = run.session.addFrame(_frame(1));
      final mute = run.session.mute();
      final failure = _failure('decoder_crashed');
      run.session.fail(failure);

      await expectLater(frame, throwsA(same(failure)));
      await expectLater(mute, throwsA(same(failure)));

      final finalizing = await _started(FakeVoiceProvider());
      final finalize = finalizing.session.finalize();
      finalizing.session.fail(failure);
      await expectLater(finalize, throwsA(same(failure)));
    });

    test('operations after a failure complete with that error', () async {
      final run = await _started(_warmProvider());
      final failure = _failure('decoder_crashed');
      run.session.fail(failure);

      for (final operation in <Future<void> Function()>[
        () => run.session.addFrame(_frame(1)),
        run.session.mute,
        run.session.unmute,
        run.session.finalize,
      ]) {
        await expectLater(operation(), throwsA(same(failure)));
      }
      expect(run.session.start, throwsStateError);
      await expectLater(run.session.stop(), completes);
    });

    test('operations after a startup failure complete with it', () async {
      final session = _warmProvider(holdStart: true).createSession(_request());
      final start = session.start();
      final failure = _failure('unauthorized', retryable: false);
      session.failStart(failure);
      await expectLater(start, throwsA(same(failure)));

      for (final operation in <Future<void> Function()>[
        () => session.addFrame(_frame(1)),
        session.mute,
        session.unmute,
        session.finalize,
      ]) {
        await expectLater(operation(), throwsA(same(failure)));
      }
      await expectLater(session.stop(), completes);
    });

    test('a mid-session rate limit keeps its metadata', () async {
      final run = await _started(FakeVoiceProvider());
      run.session.fail(
        VoiceError(
          code: 'rate_limited',
          message: 'Slow down.',
          retryable: true,
          metadata: {'retryAfterMs': '2000'},
        ),
      );

      final error = (run.events.single as ProviderFailure).error;
      expect(error.code, 'rate_limited');
      expect(error.retryable, isTrue);
      expect(error.metadata, {'retryAfterMs': '2000'});
    });

    test('disconnect is a retryable provider_disconnected failure', () async {
      final run = await _started(FakeVoiceProvider());
      run.session.disconnect();
      await pumpEventQueue();

      expect(
        (run.events.single as ProviderFailure).error,
        _voiceError('provider_disconnected', retryable: true),
      );
      expect(run.done, isTrue);
    });
  });

  group('capabilities and the input gate', () {
    test('uncapable mute and unmute are unsupported', () async {
      final run = await _started(FakeVoiceProvider());
      expect(run.session.mute, throwsUnsupportedError);
      expect(run.session.unmute, throwsUnsupportedError);

      final muteOnly = await _started(
        FakeVoiceProvider(capabilities: {ProviderCapability.immediateMute}),
      );
      expect(muteOnly.session.unmute, throwsUnsupportedError);
      await muteOnly.session.stop();
      expect(muteOnly.session.unmute, throwsUnsupportedError);
    });

    test('mute closes the gate and flushes the held tail', () async {
      final run = await _started(_warmProvider());
      run.session.holdFrames = true;
      final tail = run.session.addFrame(_frame(1));
      var flushed = false;
      final mute = run.session.mute()..then((_) => flushed = true);

      expect(run.session.muted, isTrue);
      expect(run.session.completeMute, throwsStateError);
      run.session.releaseFrame();
      await tail;
      run.session.emitFinal('tail');
      await pumpEventQueue();
      expect(flushed, isFalse);

      run.session.completeMute();
      await mute;
      expect(run.transcript, 'tail');
      expect(run.session.frames, hasLength(1));

      run.session.holdFrames = false;
      await run.session.addFrame(_frame(2));
      expect(run.session.frames, hasLength(1));
      expect(run.done, isFalse);
    });

    test(
      'a repeated mute shares the flush and a muted mute completes',
      () async {
        final run = await _started(_warmProvider());
        final first = run.session.mute();
        expect(identical(first, run.session.mute()), isTrue);
        run.session.completeMute();
        await first;
        await expectLater(run.session.mute(), completes);
        expect(run.session.mutePending, isFalse);
      },
    );

    test('an open unmute completes immediately', () async {
      final run = await _started(_warmProvider());
      await expectLater(run.session.unmute(), completes);
      expect(run.session.unmutePending, isFalse);
    });

    test('conflicting gate transitions throw while one is pending', () async {
      final run = await _started(_warmProvider());
      final mute = run.session.mute();
      expect(run.session.unmute, throwsStateError);
      expect(run.session.finalize, throwsStateError);
      run.session.completeMute();
      await mute;

      final unmute = run.session.unmute();
      expect(identical(unmute, run.session.unmute()), isTrue);
      expect(run.session.mute, throwsStateError);
      expect(run.session.finalize, throwsStateError);
      run.session.completeUnmute();
      await unmute;

      final finalize = run.session.finalize();
      expect(run.session.mute, throwsStateError);
      expect(run.session.unmute, throwsStateError);
      run.session.completeFinalize();
      await finalize;
    });

    test('frames wait for a pending unmute to complete', () async {
      final run = await _started(_warmProvider());
      final mute = run.session.mute();
      run.session.completeMute();
      await mute;

      final unmute = run.session.unmute();
      expect(() => run.session.addFrame(_frame(1)), throwsStateError);
      run.session.completeUnmute();
      await unmute;
      expect(run.session.muted, isFalse);

      await run.session.addFrame(_frame(1));
      expect(run.session.frames, hasLength(1));
    });

    test('gate changes before start completes throw', () async {
      final session = _warmProvider(holdStart: true).createSession(_request());
      expect(session.mute, throwsStateError);
      expect(session.unmute, throwsStateError);
      expect(session.finalize, throwsStateError);

      final start = session.start();
      expect(session.mute, throwsStateError);
      expect(session.unmute, throwsStateError);
      expect(session.finalize, throwsStateError);
      session.completeStart();
      await start;
    });

    test('warmUnmute requires immediateMute', () {
      expect(
        () => FakeVoiceProvider(capabilities: {ProviderCapability.warmUnmute}),
        throwsArgumentError,
      );
    });

    test('undeclared optional events throw', () async {
      final run = await _started(FakeVoiceProvider());
      expect(() => run.session.emitReadiness(live: true), throwsStateError);
      expect(() => run.session.emitAmplitude(0.5), throwsStateError);
      expect(() => run.session.rejectFinal('no'), throwsStateError);
      expect(() => run.session.emitFinal(''), throwsArgumentError);
      expect(run.events, isEmpty);
    });

    test('declared optional events are delivered', () async {
      final run = await _started(
        FakeVoiceProvider(
          capabilities: {
            ProviderCapability.realAudioReadiness,
            ProviderCapability.amplitude,
          },
        ),
      );
      run.session
        ..emitReadiness(live: true)
        ..emitAmplitude(0.25);

      expect((run.events[0] as ProviderReadiness).live, isTrue);
      expect((run.events[1] as ProviderAmplitude).value, 0.25);
    });

    test('a rejected final is delivered but never assembled', () async {
      final run = await _started(
        FakeVoiceProvider(capabilities: {ProviderCapability.rejectedFinals}),
      );
      run.session
        ..emitFinal('Keep this.')
        ..emitPartial(' someone else')
        ..rejectFinal(' someone else')
        ..emitFinal(' And this.');

      expect(
        run.events.whereType<ProviderRejected>().single.text,
        ' someone else',
      );
      expect(run.openHypothesis, isEmpty);
      expect(run.transcript, 'Keep this. And this.');
    });
  });

  group('backpressure and validity', () {
    test('a held frame stays pending until released', () async {
      final run = await _started(FakeVoiceProvider());
      run.session.holdFrames = true;
      var accepted = false;
      final frame = run.session.addFrame(_frame(1))
        ..then((_) => accepted = true);
      await pumpEventQueue();

      expect(accepted, isFalse);
      expect(run.session.frames, isEmpty);
      expect(() => run.session.addFrame(_frame(2)), throwsStateError);

      run.session.releaseFrame();
      await frame;
      expect(accepted, isTrue);
      expect(run.session.frames.single.sequence, BigInt.one);
      expect(run.session.releaseFrame, throwsStateError);
    });

    test('rejects a mismatched format or non-increasing sequence', () async {
      final run = await _started(FakeVoiceProvider());
      expect(
        () => run.session.addFrame(
          _frame(1, format: _format(encoding: AudioEncoding.opus)),
        ),
        throwsArgumentError,
      );
      expect(
        () => run.session.addFrame(_frame(1, format: _format(channels: 2))),
        throwsArgumentError,
      );

      await run.session.addFrame(_frame(2));
      expect(() => run.session.addFrame(_frame(2)), throwsArgumentError);
      expect(() => run.session.addFrame(_frame(1)), throwsArgumentError);
      await run.session.addFrame(_frame(3));
      expect(run.session.frames.map((frame) => frame.sequence), [
        BigInt.two,
        BigInt.from(3),
      ]);
    });
  });
}

/// Records a session's events, their kinds, and stream completion.
final class _Run {
  _Run(this.session) {
    subscription = session.events.listen(
      (event) {
        events.add(event);
        order.add(switch (event) {
          ProviderPartial() => 'partial',
          ProviderFinal() => 'final',
          ProviderRejected() => 'rejected',
          ProviderReadiness() => 'readiness',
          ProviderAmplitude() => 'amplitude',
          ProviderFailure() => 'failure',
        });
      },
      onDone: () {
        done = true;
        order.add('done');
      },
    );
    addTearDown(subscription.cancel);
  }

  final FakeProviderSession session;
  final List<ProviderEvent> events = [];
  final List<String> order = [];
  late final StreamSubscription<ProviderEvent> subscription;
  var done = false;

  List<String> get partials =>
      events.whereType<ProviderPartial>().map((event) => event.text).toList();

  /// The utterance: the exact concatenation of finals.
  String get transcript =>
      events.whereType<ProviderFinal>().map((event) => event.text).join();

  /// The hypothesis of the segment opened after the last commit.
  String get openHypothesis {
    var hypothesis = '';
    for (final event in events) {
      hypothesis = switch (event) {
        ProviderPartial(:final text) => text,
        ProviderFinal() || ProviderRejected() => '',
        _ => hypothesis,
      };
    }
    return hypothesis;
  }
}

Future<_Run> _started(FakeVoiceProvider provider) async {
  final run = _Run(provider.createSession(_request()));
  final start = run.session.start();
  if (run.session.startPending) run.session.completeStart();
  await start;
  return run;
}

FakeVoiceProvider _warmProvider({bool holdStart = false}) => FakeVoiceProvider(
  capabilities: {
    ProviderCapability.immediateMute,
    ProviderCapability.warmUnmute,
  },
  holdStart: holdStart,
);

ProviderSessionRequest _request({AudioFormat? format}) =>
    ProviderSessionRequest(sessionId: 'capture-1', format: format ?? _format());

AudioFormat _format({
  AudioEncoding encoding = AudioEncoding.pcmS16le,
  int channels = 1,
}) => AudioFormat(
  sampleRateHz: 16000,
  channels: channels,
  encoding: encoding,
  frameDurationMs: 10,
);

AudioFrame _frame(int sequence, {AudioFormat? format}) => AudioFrame(
  protocol: ProtocolVersion.current,
  sessionId: 'connector-session-1',
  sequence: BigInt.from(sequence),
  monotonicTimeUs: BigInt.from(sequence * 10000),
  format: format ?? _format(),
  payloadBase64: 'AAA=',
);

VoiceError _failure(String code, {bool retryable = true}) =>
    VoiceError(code: code, message: 'Synthetic failure.', retryable: retryable);

Matcher _voiceError(String code, {bool? retryable}) {
  var matcher = isA<VoiceError>().having((error) => error.code, 'code', code);
  if (retryable != null) {
    matcher = matcher.having(
      (error) => error.retryable,
      'retryable',
      retryable,
    );
  }
  return matcher;
}
