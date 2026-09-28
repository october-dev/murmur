from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from enum import StrEnum
from types import MappingProxyType
from typing import Any, Mapping

UINT32_MAX = 2**32 - 1
UINT64_MAX = 2**64 - 1
CURRENT_PROTOCOL_MAJOR = 1
_ASCII_UINT = re.compile(r"^[0-9]+$")
_STANDARD_BASE64 = re.compile(r"^[A-Za-z0-9+/]*$")
_URLSAFE_BASE64 = re.compile(r"^[A-Za-z0-9_-]*$")

TRANSCRIPT_KINDS = frozenset(
    {
        "TRANSCRIPT_KIND_UNSPECIFIED",
        "TRANSCRIPT_KIND_PARTIAL",
        "TRANSCRIPT_KIND_FINAL",
        "TRANSCRIPT_KIND_REJECTED",
    }
)
SESSION_STATES = frozenset(
    {
        "SESSION_STATE_UNSPECIFIED",
        "SESSION_STATE_IDLE",
        "SESSION_STATE_STARTING",
        "SESSION_STATE_LISTENING",
        "SESSION_STATE_WARM_MUTED",
        "SESSION_STATE_FINALIZING",
        "SESSION_STATE_STOPPED",
        "SESSION_STATE_ERROR",
    }
)
CAPTURE_MODES = frozenset(
    {
        "CAPTURE_MODE_UNSPECIFIED",
        "CAPTURE_MODE_TAP_TO_SPEAK",
        "CAPTURE_MODE_HOLD_TO_TALK",
        "CAPTURE_MODE_HANDS_FREE",
        "CAPTURE_MODE_WAKE_PHRASE",
    }
)
AUDIO_ENCODINGS = frozenset(
    {"AUDIO_ENCODING_PCM_S16LE", "AUDIO_ENCODING_PCM_F32LE", "AUDIO_ENCODING_OPUS"}
)
SOURCE_TRANSPORTS = frozenset(
    {
        "SOURCE_TRANSPORT_BLUETOOTH_LE",
        "SOURCE_TRANSPORT_LOCAL_AUDIO",
        "SOURCE_TRANSPORT_NETWORK",
        "SOURCE_TRANSPORT_FILE",
        "SOURCE_TRANSPORT_SYNTHETIC",
    }
)
SOURCE_CAPABILITIES = frozenset(
    {
        "SOURCE_CAPABILITY_LIVE_AUDIO",
        "SOURCE_CAPABILITY_STORED_AUDIO",
        "SOURCE_CAPABILITY_BATTERY",
        "SOURCE_CAPABILITY_HARDWARE_CONTROL",
        "SOURCE_CAPABILITY_OUTPUT_AUDIO",
        "SOURCE_CAPABILITY_BACKGROUND_CAPTURE",
        "SOURCE_CAPABILITY_INPUT_MUTE",
        "SOURCE_CAPABILITY_SPEAKER_VERIFICATION",
    }
)

# Required discriminators reject the *_UNSPECIFIED name; optional enums treat it
# as absent.
ENGINE_LOCALITIES = frozenset(
    {"ENGINE_LOCALITY_UNSPECIFIED", "ENGINE_LOCALITY_ON_DEVICE", "ENGINE_LOCALITY_REMOTE"}
)
ENGINE_PLATFORMS = frozenset(
    {
        "ENGINE_PLATFORM_UNSPECIFIED",
        "ENGINE_PLATFORM_MACOS",
        "ENGINE_PLATFORM_WINDOWS",
        "ENGINE_PLATFORM_LINUX",
        "ENGINE_PLATFORM_IOS",
        "ENGINE_PLATFORM_ANDROID",
    }
)
ENGINE_READINESS = frozenset(
    {
        "ENGINE_READINESS_UNSPECIFIED",
        "ENGINE_READINESS_NOT_READY",
        "ENGINE_READINESS_PREPARING",
        "ENGINE_READINESS_READY",
        "ENGINE_READINESS_FAILED",
    }
)
VOICE_PACK_STATES = frozenset(
    {
        "VOICE_PACK_STATE_UNSPECIFIED",
        "VOICE_PACK_STATE_NOT_INSTALLED",
        "VOICE_PACK_STATE_PREPARING",
        "VOICE_PACK_STATE_REPAIRING",
        "VOICE_PACK_STATE_READY",
        "VOICE_PACK_STATE_FAILED",
        "VOICE_PACK_STATE_UNSUPPORTED",
    }
)
VOICE_PACK_COMPONENT_KINDS = frozenset(
    {
        "VOICE_PACK_COMPONENT_KIND_UNSPECIFIED",
        "VOICE_PACK_COMPONENT_KIND_TRANSCRIPTION",
        "VOICE_PACK_COMPONENT_KIND_VOICE_ACTIVITY",
        "VOICE_PACK_COMPONENT_KIND_SPEECH_OUTPUT",
        "VOICE_PACK_COMPONENT_KIND_WAKE_PHRASE",
        "VOICE_PACK_COMPONENT_KIND_SPEAKER_VERIFICATION",
    }
)
VOICE_PACK_ACTIONS = frozenset(
    {
        "VOICE_PACK_ACTION_UNSPECIFIED",
        "VOICE_PACK_ACTION_PREPARE",
        "VOICE_PACK_ACTION_RETRY",
        "VOICE_PACK_ACTION_REPAIR",
    }
)
MICROPHONE_PERMISSIONS = frozenset(
    {
        "MICROPHONE_PERMISSION_UNSPECIFIED",
        "MICROPHONE_PERMISSION_NOT_DETERMINED",
        "MICROPHONE_PERMISSION_GRANTED",
        "MICROPHONE_PERMISSION_DENIED",
        "MICROPHONE_PERMISSION_RESTRICTED",
    }
)
MICROPHONE_ROUTES = frozenset(
    {
        "MICROPHONE_ROUTE_UNSPECIFIED",
        "MICROPHONE_ROUTE_BUILT_IN",
        "MICROPHONE_ROUTE_WIRED",
        "MICROPHONE_ROUTE_BLUETOOTH",
        "MICROPHONE_ROUTE_USB",
        "MICROPHONE_ROUTE_VIRTUAL",
    }
)
MICROPHONE_READINESS = frozenset(
    {
        "MICROPHONE_READINESS_UNSPECIFIED",
        "MICROPHONE_READINESS_UNAVAILABLE",
        "MICROPHONE_READINESS_WARMING",
        "MICROPHONE_READINESS_READY",
        "MICROPHONE_READINESS_INTERRUPTED",
    }
)
MICROPHONE_INTERRUPTIONS = frozenset(
    {
        "MICROPHONE_INTERRUPTION_UNSPECIFIED",
        "MICROPHONE_INTERRUPTION_SYSTEM",
        "MICROPHONE_INTERRUPTION_OTHER_APPLICATION",
        "MICROPHONE_INTERRUPTION_DEVICE_REMOVED",
    }
)
SPEECH_OUTPUT_STATES = frozenset(
    {
        "SPEECH_OUTPUT_STATE_UNSPECIFIED",
        "SPEECH_OUTPUT_STATE_PREPARING",
        "SPEECH_OUTPUT_STATE_SPEAKING",
        "SPEECH_OUTPUT_STATE_ECHO_CLEARING",
        "SPEECH_OUTPUT_STATE_COMPLETED",
        "SPEECH_OUTPUT_STATE_CANCELLED",
        "SPEECH_OUTPUT_STATE_FAILED",
    }
)
PROVIDER_STATES = frozenset(
    {
        "PROVIDER_STATE_UNSPECIFIED",
        "PROVIDER_STATE_STARTING",
        "PROVIDER_STATE_ACTIVE",
        "PROVIDER_STATE_FINALIZING",
        "PROVIDER_STATE_FINALIZED",
        "PROVIDER_STATE_CANCELLED",
        "PROVIDER_STATE_FAILED",
    }
)
INPUT_GATE_CAUSES = frozenset(
    {
        "INPUT_GATE_CAUSE_UNSPECIFIED",
        "INPUT_GATE_CAUSE_HOST",
        "INPUT_GATE_CAUSE_FINALIZATION",
        "INPUT_GATE_CAUSE_SPEECH_OUTPUT",
        "INPUT_GATE_CAUSE_ECHO_CLEARANCE",
        "INPUT_GATE_CAUSE_INTERRUPTION",
    }
)
WAKE_PHRASE_STAGES = frozenset(
    {
        "WAKE_PHRASE_STAGE_UNSPECIFIED",
        "WAKE_PHRASE_STAGE_DETECTED",
        "WAKE_PHRASE_STAGE_ACTIVATED",
        "WAKE_PHRASE_STAGE_DISMISSED",
    }
)
SPEAKER_VERIFICATION_MODES = frozenset(
    {
        "SPEAKER_VERIFICATION_MODE_UNSPECIFIED",
        "SPEAKER_VERIFICATION_MODE_DISABLED",
        "SPEAKER_VERIFICATION_MODE_ENFORCED",
        "SPEAKER_VERIFICATION_MODE_BYPASSED",
    }
)
SPEAKER_VERIFICATION_RESULTS = frozenset(
    {
        "SPEAKER_VERIFICATION_RESULT_UNSPECIFIED",
        "SPEAKER_VERIFICATION_RESULT_ACCEPTED",
        "SPEAKER_VERIFICATION_RESULT_BYPASSED",
        "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
        "SPEAKER_VERIFICATION_RESULT_REJECTED",
    }
)
# Speaker-verification results each transcript kind may carry besides an absent
# or UNSPECIFIED result.
SPEAKER_RESULTS_BY_KIND: Mapping[str, frozenset[str]] = MappingProxyType(
    {
        "TRANSCRIPT_KIND_UNSPECIFIED": frozenset(),
        "TRANSCRIPT_KIND_PARTIAL": frozenset(),
        "TRANSCRIPT_KIND_FINAL": frozenset(
            {
                "SPEAKER_VERIFICATION_RESULT_ACCEPTED",
                "SPEAKER_VERIFICATION_RESULT_BYPASSED",
                "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
            }
        ),
        "TRANSCRIPT_KIND_REJECTED": frozenset(
            {"SPEAKER_VERIFICATION_RESULT_REJECTED", "SPEAKER_VERIFICATION_RESULT_UNCERTAIN"}
        ),
    }
)


def is_supported(protocol: ProtocolVersion) -> bool:
    return protocol.major == CURRENT_PROTOCOL_MAJOR


@dataclass(frozen=True, slots=True)
class ProtocolVersion:
    major: int
    minor: int

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> ProtocolVersion:
        protocol = cls(
            major=_parse_uint32(value.get("major"), "protocol.major"),
            minor=_parse_uint32(value.get("minor"), "protocol.minor"),
        )
        if not is_supported(protocol):
            raise ValueError(f"unsupported protocol major {protocol.major}")
        return protocol

    def to_dict(self) -> dict[str, int]:
        return {"major": self.major, "minor": self.minor}


class PayloadKind(StrEnum):
    SESSION_STATE_CHANGED = "sessionStateChanged"
    CAPTURE_READINESS = "captureReadiness"
    AUDIO_LEVEL = "audioLevel"
    TRANSCRIPT = "transcript"
    ERROR = "error"
    INTENT_PROPOSAL = "intentProposal"
    CONFIRMATION_REQUEST = "confirmationRequest"
    ACTION_RESULT = "actionResult"
    PROVIDER_STATUS = "providerStatus"
    INPUT_GATE_STATUS = "inputGateStatus"
    WAKE_PHRASE = "wakePhrase"
    BATCH_PROGRESS = "batchProgress"


class SessionCommandKind(StrEnum):
    START = "start"
    STOP = "stop"
    INPUT_GATE = "inputGate"
    FINALIZE = "finalize"
    SPEAKER_VERIFICATION = "speakerVerification"
    START_BATCH = "startBatch"


class EnginePayloadKind(StrEnum):
    ENGINE_STATUS = "engineStatus"
    VOICE_PACK_STATUS = "voicePackStatus"
    MICROPHONE_STATUS = "microphoneStatus"
    SPEECH_OUTPUT = "speechOutput"
    ERROR = "error"


class EngineCommandKind(StrEnum):
    VOICE_PACK = "voicePack"
    SPEAK = "speak"
    CANCEL_SPEECH = "cancelSpeech"


@dataclass(frozen=True, slots=True)
class RuntimeEvent:
    protocol: ProtocolVersion
    session_id: str
    sequence: int
    monotonic_time_us: int
    kind: PayloadKind
    payload: Mapping[str, Any]

    @classmethod
    def from_json(cls, source: str) -> RuntimeEvent:
        return cls.from_dict(_json_object(source, "runtime event"))

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> RuntimeEvent:
        protocol = _parse_protocol(value)
        session_id = _non_empty_string(value.get("sessionId"), "sessionId")
        sequence = _parse_uint64(value.get("sequence"), "sequence")
        monotonic = _parse_uint64(value.get("monotonicTimeUs"), "monotonicTimeUs")
        present = [kind for kind in PayloadKind if kind.value in value]
        if len(present) != 1:
            raise ValueError("runtime event must contain exactly one known payload")
        kind = present[0]
        payload = _object(value[kind.value], kind.value)
        _validate_runtime_payload(kind, payload)
        return cls(protocol, session_id, sequence, monotonic, kind, MappingProxyType(dict(payload)))

    def to_dict(self) -> dict[str, Any]:
        return {
            "protocol": self.protocol.to_dict(),
            "sessionId": self.session_id,
            "sequence": str(self.sequence),
            "monotonicTimeUs": str(self.monotonic_time_us),
            self.kind.value: dict(self.payload),
        }


@dataclass(frozen=True, slots=True)
class VoiceSource:
    source_id: str
    display_name: str
    transport: str
    capabilities: tuple[str, ...] = ()
    metadata: Mapping[str, str] = field(default_factory=lambda: MappingProxyType({}))

    def __post_init__(self) -> None:
        _non_empty_string(self.source_id, "sourceId")
        _non_empty_string(self.display_name, "displayName")
        _known_name(self.transport, SOURCE_TRANSPORTS, "transport")
        for capability in self.capabilities:
            _known_name(capability, SOURCE_CAPABILITIES, "capability")
        if any(not isinstance(key, str) or not isinstance(value, str) for key, value in self.metadata.items()):
            raise ValueError("metadata must map strings to strings")

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> VoiceSource:
        capabilities = value.get("capabilities", [])
        metadata = value.get("metadata", {})
        if not isinstance(capabilities, list):
            raise ValueError("capabilities must be an array")
        if not isinstance(metadata, dict):
            raise ValueError("metadata must be an object")
        return cls(
            source_id=_non_empty_string(value.get("sourceId"), "sourceId"),
            display_name=_non_empty_string(value.get("displayName"), "displayName"),
            transport=_known_name(value.get("transport"), SOURCE_TRANSPORTS, "transport"),
            capabilities=tuple(
                _known_name(capability, SOURCE_CAPABILITIES, "capability")
                for capability in capabilities
            ),
            metadata=MappingProxyType(dict(metadata)),
        )

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "sourceId": self.source_id,
            "displayName": self.display_name,
            "transport": self.transport,
        }
        if self.capabilities:
            result["capabilities"] = list(self.capabilities)
        if self.metadata:
            result["metadata"] = dict(self.metadata)
        return result


@dataclass(frozen=True, slots=True)
class SessionControl:
    protocol: ProtocolVersion
    session_id: str
    request_sequence: int
    kind: SessionCommandKind
    body: Mapping[str, Any]

    @classmethod
    def from_json(cls, source: str) -> SessionControl:
        return cls.from_dict(_json_object(source, "session control"))

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> SessionControl:
        present = [kind for kind in SessionCommandKind if kind.value in value]
        if len(present) != 1:
            raise ValueError("session control must contain exactly one known command")
        kind = present[0]
        body = _object(value[kind.value], kind.value)
        _validate_session_body(kind, body)
        return cls(
            _parse_protocol(value),
            _non_empty_string(value.get("sessionId"), "sessionId"),
            _parse_uint64(value.get("requestSequence"), "requestSequence"),
            kind,
            MappingProxyType(dict(body)),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "protocol": self.protocol.to_dict(),
            "sessionId": self.session_id,
            "requestSequence": str(self.request_sequence),
            self.kind.value: dict(self.body),
        }


@dataclass(frozen=True, slots=True)
class AudioFrame:
    protocol: ProtocolVersion
    session_id: str
    sequence: int
    monotonic_time_us: int
    format: Mapping[str, Any]
    payload_base64: str

    @classmethod
    def from_json(cls, source: str) -> AudioFrame:
        return cls.from_dict(_json_object(source, "audio frame"))

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> AudioFrame:
        audio_format = _object(value.get("format"), "format")
        _validate_audio_format(audio_format)
        payload = value.get("payload")
        if not isinstance(payload, str) or not _is_base64(payload):
            raise ValueError("payload must use valid base64 grammar")
        return cls(
            _parse_protocol(value),
            _non_empty_string(value.get("sessionId"), "sessionId"),
            _parse_uint64(value.get("sequence"), "sequence"),
            _parse_uint64(value.get("monotonicTimeUs"), "monotonicTimeUs"),
            MappingProxyType(dict(audio_format)),
            payload,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "protocol": self.protocol.to_dict(),
            "sessionId": self.session_id,
            "sequence": str(self.sequence),
            "monotonicTimeUs": str(self.monotonic_time_us),
            "format": dict(self.format),
            "payload": self.payload_base64,
        }


@dataclass(frozen=True, slots=True)
class EngineEvent:
    protocol: ProtocolVersion
    engine_id: str
    sequence: int
    monotonic_time_us: int
    kind: EnginePayloadKind
    payload: Mapping[str, Any]

    @classmethod
    def from_json(cls, source: str) -> EngineEvent:
        return cls.from_dict(_json_object(source, "engine event"))

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> EngineEvent:
        protocol = _parse_protocol(value)
        engine_id = _non_empty_string(value.get("engineId"), "engineId")
        sequence = _parse_uint64(value.get("sequence"), "sequence")
        monotonic = _parse_uint64(value.get("monotonicTimeUs"), "monotonicTimeUs")
        present = [kind for kind in EnginePayloadKind if kind.value in value]
        if len(present) != 1:
            raise ValueError("engine event must contain exactly one known payload")
        kind = present[0]
        payload = _object(value[kind.value], kind.value)
        _validate_engine_payload(kind, payload)
        return cls(protocol, engine_id, sequence, monotonic, kind, MappingProxyType(dict(payload)))

    def to_dict(self) -> dict[str, Any]:
        return {
            "protocol": self.protocol.to_dict(),
            "engineId": self.engine_id,
            "sequence": str(self.sequence),
            "monotonicTimeUs": str(self.monotonic_time_us),
            self.kind.value: dict(self.payload),
        }


@dataclass(frozen=True, slots=True)
class EngineControl:
    protocol: ProtocolVersion
    engine_id: str
    request_sequence: int
    kind: EngineCommandKind
    body: Mapping[str, Any]

    @classmethod
    def from_json(cls, source: str) -> EngineControl:
        return cls.from_dict(_json_object(source, "engine control"))

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> EngineControl:
        present = [kind for kind in EngineCommandKind if kind.value in value]
        if len(present) != 1:
            raise ValueError("engine control must contain exactly one known command")
        kind = present[0]
        body = _object(value[kind.value], kind.value)
        _validate_engine_command(kind, body)
        return cls(
            _parse_protocol(value),
            _non_empty_string(value.get("engineId"), "engineId"),
            _parse_uint64(value.get("requestSequence"), "requestSequence"),
            kind,
            MappingProxyType(dict(body)),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "protocol": self.protocol.to_dict(),
            "engineId": self.engine_id,
            "requestSequence": str(self.request_sequence),
            self.kind.value: dict(self.body),
        }


def _json_object(source: str, name: str) -> dict[str, Any]:
    value = json.loads(source)
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be an object")
    return value


def _object(value: Any, field_name: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field_name} must be an object")
    return value


def _parse_protocol(value: Mapping[str, Any]) -> ProtocolVersion:
    return ProtocolVersion.from_dict(_object(value.get("protocol"), "protocol"))


def _parse_uint32(value: Any, field_name: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= UINT32_MAX:
        raise ValueError(f"{field_name} must be a uint32")
    return value


def _parse_uint64(value: Any, field_name: str) -> int:
    if not isinstance(value, str) or _ASCII_UINT.fullmatch(value) is None:
        raise ValueError(f"{field_name} must be an ASCII uint64 string")
    parsed = int(value)
    if parsed > UINT64_MAX:
        raise ValueError(f"{field_name} is outside uint64 range")
    return parsed


def _non_empty_string(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty string")
    return value


def _known_name(value: Any, names: frozenset[str], field_name: str) -> str:
    if not isinstance(value, str) or value not in names:
        raise ValueError(f"{field_name} must be a known enum name")
    return value


def _required_name(value: Any, names: frozenset[str], field_name: str) -> str:
    if _known_name(value, names, field_name).endswith("_UNSPECIFIED"):
        raise ValueError(f"{field_name} must not be unspecified")
    return value


def _is_set(body: Mapping[str, Any], field_name: str) -> bool:
    value = body.get(field_name)
    return field_name in body and not (isinstance(value, str) and value.endswith("_UNSPECIFIED"))


def _validate_outcome(body: Mapping[str, Any], failed: bool, name: str, error_allowed: bool = False) -> None:
    if "error" in body:
        _object(body["error"], f"{name}.error")
        if not failed and not error_allowed:
            raise ValueError(f"{name}.error is only allowed when failed")
    elif failed:
        raise ValueError(f"{name}.error is required when failed")


def _validate_unit_interval(value: Any, field_name: str) -> None:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or not 0 <= value <= 1
    ):
        raise ValueError(f"{field_name} must be between 0 and 1")


def _validate_progress(completed: int, total: int, name: str) -> None:
    if total and completed > total:
        raise ValueError(f"{name} progress exceeds its total")


def _array(value: Any, field_name: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{field_name} must be an array")
    return value


def _validate_transcript(payload: Mapping[str, Any]) -> None:
    kind = _known_name(payload.get("kind"), TRANSCRIPT_KINDS, "transcript.kind")
    if not isinstance(payload.get("text"), str):
        raise ValueError("transcript.text must be a string")
    if "speakerVerification" in payload:
        result = _known_name(
            payload["speakerVerification"], SPEAKER_VERIFICATION_RESULTS, "transcript.speakerVerification"
        )
        if _is_set(payload, "speakerVerification") and result not in SPEAKER_RESULTS_BY_KIND[kind]:
            raise ValueError(f"{kind} cannot carry {result}")
    previous_start = 0
    for word in _array(payload.get("words", []), "transcript.words"):
        word = _object(word, "transcript.words[]")
        if not isinstance(word.get("text"), str):
            raise ValueError("word.text must be a string")
        start = _parse_uint32(word.get("startOffsetMs", 0), "word.startOffsetMs")
        end = _parse_uint32(word.get("endOffsetMs", 0), "word.endOffsetMs")
        if start > end or start < previous_start:
            raise ValueError("words must be ordered and end at or after their start")
        if "confidence" in word:
            _validate_unit_interval(word["confidence"], "word.confidence")
        previous_start = start


def _validate_runtime_payload(kind: PayloadKind, payload: Mapping[str, Any]) -> None:
    if kind is PayloadKind.TRANSCRIPT:
        _validate_transcript(payload)
    elif kind is PayloadKind.AUDIO_LEVEL:
        amplitude = payload.get("amplitude")
        if isinstance(amplitude, bool) or not isinstance(amplitude, (int, float)) or not 0 <= amplitude <= 1:
            raise ValueError("audioLevel.amplitude must be between 0 and 1")
    elif kind is PayloadKind.SESSION_STATE_CHANGED:
        _known_name(payload.get("previous"), SESSION_STATES, "sessionStateChanged.previous")
        _known_name(payload.get("current"), SESSION_STATES, "sessionStateChanged.current")
    elif kind is PayloadKind.PROVIDER_STATUS:
        state = _required_name(payload.get("state"), PROVIDER_STATES, "providerStatus.state")
        _validate_outcome(payload, state == "PROVIDER_STATE_FAILED", "providerStatus")
    elif kind is PayloadKind.INPUT_GATE_STATUS:
        causes = [
            _required_name(cause, INPUT_GATE_CAUSES, "inputGateStatus.closedBy")
            for cause in _array(payload.get("closedBy", []), "inputGateStatus.closedBy")
        ]
        if len(set(causes)) != len(causes):
            raise ValueError("inputGateStatus.closedBy must not repeat a cause")
    elif kind is PayloadKind.WAKE_PHRASE:
        _non_empty_string(payload.get("phraseId"), "wakePhrase.phraseId")
        _required_name(payload.get("stage"), WAKE_PHRASE_STAGES, "wakePhrase.stage")
        if "confidence" in payload:
            _validate_unit_interval(payload["confidence"], "wakePhrase.confidence")
    elif kind is PayloadKind.BATCH_PROGRESS:
        _validate_progress(
            _parse_uint32(payload.get("processedAudioMs", 0), "batchProgress.processedAudioMs"),
            _parse_uint32(payload.get("totalAudioMs", 0), "batchProgress.totalAudioMs"),
            "batchProgress",
        )


def _validate_engine_payload(kind: EnginePayloadKind, payload: Mapping[str, Any]) -> None:
    if kind is EnginePayloadKind.ENGINE_STATUS:
        engine = _object(payload.get("engine"), "engineStatus.engine")
        readiness = _required_name(payload.get("readiness"), ENGINE_READINESS, "engineStatus.readiness")
        locality = _required_name(engine.get("locality"), ENGINE_LOCALITIES, "engine.locality")
        if locality == "ENGINE_LOCALITY_ON_DEVICE":
            _required_name(engine.get("platform"), ENGINE_PLATFORMS, "engine.platform")
        elif "platform" in engine:
            _known_name(engine["platform"], ENGINE_PLATFORMS, "engine.platform")
        for token in _array(engine.get("capabilities", []), "engine.capabilities"):
            _non_empty_string(token, "engine.capabilities[]")
        _validate_outcome(
            payload,
            readiness == "ENGINE_READINESS_FAILED",
            "engineStatus",
            error_allowed=readiness == "ENGINE_READINESS_NOT_READY",
        )
    elif kind is EnginePayloadKind.VOICE_PACK_STATUS:
        _non_empty_string(payload.get("packId"), "voicePackStatus.packId")
        _validate_voice_pack_item(payload, "voicePackStatus")
        for component in _array(payload.get("components", []), "voicePackStatus.components"):
            component = _object(component, "voicePackStatus.components[]")
            _non_empty_string(component.get("componentId"), "component.componentId")
            _required_name(component.get("kind"), VOICE_PACK_COMPONENT_KINDS, "component.kind")
            _validate_voice_pack_item(component, "component")
    elif kind is EnginePayloadKind.MICROPHONE_STATUS:
        _non_empty_string(payload.get("sourceId"), "microphoneStatus.sourceId")
        _required_name(payload.get("permission"), MICROPHONE_PERMISSIONS, "microphoneStatus.permission")
        readiness = _required_name(payload.get("readiness"), MICROPHONE_READINESS, "microphoneStatus.readiness")
        if "route" in payload:
            _known_name(payload["route"], MICROPHONE_ROUTES, "microphoneStatus.route")
        if "interruption" in payload:
            _known_name(payload["interruption"], MICROPHONE_INTERRUPTIONS, "microphoneStatus.interruption")
        if _is_set(payload, "interruption") != (readiness == "MICROPHONE_READINESS_INTERRUPTED"):
            raise ValueError("microphoneStatus.interruption is set exactly when interrupted")
    elif kind is EnginePayloadKind.SPEECH_OUTPUT:
        _non_empty_string(payload.get("outputId"), "speechOutput.outputId")
        state = _required_name(payload.get("state"), SPEECH_OUTPUT_STATES, "speechOutput.state")
        _validate_outcome(payload, state == "SPEECH_OUTPUT_STATE_FAILED", "speechOutput")


def _validate_voice_pack_item(item: Mapping[str, Any], name: str) -> None:
    state = _required_name(item.get("state"), VOICE_PACK_STATES, f"{name}.state")
    _validate_outcome(item, state == "VOICE_PACK_STATE_FAILED", name)
    _validate_progress(
        _parse_uint64(item.get("bytesCompleted", "0"), f"{name}.bytesCompleted"),
        _parse_uint64(item.get("bytesTotal", "0"), f"{name}.bytesTotal"),
        name,
    )


def _validate_engine_command(kind: EngineCommandKind, body: Mapping[str, Any]) -> None:
    if kind is EngineCommandKind.VOICE_PACK:
        _non_empty_string(body.get("packId"), "voicePack.packId")
        _required_name(body.get("action"), VOICE_PACK_ACTIONS, "voicePack.action")
    elif kind is EngineCommandKind.SPEAK:
        _non_empty_string(body.get("outputId"), "speak.outputId")
        _non_empty_string(body.get("text"), "speak.text")
        if "fullDuplex" in body and not isinstance(body["fullDuplex"], bool):
            raise ValueError("speak.fullDuplex must be a boolean")
        if "echoClearanceMs" in body:
            _parse_uint32(body["echoClearanceMs"], "speak.echoClearanceMs")
    elif kind is EngineCommandKind.CANCEL_SPEECH:
        _non_empty_string(body.get("outputId"), "cancelSpeech.outputId")


def _validate_audio_format(value: Mapping[str, Any]) -> None:
    if _parse_uint32(value.get("sampleRateHz"), "sampleRateHz") < 1:
        raise ValueError("sampleRateHz must be at least 1")
    if _parse_uint32(value.get("channels"), "channels") < 1:
        raise ValueError("channels must be at least 1")
    _known_name(value.get("encoding"), AUDIO_ENCODINGS, "encoding")
    if "frameDurationMs" in value:
        _parse_uint32(value["frameDurationMs"], "frameDurationMs")


def _validate_session_body(kind: SessionCommandKind, body: Mapping[str, Any]) -> None:
    if kind is SessionCommandKind.INPUT_GATE:
        for field_name in ("open", "flushAcceptedAudio"):
            if field_name in body and not isinstance(body[field_name], bool):
                raise ValueError(f"{field_name} must be a boolean")
    elif kind is SessionCommandKind.STOP:
        if "reason" in body and not isinstance(body["reason"], str):
            raise ValueError("stop.reason must be a string")
    elif kind is SessionCommandKind.START:
        if "mode" in body:
            _known_name(body["mode"], CAPTURE_MODES, "start.mode")
        if "source" in body:
            VoiceSource.from_dict(_object(body["source"], "start.source"))
        if "requestedFormat" in body:
            _validate_audio_format(_object(body["requestedFormat"], "start.requestedFormat"))
        if "engineId" in body:
            _non_empty_string(body["engineId"], "start.engineId")
    elif kind is SessionCommandKind.SPEAKER_VERIFICATION:
        _required_name(body.get("mode"), SPEAKER_VERIFICATION_MODES, "speakerVerification.mode")
    elif kind is SessionCommandKind.START_BATCH:
        _non_empty_string(body.get("engineId"), "startBatch.engineId")
        audio_format = _object(body.get("format"), "startBatch.format")
        _validate_audio_format(audio_format)
        if audio_format["encoding"] == "AUDIO_ENCODING_OPUS" and audio_format.get("frameDurationMs", 0) < 1:
            raise ValueError("startBatch.format.frameDurationMs is required for Opus")
        if "totalAudioMs" in body:
            _parse_uint32(body["totalAudioMs"], "startBatch.totalAudioMs")


def _is_base64(value: str) -> bool:
    pad = len(value) - len(value.rstrip("="))
    if pad > 2:
        return False
    raw = value[:-pad] if pad else value
    if "=" in raw or len(raw) % 4 == 1:
        return False
    if pad and (pad != (4 - len(raw) % 4) % 4 or len(value) % 4 != 0):
        return False
    return _STANDARD_BASE64.fullmatch(raw) is not None or _URLSAFE_BASE64.fullmatch(raw) is not None
