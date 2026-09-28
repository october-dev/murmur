import 'dart:convert';

import 'protocol.dart';
import 'validation.dart';

/// The payload arms of a `murmur.v1.EngineEvent`.
enum EnginePayloadKind {
  engineStatus('engineStatus'),
  voicePackStatus('voicePackStatus'),
  microphoneStatus('microphoneStatus'),
  speechOutput('speechOutput'),
  error('error');

  const EnginePayloadKind(this.protoJsonField);

  final String protoJsonField;
}

/// An engine-scoped protocol event with a typed payload discriminator and a
/// lossless payload map.
///
/// [engineId] is the routing key and ordering scope: [sequence] strictly
/// increases per engine.
final class EngineEvent {
  EngineEvent({
    required this.protocol,
    required this.engineId,
    required this.sequence,
    required this.monotonicTimeUs,
    required this.kind,
    required Map<String, Object?> payload,
  }) : payload = Map.unmodifiable(payload) {
    if (engineId.trim().isEmpty) {
      throw ArgumentError.value(engineId, 'engineId', 'must not be empty');
    }
    if (sequence < BigInt.zero || monotonicTimeUs < BigInt.zero) {
      throw ArgumentError('sequence and monotonicTimeUs must be non-negative');
    }
  }

  final ProtocolVersion protocol;
  final String engineId;
  final BigInt sequence;
  final BigInt monotonicTimeUs;
  final EnginePayloadKind kind;
  final Map<String, Object?> payload;

  factory EngineEvent.fromJsonString(String source) {
    return EngineEvent.fromJson(
      requireObject(jsonDecode(source), 'engine event'),
    );
  }

  factory EngineEvent.fromJson(Map<String, Object?> json) {
    final present = EnginePayloadKind.values
        .where((candidate) => json.containsKey(candidate.protoJsonField))
        .toList(growable: false);
    if (present.length != 1) {
      throw const FormatException(
        'engine event must contain exactly one known payload',
      );
    }
    final kind = present.single;
    final value = requireObject(json[kind.protoJsonField], kind.protoJsonField);
    _validateEnginePayload(kind, value);
    return EngineEvent(
      protocol: ProtocolVersion.fromJson(
        requireObject(json['protocol'], 'protocol'),
      ),
      engineId: requireNonEmptyString(json['engineId'], 'engineId'),
      sequence: parseUint64(json['sequence'], 'sequence'),
      monotonicTimeUs: parseUint64(json['monotonicTimeUs'], 'monotonicTimeUs'),
      kind: kind,
      payload: value,
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'engineId': engineId,
    'sequence': sequence.toString(),
    'monotonicTimeUs': monotonicTimeUs.toString(),
    kind.protoJsonField: payload,
  };

  String toJsonString() => jsonEncode(toJson());
}

/// What a voice-pack request asks the engine to do.
enum VoicePackAction {
  /// Install and load the pack; a no-op when it is already ready.
  prepare('VOICE_PACK_ACTION_PREPARE'),

  /// Prepare again after a retryable failure.
  retry('VOICE_PACK_ACTION_RETRY'),

  /// Verify every component and re-fetch damaged ones.
  repair('VOICE_PACK_ACTION_REPAIR');

  const VoicePackAction(this.protoJsonName);

  /// The `murmur.v1` ProtoJSON enum name.
  final String protoJsonName;
}

/// A typed `murmur.v1.EngineControl` command body.
sealed class EngineCommand {
  /// Creates a typed engine command.
  const EngineCommand();

  /// The command's field name in an `EngineControl` ProtoJSON object.
  String get protoJsonField;

  /// Serializes the command body using `murmur.v1` ProtoJSON field names.
  Map<String, Object?> toJson();
}

/// Requests an action on a voice pack.
final class VoicePackRequest extends EngineCommand {
  /// Creates a voice-pack request.
  const VoicePackRequest({required this.packId, required this.action});

  /// The engine-assigned pack identifier.
  final String packId;

  /// The requested action.
  final VoicePackAction action;

  @override
  String get protoJsonField => 'voicePack';

  @override
  Map<String, Object?> toJson() => {
    'packId': packId,
    'action': action.protoJsonName,
  };
}

/// Requests speech output.
final class SpeakRequest extends EngineCommand {
  /// Creates a speak request containing optional fields only when supplied.
  const SpeakRequest({
    required this.outputId,
    required this.text,
    this.fullDuplex,
    this.echoClearanceMs,
  });

  /// The host-assigned identifier that correlates status events.
  final String outputId;

  /// The text to speak.
  final String text;

  /// Whether recognition input stays open during playback, or `null` when
  /// omitted (half duplex).
  final bool? fullDuplex;

  /// The echo tail in milliseconds, or `null` when omitted (engine default).
  final int? echoClearanceMs;

  @override
  String get protoJsonField => 'speak';

  @override
  Map<String, Object?> toJson() {
    final result = <String, Object?>{'outputId': outputId, 'text': text};
    final duplex = fullDuplex;
    if (duplex != null) {
      result['fullDuplex'] = duplex;
    }
    final clearance = echoClearanceMs;
    if (clearance != null) {
      result['echoClearanceMs'] = clearance;
    }
    return result;
  }
}

/// Cancels a speech output; idempotent.
final class CancelSpeech extends EngineCommand {
  /// Creates a cancellation for [outputId].
  const CancelSpeech({required this.outputId});

  /// The identifier of the output to cancel.
  final String outputId;

  @override
  String get protoJsonField => 'cancelSpeech';

  @override
  Map<String, Object?> toJson() => {'outputId': outputId};
}

/// A typed `murmur.v1.EngineControl` wire message.
final class EngineControl {
  /// Creates an engine-control message.
  EngineControl({
    required this.protocol,
    required this.engineId,
    required this.requestSequence,
    required this.command,
  });

  /// The wire-protocol version.
  final ProtocolVersion protocol;

  /// The identifier of the target engine.
  final String engineId;

  /// The engine-scoped ordering key for control requests.
  final BigInt requestSequence;

  /// The typed command carried by this message.
  final EngineCommand command;

  /// Decodes an engine-control message from ProtoJSON text.
  factory EngineControl.fromJsonString(String source) {
    return EngineControl.fromJson(
      requireObject(jsonDecode(source), 'engine control'),
    );
  }

  /// Parses an engine-control message from a ProtoJSON object.
  factory EngineControl.fromJson(Map<String, Object?> json) {
    const commandFields = ['voicePack', 'speak', 'cancelSpeech'];
    final present = commandFields
        .where(json.containsKey)
        .toList(growable: false);
    if (present.length != 1) {
      throw const FormatException(
        'engine control must contain exactly one known command',
      );
    }
    final field = present.single;
    final body = requireObject(json[field], field);
    return EngineControl(
      protocol: ProtocolVersion.fromJson(
        requireObject(json['protocol'], 'protocol'),
      ),
      engineId: requireNonEmptyString(json['engineId'], 'engineId'),
      requestSequence: parseUint64(json['requestSequence'], 'requestSequence'),
      command: _engineCommandFromJson(field, body),
    );
  }

  /// Serializes this message using `murmur.v1` ProtoJSON field names.
  Map<String, Object?> toJson() => {
    'protocol': protocol.toJson(),
    'engineId': engineId,
    'requestSequence': requestSequence.toString(),
    command.protoJsonField: command.toJson(),
  };
}

EngineCommand _engineCommandFromJson(String field, Map<String, Object?> body) {
  return switch (field) {
    'voicePack' => VoicePackRequest(
      packId: requireNonEmptyString(body['packId'], 'voicePack.packId'),
      action: _voicePackActionFromWire(body['action']),
    ),
    'speak' => SpeakRequest(
      outputId: requireNonEmptyString(body['outputId'], 'speak.outputId'),
      text: requireNonEmptyString(body['text'], 'speak.text'),
      fullDuplex: body.containsKey('fullDuplex')
          ? _requireBool(body['fullDuplex'], 'speak.fullDuplex')
          : null,
      echoClearanceMs: body.containsKey('echoClearanceMs')
          ? parseUint32(body['echoClearanceMs'], 'speak.echoClearanceMs')
          : null,
    ),
    'cancelSpeech' => CancelSpeech(
      outputId: requireNonEmptyString(
        body['outputId'],
        'cancelSpeech.outputId',
      ),
    ),
    _ => throw FormatException('unknown engine command $field'),
  };
}

VoicePackAction _voicePackActionFromWire(Object? value) {
  for (final action in VoicePackAction.values) {
    if (action.protoJsonName == value) return action;
  }
  throw const FormatException('voicePack.action must be a known action');
}

bool _requireBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('$field must be a boolean');
  }
  return value;
}

const _engineLocalities = {
  'ENGINE_LOCALITY_UNSPECIFIED',
  'ENGINE_LOCALITY_ON_DEVICE',
  'ENGINE_LOCALITY_REMOTE',
};
const _enginePlatforms = {
  'ENGINE_PLATFORM_UNSPECIFIED',
  'ENGINE_PLATFORM_MACOS',
  'ENGINE_PLATFORM_WINDOWS',
  'ENGINE_PLATFORM_LINUX',
  'ENGINE_PLATFORM_IOS',
  'ENGINE_PLATFORM_ANDROID',
};
const _engineReadiness = {
  'ENGINE_READINESS_UNSPECIFIED',
  'ENGINE_READINESS_NOT_READY',
  'ENGINE_READINESS_PREPARING',
  'ENGINE_READINESS_READY',
  'ENGINE_READINESS_FAILED',
};
const _voicePackStates = {
  'VOICE_PACK_STATE_UNSPECIFIED',
  'VOICE_PACK_STATE_NOT_INSTALLED',
  'VOICE_PACK_STATE_PREPARING',
  'VOICE_PACK_STATE_REPAIRING',
  'VOICE_PACK_STATE_READY',
  'VOICE_PACK_STATE_FAILED',
  'VOICE_PACK_STATE_UNSUPPORTED',
};
const _voicePackComponentKinds = {
  'VOICE_PACK_COMPONENT_KIND_UNSPECIFIED',
  'VOICE_PACK_COMPONENT_KIND_TRANSCRIPTION',
  'VOICE_PACK_COMPONENT_KIND_VOICE_ACTIVITY',
  'VOICE_PACK_COMPONENT_KIND_SPEECH_OUTPUT',
  'VOICE_PACK_COMPONENT_KIND_WAKE_PHRASE',
  'VOICE_PACK_COMPONENT_KIND_SPEAKER_VERIFICATION',
};
const _microphonePermissions = {
  'MICROPHONE_PERMISSION_UNSPECIFIED',
  'MICROPHONE_PERMISSION_NOT_DETERMINED',
  'MICROPHONE_PERMISSION_GRANTED',
  'MICROPHONE_PERMISSION_DENIED',
  'MICROPHONE_PERMISSION_RESTRICTED',
};
const _microphoneRoutes = {
  'MICROPHONE_ROUTE_UNSPECIFIED',
  'MICROPHONE_ROUTE_BUILT_IN',
  'MICROPHONE_ROUTE_WIRED',
  'MICROPHONE_ROUTE_BLUETOOTH',
  'MICROPHONE_ROUTE_USB',
  'MICROPHONE_ROUTE_VIRTUAL',
};
const _microphoneReadiness = {
  'MICROPHONE_READINESS_UNSPECIFIED',
  'MICROPHONE_READINESS_UNAVAILABLE',
  'MICROPHONE_READINESS_WARMING',
  'MICROPHONE_READINESS_READY',
  'MICROPHONE_READINESS_INTERRUPTED',
};
const _microphoneInterruptions = {
  'MICROPHONE_INTERRUPTION_UNSPECIFIED',
  'MICROPHONE_INTERRUPTION_SYSTEM',
  'MICROPHONE_INTERRUPTION_OTHER_APPLICATION',
  'MICROPHONE_INTERRUPTION_DEVICE_REMOVED',
};
const _speechOutputStates = {
  'SPEECH_OUTPUT_STATE_UNSPECIFIED',
  'SPEECH_OUTPUT_STATE_PREPARING',
  'SPEECH_OUTPUT_STATE_SPEAKING',
  'SPEECH_OUTPUT_STATE_ECHO_CLEARING',
  'SPEECH_OUTPUT_STATE_COMPLETED',
  'SPEECH_OUTPUT_STATE_CANCELLED',
  'SPEECH_OUTPUT_STATE_FAILED',
};

void _validateEnginePayload(
  EnginePayloadKind kind,
  Map<String, Object?> payload,
) {
  switch (kind) {
    case EnginePayloadKind.engineStatus:
      final engine = requireObject(payload['engine'], 'engineStatus.engine');
      final readiness = requireSpecifiedEnumName(
        payload['readiness'],
        _engineReadiness,
        'engineStatus.readiness',
      );
      final locality = requireSpecifiedEnumName(
        engine['locality'],
        _engineLocalities,
        'engine.locality',
      );
      if (locality == 'ENGINE_LOCALITY_ON_DEVICE') {
        requireSpecifiedEnumName(
          engine['platform'],
          _enginePlatforms,
          'engine.platform',
        );
      } else if (engine.containsKey('platform')) {
        requireEnumName(
          engine['platform'],
          _enginePlatforms,
          'engine.platform',
        );
      }
      final capabilities = requireList(
        fieldOr(engine, 'capabilities', const <Object?>[]),
        'engine.capabilities',
      );
      for (final token in capabilities) {
        requireNonEmptyString(token, 'engine.capabilities[]');
      }
      validateOutcome(
        payload,
        'engineStatus',
        failed: readiness == 'ENGINE_READINESS_FAILED',
        errorAllowed: readiness == 'ENGINE_READINESS_NOT_READY',
      );
    case EnginePayloadKind.voicePackStatus:
      requireNonEmptyString(payload['packId'], 'voicePackStatus.packId');
      _validateVoicePackItem(payload, 'voicePackStatus');
      final components = requireList(
        fieldOr(payload, 'components', const <Object?>[]),
        'voicePackStatus.components',
      );
      for (final value in components) {
        final component = requireObject(value, 'voicePackStatus.components[]');
        requireNonEmptyString(
          component['componentId'],
          'component.componentId',
        );
        requireSpecifiedEnumName(
          component['kind'],
          _voicePackComponentKinds,
          'component.kind',
        );
        _validateVoicePackItem(component, 'component');
      }
    case EnginePayloadKind.microphoneStatus:
      requireNonEmptyString(payload['sourceId'], 'microphoneStatus.sourceId');
      requireSpecifiedEnumName(
        payload['permission'],
        _microphonePermissions,
        'microphoneStatus.permission',
      );
      final readiness = requireSpecifiedEnumName(
        payload['readiness'],
        _microphoneReadiness,
        'microphoneStatus.readiness',
      );
      if (payload.containsKey('route')) {
        requireEnumName(
          payload['route'],
          _microphoneRoutes,
          'microphoneStatus.route',
        );
      }
      if (payload.containsKey('interruption')) {
        requireEnumName(
          payload['interruption'],
          _microphoneInterruptions,
          'microphoneStatus.interruption',
        );
      }
      if (isEnumSet(payload, 'interruption') !=
          (readiness == 'MICROPHONE_READINESS_INTERRUPTED')) {
        throw const FormatException(
          'microphoneStatus.interruption is set exactly when interrupted',
        );
      }
    case EnginePayloadKind.speechOutput:
      requireNonEmptyString(payload['outputId'], 'speechOutput.outputId');
      final state = requireSpecifiedEnumName(
        payload['state'],
        _speechOutputStates,
        'speechOutput.state',
      );
      validateOutcome(
        payload,
        'speechOutput',
        failed: state == 'SPEECH_OUTPUT_STATE_FAILED',
      );
    case EnginePayloadKind.error:
      break;
  }
}

void _validateVoicePackItem(Map<String, Object?> item, String name) {
  final state = requireSpecifiedEnumName(
    item['state'],
    _voicePackStates,
    '$name.state',
  );
  validateOutcome(item, name, failed: state == 'VOICE_PACK_STATE_FAILED');
  validateProgress(
    parseUint64(fieldOr(item, 'bytesCompleted', '0'), '$name.bytesCompleted'),
    parseUint64(fieldOr(item, 'bytesTotal', '0'), '$name.bytesTotal'),
    name,
  );
}
