import 'dart:convert';

import 'protocol.dart';
import 'source.dart';

/// An audio sample or packet encoding supported by `murmur.v1`.
enum AudioEncoding {
  /// Little-endian signed 16-bit PCM samples.
  pcmS16le('AUDIO_ENCODING_PCM_S16LE'),

  /// Little-endian 32-bit floating-point PCM samples.
  pcmF32le('AUDIO_ENCODING_PCM_F32LE'),

  /// Opus-encoded audio packets.
  opus('AUDIO_ENCODING_OPUS');

  const AudioEncoding(this.protoJsonName);

  /// The `murmur.v1` ProtoJSON enum name.
  final String protoJsonName;
}

/// The capture policy requested for a session on the wire.
enum CaptureMode {
  /// No capture policy was specified.
  unspecified('CAPTURE_MODE_UNSPECIFIED'),

  /// Capture starts and stops on separate explicit actions.
  tapToSpeak('CAPTURE_MODE_TAP_TO_SPEAK'),

  /// Capture remains active while an input action is held.
  holdToTalk('CAPTURE_MODE_HOLD_TO_TALK'),

  /// Capture continues without a held input action.
  handsFree('CAPTURE_MODE_HANDS_FREE'),

  /// Capture starts after a wake phrase is detected.
  wakePhrase('CAPTURE_MODE_WAKE_PHRASE');

  const CaptureMode(this.protoJsonName);

  /// The `murmur.v1` ProtoJSON enum name.
  final String protoJsonName;
}

/// A validated `murmur.v1` audio format.
final class AudioFormat {
  /// Creates an audio format.
  ///
  /// [sampleRateHz] and [channels] must be between 1 and 2^32 - 1.
  /// [frameDurationMs], when present, must be between 0 and 2^32 - 1.
  AudioFormat({
    required this.sampleRateHz,
    required this.channels,
    required this.encoding,
    this.frameDurationMs,
  }) {
    parseUint32(sampleRateHz, 'sampleRateHz');
    parseUint32(channels, 'channels');
    if (sampleRateHz < 1) {
      throw const FormatException('sampleRateHz must be at least 1');
    }
    if (channels < 1) {
      throw const FormatException('channels must be at least 1');
    }
    final duration = frameDurationMs;
    if (duration != null) {
      parseUint32(duration, 'frameDurationMs');
    }
  }

  /// Samples per channel per second.
  final int sampleRateHz;

  /// Number of interleaved audio channels.
  final int channels;

  /// Encoding used by audio payloads in this format.
  final AudioEncoding encoding;

  /// Duration represented by each frame, or `null` when it is not specified.
  final int? frameDurationMs;

  /// Parses and validates a `murmur.v1.AudioFormat` ProtoJSON object.
  factory AudioFormat.fromJson(Map<String, Object?> json) {
    return AudioFormat(
      sampleRateHz: parseUint32(json['sampleRateHz'], 'sampleRateHz'),
      channels: parseUint32(json['channels'], 'channels'),
      encoding: _audioEncodingFromWire(json['encoding']),
      frameDurationMs: json.containsKey('frameDurationMs')
          ? parseUint32(json['frameDurationMs'], 'frameDurationMs')
          : null,
    );
  }

  /// Serializes this format using `murmur.v1` ProtoJSON field names.
  Map<String, Object?> toJson() {
    final result = <String, Object?>{
      'sampleRateHz': sampleRateHz,
      'channels': channels,
      'encoding': encoding.protoJsonName,
    };
    final duration = frameDurationMs;
    if (duration != null) {
      result['frameDurationMs'] = duration;
    }
    return result;
  }
}

/// A typed `murmur.v1.SessionControl` command body.
sealed class SessionCommand {
  /// Creates a typed session command.
  const SessionCommand();

  /// The command's field name in a `SessionControl` ProtoJSON object.
  String get protoJsonField;

  /// Serializes the command body using `murmur.v1` ProtoJSON field names.
  Map<String, Object?> toJson();
}

/// Requests that a session start capture.
final class StartSession extends SessionCommand {
  /// Creates a start command containing only the supplied fields.
  const StartSession({this.source, this.mode, this.requestedFormat});

  /// The source to capture, or `null` when selected out of band.
  final VoiceSource? source;

  /// The requested capture policy, or `null` when selected out of band.
  final CaptureMode? mode;

  /// The requested format, or `null` when the connector should negotiate it.
  final AudioFormat? requestedFormat;

  @override
  String get protoJsonField => 'start';

  @override
  Map<String, Object?> toJson() {
    final result = <String, Object?>{};
    final commandSource = source;
    if (commandSource != null) {
      result['source'] = commandSource.toJson();
    }
    final commandMode = mode;
    if (commandMode != null) {
      result['mode'] = commandMode.protoJsonName;
    }
    final format = requestedFormat;
    if (format != null) {
      result['requestedFormat'] = format.toJson();
    }
    return result;
  }
}

/// Requests that a session stop and release its resources.
final class StopSession extends SessionCommand {
  /// Creates a stop command containing [reason] only when it is supplied.
  const StopSession({this.reason});

  /// An optional human-readable reason for stopping.
  final String? reason;

  @override
  String get protoJsonField => 'stop';

  @override
  Map<String, Object?> toJson() {
    final result = <String, Object?>{};
    final stopReason = reason;
    if (stopReason != null) {
      result['reason'] = stopReason;
    }
    return result;
  }
}

/// Opens or closes a session's input gate.
final class SetInputGate extends SessionCommand {
  /// Creates an input-gate command containing only the supplied fields.
  const SetInputGate({this.open, this.flushAcceptedAudio});

  /// Whether the input gate should be open, or `null` when omitted.
  final bool? open;

  /// Whether already accepted audio may finish, or `null` when omitted.
  final bool? flushAcceptedAudio;

  @override
  String get protoJsonField => 'inputGate';

  @override
  Map<String, Object?> toJson() {
    final result = <String, Object?>{};
    final isOpen = open;
    if (isOpen != null) {
      result['open'] = isOpen;
    }
    final flush = flushAcceptedAudio;
    if (flush != null) {
      result['flushAcceptedAudio'] = flush;
    }
    return result;
  }
}

/// Requests finalization of audio already accepted by a session.
final class FinalizeSession extends SessionCommand {
  /// Creates an empty finalization command.
  const FinalizeSession();

  @override
  String get protoJsonField => 'finalize';

  @override
  Map<String, Object?> toJson() => const {};
}

/// A typed `murmur.v1.SessionControl` wire message.
final class SessionControl {
  /// Creates a session-control message.
  SessionControl({
    required this.protocol,
    required this.sessionId,
    required this.requestSequence,
    required this.command,
  });

  /// The wire-protocol version.
  final ProtocolVersion protocol;

  /// The identifier of the target session.
  final String sessionId;

  /// The session-scoped ordering key for control requests.
  final BigInt requestSequence;

  /// The typed command carried by this message.
  final SessionCommand command;

  /// Decodes a session-control message from ProtoJSON text.
  factory SessionControl.fromJsonString(String source) {
    return SessionControl.fromJson(
      requireObject(jsonDecode(source), 'session control'),
    );
  }

  /// Parses a session-control message from a ProtoJSON object.
  factory SessionControl.fromJson(Map<String, Object?> json) {
    const commandFields = ['start', 'stop', 'inputGate', 'finalize'];
    final present = commandFields
        .where(json.containsKey)
        .toList(growable: false);
    if (present.length != 1) {
      throw const FormatException(
        'session control must contain exactly one known command',
      );
    }
    final field = present.single;
    final body = requireObject(json[field], field);
    return SessionControl(
      protocol: ProtocolVersion.fromJson(
        requireObject(json['protocol'], 'protocol'),
      ),
      sessionId: requireNonEmptyString(json['sessionId'], 'sessionId'),
      requestSequence: parseUint64(json['requestSequence'], 'requestSequence'),
      command: _sessionCommandFromJson(field, body),
    );
  }

  /// Serializes this message using `murmur.v1` ProtoJSON field names.
  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'sessionId': sessionId,
    'requestSequence': requestSequence.toString(),
    command.protoJsonField: command.toJson(),
  };
}

/// A typed `murmur.v1.AudioFrame` wire message.
final class AudioFrame {
  /// Creates an audio-frame message.
  AudioFrame({
    required this.protocol,
    required this.sessionId,
    required this.sequence,
    required this.monotonicTimeUs,
    required this.format,
    required this.payloadBase64,
  });

  /// The wire-protocol version.
  final ProtocolVersion protocol;

  /// The identifier of the session that produced the frame.
  final String sessionId;

  /// A session-scoped ordering key.
  final BigInt sequence;

  /// Elapsed microseconds on the producing host's monotonic clock.
  ///
  /// This is not a UTC timestamp and cannot be compared across hosts or
  /// sessions.
  final BigInt monotonicTimeUs;

  /// The encoding and layout of [payloadBase64].
  final AudioFormat format;

  /// The ProtoJSON base64 payload exactly as it was supplied.
  final String payloadBase64;

  /// Decodes an audio-frame message from ProtoJSON text.
  factory AudioFrame.fromJsonString(String source) {
    return AudioFrame.fromJson(
      requireObject(jsonDecode(source), 'audio frame'),
    );
  }

  /// Parses and validates an audio-frame message from a ProtoJSON object.
  factory AudioFrame.fromJson(Map<String, Object?> json) {
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
      format: AudioFormat.fromJson(requireObject(json['format'], 'format')),
      payloadBase64: payload,
    );
  }

  /// Serializes this message using `murmur.v1` ProtoJSON field names.
  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'sessionId': sessionId,
    'sequence': sequence.toString(),
    'monotonicTimeUs': monotonicTimeUs.toString(),
    'format': format.toJson(),
    'payload': payloadBase64,
  };
}

AudioEncoding _audioEncodingFromWire(Object? value) {
  for (final encoding in AudioEncoding.values) {
    if (encoding.protoJsonName == value) return encoding;
  }
  throw const FormatException('encoding must be a known non-unspecified name');
}

CaptureMode _captureModeFromWire(Object? value) {
  for (final mode in CaptureMode.values) {
    if (mode.protoJsonName == value) return mode;
  }
  throw const FormatException('start.mode must be a known enum name');
}

SessionCommand _sessionCommandFromJson(
  String field,
  Map<String, Object?> body,
) {
  return switch (field) {
    'start' => StartSession(
      source: body.containsKey('source')
          ? VoiceSource.fromJson(requireObject(body['source'], 'start.source'))
          : null,
      mode: body.containsKey('mode')
          ? _captureModeFromWire(body['mode'])
          : null,
      requestedFormat: body.containsKey('requestedFormat')
          ? AudioFormat.fromJson(
              requireObject(body['requestedFormat'], 'start.requestedFormat'),
            )
          : null,
    ),
    'stop' => StopSession(
      reason: body.containsKey('reason')
          ? _requireString(body['reason'], 'stop.reason')
          : null,
    ),
    'inputGate' => SetInputGate(
      open: body.containsKey('open')
          ? _requireBool(body['open'], 'open')
          : null,
      flushAcceptedAudio: body.containsKey('flushAcceptedAudio')
          ? _requireBool(body['flushAcceptedAudio'], 'flushAcceptedAudio')
          : null,
    ),
    'finalize' => const FinalizeSession(),
    _ => throw FormatException('unknown session command $field'),
  };
}

String _requireString(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be a string');
  }
  return value;
}

bool _requireBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('$field must be a boolean');
  }
  return value;
}
