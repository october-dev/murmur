import 'dart:convert';

import 'protocol.dart';
import 'source.dart';

enum SessionCommandKind {
  start('start'),
  stop('stop'),
  inputGate('inputGate'),
  finalize('finalize');

  const SessionCommandKind(this.protoJsonField);

  final String protoJsonField;
}

final class SessionControl {
  SessionControl({
    required this.protocol,
    required this.sessionId,
    required this.requestSequence,
    required this.kind,
    required Map<String, Object?> body,
  }) : body = Map.unmodifiable(body);

  final ProtocolVersion protocol;
  final String sessionId;
  final BigInt requestSequence;
  final SessionCommandKind kind;
  final Map<String, Object?> body;

  factory SessionControl.fromJsonString(String source) {
    return SessionControl.fromJson(
      requireObject(jsonDecode(source), 'session control'),
    );
  }

  factory SessionControl.fromJson(Map<String, Object?> json) {
    final present = SessionCommandKind.values
        .where((candidate) => json.containsKey(candidate.protoJsonField))
        .toList(growable: false);
    if (present.length != 1) {
      throw const FormatException(
        'session control must contain exactly one known command',
      );
    }
    final kind = present.single;
    final body = requireObject(json[kind.protoJsonField], kind.protoJsonField);
    _validateSessionBody(kind, body);
    return SessionControl(
      protocol: ProtocolVersion.fromJson(
        requireObject(json['protocol'], 'protocol'),
      ),
      sessionId: requireNonEmptyString(json['sessionId'], 'sessionId'),
      requestSequence: parseUint64(json['requestSequence'], 'requestSequence'),
      kind: kind,
      body: body,
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'sessionId': sessionId,
    'requestSequence': requestSequence.toString(),
    kind.protoJsonField: body,
  };
}

final class AudioFrame {
  AudioFrame({
    required this.protocol,
    required this.sessionId,
    required this.sequence,
    required this.monotonicTimeUs,
    required Map<String, Object?> format,
    required this.payloadBase64,
  }) : format = Map.unmodifiable(format);

  final ProtocolVersion protocol;
  final String sessionId;
  final BigInt sequence;
  final BigInt monotonicTimeUs;
  final Map<String, Object?> format;
  final String payloadBase64;

  factory AudioFrame.fromJsonString(String source) {
    return AudioFrame.fromJson(
      requireObject(jsonDecode(source), 'audio frame'),
    );
  }

  factory AudioFrame.fromJson(Map<String, Object?> json) {
    final format = requireObject(json['format'], 'format');
    validateAudioFormat(format);
    final payload = json['payload'];
    if (payload is! String || !isValidBase64(payload)) {
      throw const FormatException('payload must use valid base64 grammar');
    }
    return AudioFrame(
      protocol: ProtocolVersion.fromJson(
        requireObject(json['protocol'], 'protocol'),
      ),
      sessionId: requireNonEmptyString(json['sessionId'], 'sessionId'),
      sequence: parseUint64(json['sequence'], 'sequence'),
      monotonicTimeUs: parseUint64(json['monotonicTimeUs'], 'monotonicTimeUs'),
      format: format,
      payloadBase64: payload,
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'sessionId': sessionId,
    'sequence': sequence.toString(),
    'monotonicTimeUs': monotonicTimeUs.toString(),
    'format': format,
    'payload': payloadBase64,
  };
}

void validateAudioFormat(Map<String, Object?> format) {
  if (parseUint32(format['sampleRateHz'], 'sampleRateHz') < 1) {
    throw const FormatException('sampleRateHz must be at least 1');
  }
  if (parseUint32(format['channels'], 'channels') < 1) {
    throw const FormatException('channels must be at least 1');
  }
  const encodings = {
    'AUDIO_ENCODING_PCM_S16LE',
    'AUDIO_ENCODING_PCM_F32LE',
    'AUDIO_ENCODING_OPUS',
  };
  if (!encodings.contains(format['encoding'])) {
    throw const FormatException(
      'encoding must be a known non-unspecified name',
    );
  }
  if (format.containsKey('frameDurationMs')) {
    parseUint32(format['frameDurationMs'], 'frameDurationMs');
  }
}

void _validateSessionBody(SessionCommandKind kind, Map<String, Object?> body) {
  if (kind == SessionCommandKind.inputGate) {
    for (final field in ['open', 'flushAcceptedAudio']) {
      if (body.containsKey(field) && body[field] is! bool) {
        throw FormatException('$field must be a boolean');
      }
    }
  } else if (kind == SessionCommandKind.stop &&
      body.containsKey('reason') &&
      body['reason'] is! String) {
    throw const FormatException('stop.reason must be a string');
  } else if (kind == SessionCommandKind.start) {
    if (body.containsKey('mode')) {
      const modes = {
        'CAPTURE_MODE_UNSPECIFIED',
        'CAPTURE_MODE_TAP_TO_SPEAK',
        'CAPTURE_MODE_HOLD_TO_TALK',
        'CAPTURE_MODE_HANDS_FREE',
        'CAPTURE_MODE_WAKE_PHRASE',
      };
      if (!modes.contains(body['mode'])) {
        throw const FormatException('start.mode must be a known enum name');
      }
    }
    if (body.containsKey('source')) {
      VoiceSource.fromJson(requireObject(body['source'], 'start.source'));
    }
    if (body.containsKey('requestedFormat')) {
      validateAudioFormat(
        requireObject(body['requestedFormat'], 'start.requestedFormat'),
      );
    }
  }
}
