from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import StrEnum
from types import MappingProxyType
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class ProtocolVersion:
    major: int
    minor: int

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> ProtocolVersion:
        major = value.get("major")
        minor = value.get("minor")
        if not isinstance(major, int) or major < 0 or not isinstance(minor, int) or minor < 0:
            raise ValueError("protocol.major and protocol.minor must be non-negative integers")
        return cls(major=major, minor=minor)

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
        value = json.loads(source)
        if not isinstance(value, dict):
            raise ValueError("runtime event must be an object")
        return cls.from_dict(value)

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> RuntimeEvent:
        protocol_value = value.get("protocol")
        if not isinstance(protocol_value, dict):
            raise ValueError("runtime event requires protocol")
        session_id = value.get("sessionId")
        if not isinstance(session_id, str) or not session_id.strip():
            raise ValueError("sessionId must be a non-empty string")
        sequence = _parse_uint64(value.get("sequence"), "sequence")
        monotonic = _parse_uint64(value.get("monotonicTimeUs"), "monotonicTimeUs")
        present = [kind for kind in PayloadKind if kind.value in value]
        if len(present) != 1:
            raise ValueError("runtime event must contain exactly one known payload")
        kind = present[0]
        payload = value[kind.value]
        if not isinstance(payload, dict):
            raise ValueError(f"{kind.value} must be an object")
        _validate_payload(kind, payload)
        return cls(
            protocol=ProtocolVersion.from_dict(protocol_value),
            session_id=session_id,
            sequence=sequence,
            monotonic_time_us=monotonic,
            kind=kind,
            payload=MappingProxyType(dict(payload)),
        )

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
        if not self.source_id.strip() or not self.display_name.strip():
            raise ValueError("source_id and display_name must not be empty")


def _parse_uint64(value: Any, field_name: str) -> int:
    if not isinstance(value, str) or not value.isdecimal():
        raise ValueError(f"{field_name} must be a uint64 string")
    parsed = int(value)
    if parsed < 0 or parsed > 2**64 - 1:
        raise ValueError(f"{field_name} is outside uint64 range")
    return parsed


def _validate_payload(kind: PayloadKind, payload: Mapping[str, Any]) -> None:
    if kind is PayloadKind.TRANSCRIPT:
        if not isinstance(payload.get("kind"), str) or not isinstance(payload.get("text"), str):
            raise ValueError("transcript requires kind and text")
    if kind is PayloadKind.AUDIO_LEVEL:
        amplitude = payload.get("amplitude")
        if not isinstance(amplitude, (int, float)) or isinstance(amplitude, bool) or not 0 <= amplitude <= 1:
            raise ValueError("audioLevel.amplitude must be between 0 and 1")
