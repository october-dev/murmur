import 'dart:convert';
import 'dart:io';

import 'package:murmur_protocol/murmur_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('passes every manifest conformance set', () {
    final conformance = Directory('../../../conformance');
    final manifest = requireObject(
      jsonDecode(File('${conformance.path}/manifest.json').readAsStringSync()),
      'manifest',
    );
    final fixtureSets = manifest['fixtureSets']! as List<Object?>;
    for (final fixtureValue in fixtureSets) {
      final fixtureSet = requireObject(fixtureValue, 'fixture set');
      final name = fixtureSet['name']! as String;
      final message = fixtureSet['message']! as String;
      final lines = File(
        '${conformance.path}/${fixtureSet['path']}',
      ).readAsLinesSync().where((line) => line.trim().isNotEmpty).toList();
      expect(
        lines,
        hasLength(fixtureSet['lines']! as int),
        reason: 'dart · $name · count',
      );
      BigInt? previous;
      final rejectLine = fixtureSet['rejectLine'] as int? ?? 1;
      for (var index = 0; index < lines.length; index++) {
        final lineNumber = index + 1;
        final label = 'dart · $name · line $lineNumber';
        final input = requireObject(jsonDecode(lines[index]), message);
        Object parsed;
        try {
          parsed = _parse(message, input);
        } on Object catch (error) {
          final shouldReject =
              fixtureSet['expect'] == 'reject' &&
              fixtureSet['rejection'] == 'parse' &&
              lineNumber >= rejectLine;
          expect(shouldReject, isTrue, reason: '$label · $error');
          continue;
        }
        if (fixtureSet['expect'] == 'reject' &&
            fixtureSet['rejection'] == 'parse' &&
            lineNumber >= rejectLine) {
          fail('$label · expected ${fixtureSet['reason']}');
        }
        final current = _orderingKey(parsed);
        if (current != null) {
          final ordered = previous == null || current > previous;
          final rejectsOrder =
              fixtureSet['expect'] == 'reject' &&
              fixtureSet['rejection'] == 'order' &&
              lineNumber >= rejectLine;
          expect(
            ordered,
            !rejectsOrder,
            reason: '$label · ${fixtureSet['reason'] ?? 'ordering'}',
          );
          if (ordered) previous = current;
        }
        final expected = requireObject(jsonDecode(lines[index]), message);
        final actual = requireObject(
          jsonDecode(jsonEncode(_serialize(parsed))),
          message,
        );
        final unknownFields =
            fixtureSet['unknownFields'] as List<Object?>? ?? const [];
        for (final path in unknownFields.cast<String>()) {
          _removePath(expected, path);
          _removePath(actual, path);
        }
        expect(actual, equals(expected), reason: '$label · round-trip');
      }
    }
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

Object _parse(String message, Map<String, Object?> input) => switch (message) {
  'RuntimeEvent' => RuntimeEvent.fromJson(input),
  'SessionControl' => SessionControl.fromJson(input),
  'AudioFrame' => AudioFrame.fromJson(input),
  'VoiceSource' => VoiceSource.fromJson(input),
  _ => throw FormatException('unknown message $message'),
};

Map<String, Object?> _serialize(Object value) => switch (value) {
  final RuntimeEvent event => event.toJson(),
  final SessionControl control => control.toJson(),
  final AudioFrame frame => frame.toJson(),
  final VoiceSource source => source.toJson(),
  _ => throw FormatException('unknown parsed type ${value.runtimeType}'),
};

BigInt? _orderingKey(Object value) => switch (value) {
  final RuntimeEvent event => event.sequence,
  final SessionControl control => control.requestSequence,
  final AudioFrame frame => frame.sequence,
  _ => null,
};

void _removePath(Map<String, Object?> value, String path) {
  final parts = path.split('/');
  Map<String, Object?>? current = value;
  for (final part in parts.take(parts.length - 1)) {
    final next = current?[part];
    if (next is! Map<String, Object?>) return;
    current = next;
  }
  current?.remove(parts.last);
}
