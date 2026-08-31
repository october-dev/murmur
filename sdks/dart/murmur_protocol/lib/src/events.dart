import 'dart:convert';

import 'protocol.dart';

enum RuntimePayloadKind {
  sessionStateChanged('sessionStateChanged'),
  captureReadiness('captureReadiness'),
  audioLevel('audioLevel'),
  transcript('transcript'),
  error('error'),
  intentProposal('intentProposal'),
  confirmationRequest('confirmationRequest'),
  actionResult('actionResult');

  const RuntimePayloadKind(this.protoJsonField);

  final String protoJsonField;
}

/// A protocol event with a typed payload discriminator and lossless payload map.
///
/// Keeping the envelope model independent of generated protobuf classes lets
/// pure Dart and Flutter consumers use the same public API over in-process,
/// ProtoJSON, WebSocket, or generated-binary transports.
final class RuntimeEvent {
  RuntimeEvent({
    required this.protocol,
    required this.sessionId,
    required this.sequence,
    required this.monotonicTimeUs,
    required this.kind,
    required Map<String, Object?> payload,
  }) : payload = Map.unmodifiable(payload) {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (sequence < 0 || monotonicTimeUs < 0) {
      throw ArgumentError('sequence and monotonicTimeUs must be non-negative');
    }
  }

  final ProtocolVersion protocol;
  final String sessionId;
  final int sequence;
  final int monotonicTimeUs;
  final RuntimePayloadKind kind;
  final Map<String, Object?> payload;

  factory RuntimeEvent.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('runtime event must be a JSON object');
    }
    return RuntimeEvent.fromJson(decoded);
  }

  factory RuntimeEvent.fromJson(Map<String, Object?> json) {
    final protocolJson = json['protocol'];
    final sessionId = json['sessionId'];
    if (protocolJson is! Map<String, Object?> || sessionId is! String) {
      throw const FormatException(
        'runtime event requires protocol and sessionId',
      );
    }

    final sequence = _parseUint64(json['sequence'], 'sequence');
    final monotonicTimeUs = _parseUint64(
      json['monotonicTimeUs'],
      'monotonicTimeUs',
    );
    final present = RuntimePayloadKind.values
        .where((candidate) => json.containsKey(candidate.protoJsonField))
        .toList(growable: false);
    if (present.length != 1) {
      throw const FormatException(
        'runtime event must contain exactly one known payload',
      );
    }

    final kind = present.single;
    final value = json[kind.protoJsonField];
    if (value is! Map<String, Object?>) {
      throw FormatException('${kind.protoJsonField} must be an object');
    }
    _validatePayload(kind, value);

    return RuntimeEvent(
      protocol: ProtocolVersion.fromJson(protocolJson),
      sessionId: sessionId,
      sequence: sequence,
      monotonicTimeUs: monotonicTimeUs,
      kind: kind,
      payload: value,
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'sessionId': sessionId,
    // ProtoJSON encodes uint64 as strings to remain safe in JavaScript.
    'sequence': sequence.toString(),
    'monotonicTimeUs': monotonicTimeUs.toString(),
    kind.protoJsonField: payload,
  };

  String toJsonString() => jsonEncode(toJson());
}

int _parseUint64(Object? value, String field) {
  final parsed = switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };
  if (parsed == null || parsed < 0) {
    throw FormatException('$field must be a non-negative uint64 string');
  }
  return parsed;
}

void _validatePayload(RuntimePayloadKind kind, Map<String, Object?> payload) {
  if (kind == RuntimePayloadKind.transcript) {
    if (payload['kind'] is! String || payload['text'] is! String) {
      throw const FormatException('transcript requires kind and text');
    }
  }
  if (kind == RuntimePayloadKind.audioLevel) {
    final amplitude = payload['amplitude'];
    if (amplitude is! num || amplitude < 0 || amplitude > 1) {
      throw const FormatException(
        'audioLevel.amplitude must be between 0 and 1',
      );
    }
  }
}
