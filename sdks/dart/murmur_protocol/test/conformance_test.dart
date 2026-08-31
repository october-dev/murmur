import 'dart:convert';
import 'dart:io';

import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('parses and preserves every shared runtime event fixture', () {
    final fixtures = File(
      '../../../conformance/fixtures/runtime-events.jsonl',
    ).readAsLinesSync().where((line) => line.trim().isNotEmpty).toList();

    final events = fixtures.map(RuntimeEvent.fromJsonString).toList();

    expect(events, hasLength(7));
    expect(
      events.map((event) => event.sequence),
      orderedEquals(List.generate(7, (i) => i + 1)),
    );
    expect(events[3].kind, RuntimePayloadKind.transcript);
    expect(events[3].payload['text'], 'synthetic hello');
    expect(events[5].kind, RuntimePayloadKind.intentProposal);

    for (var index = 0; index < events.length; index++) {
      expect(
        jsonDecode(events[index].toJsonString()),
        jsonDecode(fixtures[index]),
      );
    }
  });

  test('rejects unknown or ambiguous payloads', () {
    const base = <String, Object?>{
      'protocol': {'major': 1, 'minor': 0},
      'sessionId': 'test',
      'sequence': '1',
      'monotonicTimeUs': '1',
    };

    expect(
      () =>
          RuntimeEvent.fromJson({...base, 'unknownEvent': <String, Object?>{}}),
      throwsFormatException,
    );
    expect(
      () => RuntimeEvent.fromJson({
        ...base,
        'captureReadiness': {'live': true},
        'audioLevel': {'amplitude': 0.5},
      }),
      throwsFormatException,
    );
  });

  test('models a source without Flutter or a connector SDK', () {
    final source = VoiceSource(
      id: 'synthetic-1',
      displayName: 'Synthetic microphone',
      transport: VoiceSourceTransport.synthetic,
      capabilities: {VoiceSourceCapability.liveAudio},
    );

    expect(source.supports(VoiceSourceCapability.liveAudio), isTrue);
    expect(source.supports(VoiceSourceCapability.battery), isFalse);
  });
}
