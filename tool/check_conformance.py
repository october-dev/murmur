#!/usr/bin/env python3
"""Validate the shared conformance corpus without requiring an SDK."""

from __future__ import annotations

import base64
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
UINT32_MAX = 2**32 - 1
UINT64_MAX = 2**64 - 1
MESSAGES = {"RuntimeEvent", "SessionControl", "AudioFrame", "VoiceSource"}
REASONS = {
    "missing-payload", "ambiguous-oneof", "missing-session-command",
    "ambiguous-session-command", "invalid-enum", "sequence-order",
    "invalid-uint64", "unsupported-protocol-major",
    "invalid-protocol-version", "invalid-audio-frame",
}
RUNTIME_ARMS = {
    "sessionStateChanged", "captureReadiness", "audioLevel", "transcript",
    "error", "intentProposal", "confirmationRequest", "actionResult",
}
SESSION_ARMS = {"start", "stop", "inputGate", "finalize"}
TRANSCRIPT_KINDS = {
    "TRANSCRIPT_KIND_UNSPECIFIED", "TRANSCRIPT_KIND_PARTIAL",
    "TRANSCRIPT_KIND_FINAL", "TRANSCRIPT_KIND_REJECTED",
}
SESSION_STATES = {
    "SESSION_STATE_UNSPECIFIED", "SESSION_STATE_IDLE", "SESSION_STATE_STARTING",
    "SESSION_STATE_LISTENING", "SESSION_STATE_WARM_MUTED",
    "SESSION_STATE_FINALIZING", "SESSION_STATE_STOPPED", "SESSION_STATE_ERROR",
}
CAPTURE_MODES = {
    "CAPTURE_MODE_UNSPECIFIED", "CAPTURE_MODE_TAP_TO_SPEAK",
    "CAPTURE_MODE_HOLD_TO_TALK", "CAPTURE_MODE_HANDS_FREE",
    "CAPTURE_MODE_WAKE_PHRASE",
}
AUDIO_ENCODINGS = {
    "AUDIO_ENCODING_PCM_S16LE", "AUDIO_ENCODING_PCM_F32LE", "AUDIO_ENCODING_OPUS",
}
SOURCE_TRANSPORTS = {
    "SOURCE_TRANSPORT_BLUETOOTH_LE", "SOURCE_TRANSPORT_LOCAL_AUDIO",
    "SOURCE_TRANSPORT_NETWORK", "SOURCE_TRANSPORT_FILE", "SOURCE_TRANSPORT_SYNTHETIC",
}
SOURCE_CAPABILITIES = {
    "SOURCE_CAPABILITY_LIVE_AUDIO", "SOURCE_CAPABILITY_STORED_AUDIO",
    "SOURCE_CAPABILITY_BATTERY", "SOURCE_CAPABILITY_HARDWARE_CONTROL",
    "SOURCE_CAPABILITY_OUTPUT_AUDIO", "SOURCE_CAPABILITY_BACKGROUND_CAPTURE",
    "SOURCE_CAPABILITY_INPUT_MUTE", "SOURCE_CAPABILITY_SPEAKER_VERIFICATION",
}
KNOWN_FIELDS = {
    "RuntimeEvent": {"protocol", "sessionId", "sequence", "monotonicTimeUs"} | RUNTIME_ARMS,
    "SessionControl": {"protocol", "sessionId", "requestSequence"} | SESSION_ARMS,
    "AudioFrame": {"protocol", "sessionId", "sequence", "monotonicTimeUs", "format", "payload"},
    "VoiceSource": {"sourceId", "displayName", "transport", "capabilities", "metadata"},
    "transcript": {"kind", "text", "providerId", "confidence"},
}
ASCII_UINT = re.compile(r"^[0-9]+$")
STANDARD_BASE64 = re.compile(r"^[A-Za-z0-9+/]*$")
URLSAFE_BASE64 = re.compile(r"^[A-Za-z0-9_-]*$")


def is_uint32(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= UINT32_MAX


def is_uint64_string(value: Any) -> bool:
    return isinstance(value, str) and ASCII_UINT.fullmatch(value) is not None and int(value) <= UINT64_MAX


def is_base64(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    pad = len(value) - len(value.rstrip("="))
    if pad > 2:
        return False
    raw = value[:-pad] if pad else value
    if "=" in raw:
        return False
    remainder = len(raw) % 4
    if remainder == 1:
        return False
    if pad and (pad != (4 - remainder) % 4 or len(value) % 4 != 0):
        return False
    return STANDARD_BASE64.fullmatch(raw) is not None or URLSAFE_BASE64.fullmatch(raw) is not None


def valid_protocol(value: Any) -> tuple[bool, bool]:
    if not isinstance(value, dict) or not is_uint32(value.get("major")) or not is_uint32(value.get("minor")):
        return False, False
    return True, value["major"] == 1


def valid_source(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    source_id, display_name = value.get("sourceId"), value.get("displayName")
    capabilities, metadata = value.get("capabilities", []), value.get("metadata", {})
    return (
        isinstance(source_id, str) and bool(source_id.strip())
        and isinstance(display_name, str) and bool(display_name.strip())
        and value.get("transport") in SOURCE_TRANSPORTS
        and isinstance(capabilities, list)
        and all(capability in SOURCE_CAPABILITIES for capability in capabilities)
        and isinstance(metadata, dict)
        and all(isinstance(key, str) and isinstance(item, str) for key, item in metadata.items())
    )


def valid_audio_format(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and is_uint32(value.get("sampleRateHz")) and value["sampleRateHz"] >= 1
        and is_uint32(value.get("channels")) and value["channels"] >= 1
        and value.get("encoding") in AUDIO_ENCODINGS
        and ("frameDurationMs" not in value or is_uint32(value["frameDurationMs"]))
    )


def common_violations(value: dict[str, Any], sequence_field: str) -> set[str]:
    result: set[str] = set()
    protocol_valid, protocol_supported = valid_protocol(value.get("protocol"))
    if not protocol_valid:
        result.add("invalid-protocol-version")
    elif not protocol_supported:
        result.add("unsupported-protocol-major")
    if not isinstance(value.get("sessionId"), str) or not value["sessionId"].strip():
        result.add("invalid-protocol-version")
    if not is_uint64_string(value.get(sequence_field)):
        result.add("invalid-uint64")
    return result


def diagnose(message: str, value: Any) -> set[str]:
    if not isinstance(value, dict):
        return {"invalid-protocol-version"}
    if message == "VoiceSource":
        return set() if valid_source(value) else {"invalid-enum"}
    if message == "RuntimeEvent":
        result = common_violations(value, "sequence")
        if not is_uint64_string(value.get("monotonicTimeUs")):
            result.add("invalid-uint64")
        present = RUNTIME_ARMS.intersection(value)
        if not present:
            result.add("missing-payload")
            return result
        if len(present) > 1:
            result.add("ambiguous-oneof")
            return result
        arm = next(iter(present))
        payload = value[arm]
        if not isinstance(payload, dict):
            result.add("invalid-enum")
            return result
        if arm == "transcript" and (
            payload.get("kind") not in TRANSCRIPT_KINDS or not isinstance(payload.get("text"), str)
        ):
            result.add("invalid-enum")
        elif arm == "audioLevel":
            amplitude = payload.get("amplitude")
            if isinstance(amplitude, bool) or not isinstance(amplitude, (int, float)) or not 0 <= amplitude <= 1:
                result.add("invalid-enum")
        elif arm == "sessionStateChanged" and (
            payload.get("previous") not in SESSION_STATES or payload.get("current") not in SESSION_STATES
        ):
            result.add("invalid-enum")
        return result
    if message == "SessionControl":
        result = common_violations(value, "requestSequence")
        present = SESSION_ARMS.intersection(value)
        if not present:
            result.add("missing-session-command")
            return result
        if len(present) > 1:
            result.add("ambiguous-session-command")
            return result
        arm = next(iter(present))
        body = value[arm]
        if not isinstance(body, dict):
            result.add("invalid-enum")
            return result
        if arm == "inputGate" and any(
            field in body and not isinstance(body[field], bool) for field in ("open", "flushAcceptedAudio")
        ):
            result.add("invalid-enum")
        if arm == "stop" and "reason" in body and not isinstance(body["reason"], str):
            result.add("invalid-enum")
        if arm == "start":
            if "mode" in body and body["mode"] not in CAPTURE_MODES:
                result.add("invalid-enum")
            if "source" in body and not valid_source(body["source"]):
                result.add("invalid-enum")
            if "requestedFormat" in body and not valid_audio_format(body["requestedFormat"]):
                result.add("invalid-enum")
        return result
    if message == "AudioFrame":
        result = common_violations(value, "sequence")
        if not is_uint64_string(value.get("monotonicTimeUs")):
            result.add("invalid-uint64")
        if not valid_audio_format(value.get("format")) or not is_base64(value.get("payload")):
            result.add("invalid-audio-frame")
        return result
    raise AssertionError(f"unknown message {message}")


def get_path(value: dict[str, Any], path: str) -> Any:
    current: Any = value
    for part in path.split("/"):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def validate_pcm_length(value: dict[str, Any], location: str) -> None:
    audio_format = value["format"]
    bytes_per_sample = {"AUDIO_ENCODING_PCM_S16LE": 2, "AUDIO_ENCODING_PCM_F32LE": 4}.get(
        audio_format["encoding"]
    )
    duration = audio_format.get("frameDurationMs")
    if bytes_per_sample is None or duration is None:
        return
    expected = audio_format["sampleRateHz"] * audio_format["channels"] * duration * bytes_per_sample
    assert expected % 1000 == 0, f"{location}: PCM duration does not produce whole bytes"
    decoded = base64.b64decode(value["payload"], validate=True)
    assert len(decoded) == expected // 1000, f"{location}: incorrect PCM payload length"


def validate_manifest(manifest: Any) -> list[dict[str, Any]]:
    assert isinstance(manifest, dict), "manifest must be an object"
    assert manifest.get("manifestVersion") == 1, "unsupported manifest version"
    assert manifest.get("protocol") == {"major": 1, "minor": 0}, "unexpected conformance protocol"
    fixture_sets = manifest.get("fixtureSets")
    assert isinstance(fixture_sets, list) and fixture_sets, "fixtureSets must be non-empty"
    names: set[str] = set()
    for item in fixture_sets:
        assert isinstance(item, dict), "fixture set must be an object"
        required = {"name", "message", "path", "lines", "expect"}
        assert required <= item.keys(), f"fixture set is missing {required - item.keys()}"
        assert isinstance(item["name"], str) and item["name"] not in names, "fixture names must be unique"
        names.add(item["name"])
        assert item["message"] in MESSAGES, f"invalid message in {item['name']}"
        assert item["expect"] in {"accept", "reject"}, f"invalid expectation in {item['name']}"
        assert isinstance(item["lines"], int) and item["lines"] > 0, f"invalid line count in {item['name']}"
        if item["expect"] == "reject":
            assert item.get("reason") in REASONS, f"invalid reason in {item['name']}"
            assert item.get("rejection") in {"parse", "order"}, f"invalid rejection in {item['name']}"
            reject_line = item.get("rejectLine", 1)
            assert isinstance(reject_line, int) and 1 <= reject_line <= item["lines"]
        unknown = item.get("unknownFields", [])
        assert isinstance(unknown, list) and all(isinstance(path, str) and path for path in unknown)
    return fixture_sets


def main() -> None:
    manifest = json.loads((ROOT / "conformance/manifest.json").read_text(encoding="utf-8"))
    fixture_sets = validate_manifest(manifest)
    protocol = manifest["protocol"]
    for fixture_set in fixture_sets:
        path = ROOT / "conformance" / fixture_set["path"]
        lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line]
        assert len(lines) == fixture_set["lines"], f"incorrect line count in {path}"
        values = [json.loads(line) for line in lines]
        message = fixture_set["message"]
        reject_line = fixture_set.get("rejectLine", 1)
        previous: int | None = None
        session_id: str | None = None
        for line_number, value in enumerate(values, start=1):
            location = f"{path}:{line_number}"
            violations = diagnose(message, value)
            if fixture_set["expect"] == "accept" or fixture_set.get("rejection") == "order":
                assert not violations, f"{location}: {sorted(violations)}"
            elif line_number >= reject_line:
                assert violations == {fixture_set["reason"]}, (
                    f"{location}: expected {fixture_set['reason']}, diagnosed {sorted(violations)}"
                )
            if message != "VoiceSource":
                if fixture_set["expect"] == "accept":
                    if fixture_set.get("unknownFields"):
                        assert value["protocol"]["major"] == protocol["major"], f"major mismatch at {location}"
                    else:
                        assert value["protocol"] == protocol, f"protocol mismatch at {location}"
                current_session = value.get("sessionId")
                session_id = session_id or current_session
                assert current_session == session_id, f"fixture changed sessions at {location}"
            ordering_field = {
                "RuntimeEvent": "sequence", "SessionControl": "requestSequence", "AudioFrame": "sequence",
            }.get(message)
            if ordering_field and not violations:
                current = int(value[ordering_field])
                ordered = previous is None or current > previous
                if fixture_set.get("rejection") == "order" and line_number >= reject_line:
                    assert not ordered, f"{location}: expected ordering rejection"
                else:
                    assert ordered, f"{location}: ordering key must increase"
                if ordered:
                    previous = current
            if message == "RuntimeEvent" and "transcript" in value:
                assert "synthetic" in value["transcript"]["text"].lower(), f"non-synthetic text at {location}"
            if message == "AudioFrame" and not violations:
                validate_pcm_length(value, location)
        for unknown_path in fixture_set.get("unknownFields", []):
            assert any(get_path(value, unknown_path) is not None for value in values), (
                f"unknown path {unknown_path} is absent from {fixture_set['name']}"
            )
            parts = unknown_path.split("/")
            owner = message if len(parts) == 1 else parts[-2]
            assert parts[-1] not in KNOWN_FIELDS.get(owner, set()), (
                f"{unknown_path} is a known field in {fixture_set['name']}"
            )
    connector = json.loads((ROOT / "connectors/omi/connector.json").read_text(encoding="utf-8"))
    assert connector["protocolMajor"] == protocol["major"], "connector protocol major mismatch"
    assert (ROOT / connector["implementation"]["path"]).is_dir(), "connector implementation path missing"
    print("Murmur protocol fixtures and connector manifests are consistent (15 sets, 43 lines).")


if __name__ == "__main__":
    main()
