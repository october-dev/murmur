from __future__ import annotations

import json
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


class SessionCommandKind(StrEnum):
    START = "start"
    STOP = "stop"
    INPUT_GATE = "inputGate"
    FINALIZE = "finalize"


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


def _validate_runtime_payload(kind: PayloadKind, payload: Mapping[str, Any]) -> None:
    if kind is PayloadKind.TRANSCRIPT:
        _known_name(payload.get("kind"), TRANSCRIPT_KINDS, "transcript.kind")
        if not isinstance(payload.get("text"), str):
            raise ValueError("transcript.text must be a string")
    elif kind is PayloadKind.AUDIO_LEVEL:
        amplitude = payload.get("amplitude")
        if isinstance(amplitude, bool) or not isinstance(amplitude, (int, float)) or not 0 <= amplitude <= 1:
            raise ValueError("audioLevel.amplitude must be between 0 and 1")
    elif kind is PayloadKind.SESSION_STATE_CHANGED:
        _known_name(payload.get("previous"), SESSION_STATES, "sessionStateChanged.previous")
        _known_name(payload.get("current"), SESSION_STATES, "sessionStateChanged.current")


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
