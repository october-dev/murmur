import 'dart:convert';

import 'protocol.dart';
import 'validation.dart';

enum RuntimePayloadKind {
  sessionStateChanged('sessionStateChanged'),
  captureReadiness('captureReadiness'),
  audioLevel('audioLevel'),
  transcript('transcript'),
  error('error'),
  intentProposal('intentProposal'),
  confirmationRequest('confirmationRequest'),
  actionResult('actionResult'),
  providerStatus('providerStatus'),
  inputGateStatus('inputGateStatus'),
  wakePhrase('wakePhrase'),
  batchProgress('batchProgress');

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
    if (sequence < BigInt.zero || monotonicTimeUs < BigInt.zero) {
      throw ArgumentError('sequence and monotonicTimeUs must be non-negative');
    }
  }

  final ProtocolVersion protocol;
  final String sessionId;
  final BigInt sequence;
  final BigInt monotonicTimeUs;
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

    final sequence = parseUint64(json['sequence'], 'sequence');
    final monotonicTimeUs = parseUint64(
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

const _transcriptKinds = {
  'TRANSCRIPT_KIND_UNSPECIFIED',
  'TRANSCRIPT_KIND_PARTIAL',
  'TRANSCRIPT_KIND_FINAL',
  'TRANSCRIPT_KIND_REJECTED',
};
const _speakerVerificationResults = {
  'SPEAKER_VERIFICATION_RESULT_UNSPECIFIED',
  'SPEAKER_VERIFICATION_RESULT_ACCEPTED',
  'SPEAKER_VERIFICATION_RESULT_BYPASSED',
  'SPEAKER_VERIFICATION_RESULT_UNCERTAIN',
  'SPEAKER_VERIFICATION_RESULT_REJECTED',
};

/// Speaker-verification results each transcript kind may carry besides an
/// absent or UNSPECIFIED result.
const _speakerResultsByKind = <String, Set<String>>{
  'TRANSCRIPT_KIND_UNSPECIFIED': {},
  'TRANSCRIPT_KIND_PARTIAL': {},
  'TRANSCRIPT_KIND_FINAL': {
    'SPEAKER_VERIFICATION_RESULT_ACCEPTED',
    'SPEAKER_VERIFICATION_RESULT_BYPASSED',
    'SPEAKER_VERIFICATION_RESULT_UNCERTAIN',
  },
  'TRANSCRIPT_KIND_REJECTED': {
    'SPEAKER_VERIFICATION_RESULT_REJECTED',
    'SPEAKER_VERIFICATION_RESULT_UNCERTAIN',
  },
};
const _providerStates = {
  'PROVIDER_STATE_UNSPECIFIED',
  'PROVIDER_STATE_STARTING',
  'PROVIDER_STATE_ACTIVE',
  'PROVIDER_STATE_FINALIZING',
  'PROVIDER_STATE_FINALIZED',
  'PROVIDER_STATE_CANCELLED',
  'PROVIDER_STATE_FAILED',
};
const _inputGateCauses = {
  'INPUT_GATE_CAUSE_UNSPECIFIED',
  'INPUT_GATE_CAUSE_HOST',
  'INPUT_GATE_CAUSE_FINALIZATION',
  'INPUT_GATE_CAUSE_SPEECH_OUTPUT',
  'INPUT_GATE_CAUSE_ECHO_CLEARANCE',
  'INPUT_GATE_CAUSE_INTERRUPTION',
};
const _wakePhraseStages = {
  'WAKE_PHRASE_STAGE_UNSPECIFIED',
  'WAKE_PHRASE_STAGE_DETECTED',
  'WAKE_PHRASE_STAGE_ACTIVATED',
  'WAKE_PHRASE_STAGE_DISMISSED',
};

void _validateTranscript(Map<String, Object?> payload) {
  final kind = requireEnumName(
    payload['kind'],
    _transcriptKinds,
    'transcript.kind',
  );
  if (payload['text'] is! String) {
    throw const FormatException('transcript requires kind and text');
  }
  if (payload.containsKey('speakerVerification')) {
    final result = requireEnumName(
      payload['speakerVerification'],
      _speakerVerificationResults,
      'transcript.speakerVerification',
    );
    if (isEnumSet(payload, 'speakerVerification') &&
        !_speakerResultsByKind[kind]!.contains(result)) {
      throw FormatException('$kind cannot carry $result');
    }
  }
  final words = requireList(
    fieldOr(payload, 'words', const <Object?>[]),
    'transcript.words',
  );
  var previousStart = 0;
  for (final value in words) {
    final word = requireObject(value, 'transcript.words[]');
    if (word['text'] is! String) {
      throw const FormatException('word.text must be a string');
    }
    final start = parseUint32(
      fieldOr(word, 'startOffsetMs', 0),
      'startOffsetMs',
    );
    final end = parseUint32(fieldOr(word, 'endOffsetMs', 0), 'endOffsetMs');
    if (start > end || start < previousStart) {
      throw const FormatException(
        'words must be ordered and end at or after their start',
      );
    }
    if (word.containsKey('confidence')) {
      validateUnitInterval(word['confidence'], 'word.confidence');
    }
    previousStart = start;
  }
}

void _validatePayload(RuntimePayloadKind kind, Map<String, Object?> payload) {
  if (kind == RuntimePayloadKind.transcript) {
    _validateTranscript(payload);
  }
  if (kind == RuntimePayloadKind.audioLevel) {
    final amplitude = payload['amplitude'];
    if (amplitude is! num || amplitude < 0 || amplitude > 1) {
      throw const FormatException(
        'audioLevel.amplitude must be between 0 and 1',
      );
    }
  }
  if (kind == RuntimePayloadKind.sessionStateChanged) {
    const states = {
      'SESSION_STATE_UNSPECIFIED',
      'SESSION_STATE_IDLE',
      'SESSION_STATE_STARTING',
      'SESSION_STATE_LISTENING',
      'SESSION_STATE_WARM_MUTED',
      'SESSION_STATE_FINALIZING',
      'SESSION_STATE_STOPPED',
      'SESSION_STATE_ERROR',
    };
    if (!states.contains(payload['previous']) ||
        !states.contains(payload['current'])) {
      throw const FormatException(
        'sessionStateChanged requires known previous and current states',
      );
    }
  }
  if (kind == RuntimePayloadKind.providerStatus) {
    final state = requireSpecifiedEnumName(
      payload['state'],
      _providerStates,
      'providerStatus.state',
    );
    validateOutcome(
      payload,
      'providerStatus',
      failed: state == 'PROVIDER_STATE_FAILED',
    );
  }
  if (kind == RuntimePayloadKind.inputGateStatus) {
    final causes = requireList(
      fieldOr(payload, 'closedBy', const <Object?>[]),
      'inputGateStatus.closedBy',
    );
    final distinct = causes
        .map(
          (cause) => requireSpecifiedEnumName(
            cause,
            _inputGateCauses,
            'inputGateStatus.closedBy',
          ),
        )
        .toSet();
    if (distinct.length != causes.length) {
      throw const FormatException(
        'inputGateStatus.closedBy must not repeat a cause',
      );
    }
  }
  if (kind == RuntimePayloadKind.wakePhrase) {
    requireNonEmptyString(payload['phraseId'], 'wakePhrase.phraseId');
    requireSpecifiedEnumName(
      payload['stage'],
      _wakePhraseStages,
      'wakePhrase.stage',
    );
    if (payload.containsKey('confidence')) {
      validateUnitInterval(payload['confidence'], 'wakePhrase.confidence');
    }
  }
  if (kind == RuntimePayloadKind.batchProgress) {
    validateProgress(
      BigInt.from(
        parseUint32(
          fieldOr(payload, 'processedAudioMs', 0),
          'batchProgress.processedAudioMs',
        ),
      ),
      BigInt.from(
        parseUint32(
          fieldOr(payload, 'totalAudioMs', 0),
          'batchProgress.totalAudioMs',
        ),
      ),
      'batchProgress',
    );
  }
}
