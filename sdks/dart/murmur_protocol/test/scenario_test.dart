import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:test/test.dart';

import 'support/fake_connector.dart';
import 'support/fake_provider.dart';

/// Replays every `scenarioSets` fixture through the coordinator.
///
/// Driver steps act on the in-process connector and provider boundary; each
/// `emit` step must match the next coordinator event exactly, and no event may
/// appear where the fixture does not expect one.
void main() {
  final conformance = Directory('../../../conformance');
  final manifest = requireObject(
    jsonDecode(File('${conformance.path}/manifest.json').readAsStringSync()),
    'manifest',
  );
  test('dart · scenario manifest version', () {
    expect(manifest['scenarioManifestVersion'], 1);
  });
  final timeoutsMs = requireObject(
    manifest['scenarioTimeoutsMs'],
    'scenarioTimeoutsMs',
  );
  final timeouts = CaptureTimeouts(
    startup: _ms(timeoutsMs, 'startup'),
    endpoint: _ms(timeoutsMs, 'endpoint'),
    finalize: _ms(timeoutsMs, 'finalize'),
    shutdown: _ms(timeoutsMs, 'shutdown'),
    warmHold: _ms(timeoutsMs, 'warmHold'),
  );

  for (final value in manifest['scenarioSets']! as List<Object?>) {
    final scenario = requireObject(value, 'scenario set');
    final name = scenario['name']! as String;
    test('dart · scenario · $name', () async {
      final lines = File(
        '${conformance.path}/${scenario['path']}',
      ).readAsLinesSync().where((line) => line.trim().isNotEmpty).toList();
      expect(lines, hasLength(scenario['steps']! as int), reason: 'count');
      final capabilities = (scenario['providerCapabilities'] as List<Object?>)
          .map((item) => ProviderCapability.values.byName(item! as String))
          .toSet();
      final driver = _Driver(capabilities: capabilities, timeouts: timeouts);
      for (var index = 0; index < lines.length; index++) {
        final step = requireObject(jsonDecode(lines[index]), 'step');
        expect(step.keys, hasLength(1), reason: 'step ${index + 1}');
        final kind = step.keys.single;
        final args = requireObject(step[kind], kind);
        await driver.perform(kind, args, 'step ${index + 1} · $kind');
      }
      expect(driver.emitted, isEmpty, reason: 'unexpected trailing events');
      expect(driver.utterances, scenario['utterances']);
      expect(driver.scheduler.pendingTimers, 0, reason: 'timers left behind');
    });
  }
}

Duration _ms(Map<String, Object?> json, String field) =>
    Duration(milliseconds: json[field]! as int);

final class _Driver {
  _Driver({
    required Set<ProviderCapability> capabilities,
    required CaptureTimeouts timeouts,
  }) : connector = FakeConnector(),
       provider = FakeProvider(capabilities: capabilities),
       scheduler = ManualScheduler() {
    var sessions = 0;
    coordinator = VoiceCaptureCoordinator(
      connector,
      provider,
      onUtteranceFinalized: utterances.add,
      timeouts: timeouts,
      sessionIdFactory: () => 'session-${++sessions}',
      scheduler: scheduler,
    );
    coordinator.events.listen((event) => emitted.add(event.toJson()));
  }

  final FakeConnector connector;
  final FakeProvider provider;
  final ManualScheduler scheduler;
  late final VoiceCaptureCoordinator coordinator;
  final List<Map<String, Object?>> emitted = [];
  final List<String> utterances = [];

  Future<void> perform(
    String kind,
    Map<String, Object?> args,
    String label,
  ) async {
    if (kind == 'emit') {
      expect(emitted, isNotEmpty, reason: '$label · no event was emitted');
      expect(emitted.removeAt(0), equals(args), reason: label);
      return;
    }
    expect(emitted, isEmpty, reason: '$label · unexpected event before step');
    switch (kind) {
      case 'start':
        final mode = CaptureMode.values.firstWhere(
          (candidate) => candidate.protoJsonName == args['mode'],
        );
        coordinator.start(source: fakeSource(), mode: mode).ignore();
      case 'release':
        coordinator.release().ignore();
      case 'finalize':
        coordinator.finalize().ignore();
      case 'stop':
        coordinator.stop().ignore();
      case 'connect_ok':
        connector.completeConnect();
      case 'connect_fail':
        connector.failConnect(_error(args));
      case 'provider_open_ok':
        provider.completeOpen();
      case 'provider_open_fail':
        provider.failOpen(_error(args));
      case 'frame':
        final delivered = connector.latestSession.emitFrame(
          args['seq']! as int,
          silent: args['silent'] as bool? ?? false,
        );
        expect(delivered, isTrue, reason: '$label · session not listening');
      case 'partial':
        provider.latestSession.emit(ProviderPartial(args['text']! as String));
      case 'final':
        provider.latestSession.emit(ProviderFinal(args['text']! as String));
      case 'rejected':
        provider.latestSession.emit(ProviderRejected(args['text']! as String));
      case 'readiness':
        provider.latestSession.emit(
          ProviderReadiness(live: args['live']! as bool),
        );
      case 'amplitude':
        provider.latestSession.emit(
          ProviderAmplitude((args['value']! as num).toDouble()),
        );
      case 'provider_closed':
        final session = provider.latestSession;
        final expected = args['expected']! as bool;
        session.emit(ProviderClosed(expected: expected));
        if (expected && session.finalizePending) session.completeFinalize();
      case 'provider_failed':
        provider.latestSession.emit(ProviderFailure(_error(args)));
      case 'provider_flushed':
        provider.latestSession.completeFlush();
      case 'advanceMs':
        scheduler.advance(Duration(milliseconds: args['ms']! as int));
      default:
        fail('$label · unknown step');
    }
    await pumpEventQueue();
  }
}

VoiceError _error(Map<String, Object?> args) {
  final error = requireObject(args['error'], 'error');
  return VoiceError(
    code: error['code']! as String,
    message: error['message']! as String,
    retryable: error['retryable']! as bool,
  );
}
