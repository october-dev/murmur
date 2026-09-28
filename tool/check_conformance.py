#!/usr/bin/env python3
"""Validate the shared conformance corpus without requiring an SDK."""

from __future__ import annotations

import base64
import json
import math
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
UINT32_MAX = 2**32 - 1
UINT64_MAX = 2**64 - 1
MESSAGES = {"RuntimeEvent", "SessionControl", "AudioFrame", "VoiceSource", "EngineEvent", "EngineControl"}
REASONS = {
    "missing-payload", "ambiguous-oneof", "missing-session-command",
    "ambiguous-session-command", "invalid-enum", "sequence-order",
    "invalid-uint64", "unsupported-protocol-major",
    "invalid-protocol-version", "invalid-audio-frame",
    "missing-engine-command", "ambiguous-engine-command", "invalid-identifier",
    "invalid-progress", "invalid-word-timing", "invalid-outcome",
}
RUNTIME_ARMS = {
    "sessionStateChanged", "captureReadiness", "audioLevel", "transcript",
    "error", "intentProposal", "confirmationRequest", "actionResult",
    "providerStatus", "inputGateStatus", "wakePhrase", "batchProgress",
}
SESSION_ARMS = {"start", "stop", "inputGate", "finalize", "speakerVerification", "startBatch"}
ENGINE_EVENT_ARMS = {"engineStatus", "voicePackStatus", "microphoneStatus", "speechOutput", "error"}
ENGINE_CONTROL_ARMS = {"voicePack", "speak", "cancelSpeech"}
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
# Enum sets below list every known name, including *_UNSPECIFIED; fields that
# are required discriminators additionally reject the UNSPECIFIED name.
ENGINE_LOCALITIES = {"ENGINE_LOCALITY_UNSPECIFIED", "ENGINE_LOCALITY_ON_DEVICE", "ENGINE_LOCALITY_REMOTE"}
ENGINE_PLATFORMS = {
    "ENGINE_PLATFORM_UNSPECIFIED", "ENGINE_PLATFORM_MACOS", "ENGINE_PLATFORM_WINDOWS",
    "ENGINE_PLATFORM_LINUX", "ENGINE_PLATFORM_IOS", "ENGINE_PLATFORM_ANDROID",
}
ENGINE_READINESS = {
    "ENGINE_READINESS_UNSPECIFIED", "ENGINE_READINESS_NOT_READY", "ENGINE_READINESS_PREPARING",
    "ENGINE_READINESS_READY", "ENGINE_READINESS_FAILED",
}
VOICE_PACK_STATES = {
    "VOICE_PACK_STATE_UNSPECIFIED", "VOICE_PACK_STATE_NOT_INSTALLED", "VOICE_PACK_STATE_PREPARING",
    "VOICE_PACK_STATE_REPAIRING", "VOICE_PACK_STATE_READY", "VOICE_PACK_STATE_FAILED",
    "VOICE_PACK_STATE_UNSUPPORTED",
}
VOICE_PACK_COMPONENT_KINDS = {
    "VOICE_PACK_COMPONENT_KIND_UNSPECIFIED", "VOICE_PACK_COMPONENT_KIND_TRANSCRIPTION",
    "VOICE_PACK_COMPONENT_KIND_VOICE_ACTIVITY", "VOICE_PACK_COMPONENT_KIND_SPEECH_OUTPUT",
    "VOICE_PACK_COMPONENT_KIND_WAKE_PHRASE", "VOICE_PACK_COMPONENT_KIND_SPEAKER_VERIFICATION",
}
VOICE_PACK_ACTIONS = {
    "VOICE_PACK_ACTION_UNSPECIFIED", "VOICE_PACK_ACTION_PREPARE", "VOICE_PACK_ACTION_RETRY",
    "VOICE_PACK_ACTION_REPAIR",
}
MICROPHONE_PERMISSIONS = {
    "MICROPHONE_PERMISSION_UNSPECIFIED", "MICROPHONE_PERMISSION_NOT_DETERMINED",
    "MICROPHONE_PERMISSION_GRANTED", "MICROPHONE_PERMISSION_DENIED", "MICROPHONE_PERMISSION_RESTRICTED",
}
MICROPHONE_ROUTES = {
    "MICROPHONE_ROUTE_UNSPECIFIED", "MICROPHONE_ROUTE_BUILT_IN", "MICROPHONE_ROUTE_WIRED",
    "MICROPHONE_ROUTE_BLUETOOTH", "MICROPHONE_ROUTE_USB", "MICROPHONE_ROUTE_VIRTUAL",
}
MICROPHONE_READINESS = {
    "MICROPHONE_READINESS_UNSPECIFIED", "MICROPHONE_READINESS_UNAVAILABLE",
    "MICROPHONE_READINESS_WARMING", "MICROPHONE_READINESS_READY", "MICROPHONE_READINESS_INTERRUPTED",
}
MICROPHONE_INTERRUPTIONS = {
    "MICROPHONE_INTERRUPTION_UNSPECIFIED", "MICROPHONE_INTERRUPTION_SYSTEM",
    "MICROPHONE_INTERRUPTION_OTHER_APPLICATION", "MICROPHONE_INTERRUPTION_DEVICE_REMOVED",
}
SPEECH_OUTPUT_STATES = {
    "SPEECH_OUTPUT_STATE_UNSPECIFIED", "SPEECH_OUTPUT_STATE_PREPARING", "SPEECH_OUTPUT_STATE_SPEAKING",
    "SPEECH_OUTPUT_STATE_ECHO_CLEARING", "SPEECH_OUTPUT_STATE_COMPLETED",
    "SPEECH_OUTPUT_STATE_CANCELLED", "SPEECH_OUTPUT_STATE_FAILED",
}
PROVIDER_STATES = {
    "PROVIDER_STATE_UNSPECIFIED", "PROVIDER_STATE_STARTING", "PROVIDER_STATE_ACTIVE",
    "PROVIDER_STATE_FINALIZING", "PROVIDER_STATE_FINALIZED", "PROVIDER_STATE_CANCELLED",
    "PROVIDER_STATE_FAILED",
}
INPUT_GATE_CAUSES = {
    "INPUT_GATE_CAUSE_UNSPECIFIED", "INPUT_GATE_CAUSE_HOST", "INPUT_GATE_CAUSE_FINALIZATION",
    "INPUT_GATE_CAUSE_SPEECH_OUTPUT", "INPUT_GATE_CAUSE_ECHO_CLEARANCE", "INPUT_GATE_CAUSE_INTERRUPTION",
}
WAKE_PHRASE_STAGES = {
    "WAKE_PHRASE_STAGE_UNSPECIFIED", "WAKE_PHRASE_STAGE_DETECTED", "WAKE_PHRASE_STAGE_ACTIVATED",
    "WAKE_PHRASE_STAGE_DISMISSED",
}
SPEAKER_VERIFICATION_MODES = {
    "SPEAKER_VERIFICATION_MODE_UNSPECIFIED", "SPEAKER_VERIFICATION_MODE_DISABLED",
    "SPEAKER_VERIFICATION_MODE_ENFORCED", "SPEAKER_VERIFICATION_MODE_BYPASSED",
}
SPEAKER_VERIFICATION_RESULTS = {
    "SPEAKER_VERIFICATION_RESULT_UNSPECIFIED", "SPEAKER_VERIFICATION_RESULT_ACCEPTED",
    "SPEAKER_VERIFICATION_RESULT_BYPASSED", "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
    "SPEAKER_VERIFICATION_RESULT_REJECTED",
}
# Speaker-verification results allowed on each transcript kind. An absent or
# explicit SPEAKER_VERIFICATION_RESULT_UNSPECIFIED result is allowed on every kind.
SPEAKER_RESULTS_BY_KIND = {
    "TRANSCRIPT_KIND_UNSPECIFIED": set(),
    "TRANSCRIPT_KIND_PARTIAL": set(),
    "TRANSCRIPT_KIND_FINAL": {
        "SPEAKER_VERIFICATION_RESULT_ACCEPTED", "SPEAKER_VERIFICATION_RESULT_BYPASSED",
        "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
    },
    "TRANSCRIPT_KIND_REJECTED": {
        "SPEAKER_VERIFICATION_RESULT_REJECTED", "SPEAKER_VERIFICATION_RESULT_UNCERTAIN",
    },
}
KNOWN_FIELDS = {
    "RuntimeEvent": {"protocol", "sessionId", "sequence", "monotonicTimeUs"} | RUNTIME_ARMS,
    "SessionControl": {"protocol", "sessionId", "requestSequence"} | SESSION_ARMS,
    "AudioFrame": {"protocol", "sessionId", "sequence", "monotonicTimeUs", "format", "payload"},
    "VoiceSource": {"sourceId", "displayName", "transport", "capabilities", "metadata"},
    "EngineEvent": {"protocol", "engineId", "sequence", "monotonicTimeUs"} | ENGINE_EVENT_ARMS,
    "EngineControl": {"protocol", "engineId", "requestSequence"} | ENGINE_CONTROL_ARMS,
    "transcript": {"kind", "text", "providerId", "confidence", "words", "speakerVerification"},
    "start": {"source", "mode", "requestedFormat", "engineId"},
}
ORDERING_FIELDS = {
    "RuntimeEvent": "sequence", "SessionControl": "requestSequence", "AudioFrame": "sequence",
    "EngineEvent": "sequence", "EngineControl": "requestSequence",
}
ROUTING_FIELDS = {
    "RuntimeEvent": "sessionId", "SessionControl": "sessionId", "AudioFrame": "sessionId",
    "EngineEvent": "engineId", "EngineControl": "engineId",
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


def is_non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def is_unit_interval(value: Any) -> bool:
    return (
        not isinstance(value, bool) and isinstance(value, (int, float))
        and math.isfinite(value) and 0 <= value <= 1
    )


def is_known_enum(value: Any, names: set[str]) -> bool:
    return isinstance(value, str) and value in names


def is_required_enum(value: Any, names: set[str]) -> bool:
    """A required discriminator: a known name other than *_UNSPECIFIED."""
    return is_known_enum(value, names) and not value.endswith("_UNSPECIFIED")


def is_set(body: dict[str, Any], field: str) -> bool:
    """Whether an optional enum is set; an explicit *_UNSPECIFIED counts as absent."""
    return field in body and not (isinstance(body[field], str) and body[field].endswith("_UNSPECIFIED"))


def valid_outcome(body: dict[str, Any], failed: bool, error_allowed: bool = False) -> bool:
    """FAILED requires an error object; other states forbid it unless allowed."""
    if "error" not in body:
        return not failed
    return isinstance(body["error"], dict) and (failed or error_allowed)


def valid_progress(completed: Any, total: Any) -> bool:
    return total == 0 or completed <= total


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
        and is_known_enum(value.get("transport"), SOURCE_TRANSPORTS)
        and isinstance(capabilities, list)
        and all(is_known_enum(capability, SOURCE_CAPABILITIES) for capability in capabilities)
        and isinstance(metadata, dict)
        and all(isinstance(key, str) and isinstance(item, str) for key, item in metadata.items())
    )


def valid_audio_format(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and is_uint32(value.get("sampleRateHz")) and value["sampleRateHz"] >= 1
        and is_uint32(value.get("channels")) and value["channels"] >= 1
        and is_known_enum(value.get("encoding"), AUDIO_ENCODINGS)
        and ("frameDurationMs" not in value or is_uint32(value["frameDurationMs"]))
    )


def common_violations(value: dict[str, Any], sequence_field: str, routing_field: str = "sessionId") -> set[str]:
    result: set[str] = set()
    protocol_valid, protocol_supported = valid_protocol(value.get("protocol"))
    if not protocol_valid:
        result.add("invalid-protocol-version")
    elif not protocol_supported:
        result.add("unsupported-protocol-major")
    if not is_non_empty_string(value.get(routing_field)):
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
        if arm == "transcript":
            result |= transcript_violations(payload)
        elif arm == "audioLevel":
            amplitude = payload.get("amplitude")
            if isinstance(amplitude, bool) or not isinstance(amplitude, (int, float)) or not 0 <= amplitude <= 1:
                result.add("invalid-enum")
        elif arm == "sessionStateChanged" and (
            not is_known_enum(payload.get("previous"), SESSION_STATES) or not is_known_enum(payload.get("current"), SESSION_STATES)
        ):
            result.add("invalid-enum")
        elif arm == "providerStatus":
            state = payload.get("state")
            if not is_required_enum(state, PROVIDER_STATES):
                result.add("invalid-enum")
            elif not valid_outcome(payload, state == "PROVIDER_STATE_FAILED"):
                result.add("invalid-outcome")
        elif arm == "inputGateStatus":
            causes = payload.get("closedBy", [])
            if not (
                isinstance(causes, list)
                and all(is_required_enum(cause, INPUT_GATE_CAUSES) for cause in causes)
                and len(set(causes)) == len(causes)
            ):
                result.add("invalid-enum")
        elif arm == "wakePhrase":
            if not is_non_empty_string(payload.get("phraseId")):
                result.add("invalid-identifier")
            if not is_required_enum(payload.get("stage"), WAKE_PHRASE_STAGES) or (
                "confidence" in payload and not is_unit_interval(payload["confidence"])
            ):
                result.add("invalid-enum")
        elif arm == "batchProgress":
            processed, total = payload.get("processedAudioMs", 0), payload.get("totalAudioMs", 0)
            if not (is_uint32(processed) and is_uint32(total) and valid_progress(processed, total)):
                result.add("invalid-progress")
        return result
    if message == "EngineEvent":
        result = common_violations(value, "sequence", "engineId")
        if not is_uint64_string(value.get("monotonicTimeUs")):
            result.add("invalid-uint64")
        present = ENGINE_EVENT_ARMS.intersection(value)
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
        return result | engine_payload_violations(arm, payload)
    if message == "EngineControl":
        result = common_violations(value, "requestSequence", "engineId")
        present = ENGINE_CONTROL_ARMS.intersection(value)
        if not present:
            result.add("missing-engine-command")
            return result
        if len(present) > 1:
            result.add("ambiguous-engine-command")
            return result
        arm = next(iter(present))
        body = value[arm]
        if not isinstance(body, dict):
            result.add("invalid-enum")
            return result
        return result | engine_command_violations(arm, body)
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
            if "mode" in body and not is_known_enum(body["mode"], CAPTURE_MODES):
                result.add("invalid-enum")
            if "source" in body and not valid_source(body["source"]):
                result.add("invalid-enum")
            if "requestedFormat" in body and not valid_audio_format(body["requestedFormat"]):
                result.add("invalid-enum")
            if "engineId" in body and not is_non_empty_string(body["engineId"]):
                result.add("invalid-identifier")
        if arm == "speakerVerification" and not is_required_enum(body.get("mode"), SPEAKER_VERIFICATION_MODES):
            result.add("invalid-enum")
        if arm == "startBatch":
            if not is_non_empty_string(body.get("engineId")):
                result.add("invalid-identifier")
            audio_format = body.get("format")
            if not valid_audio_format(audio_format) or (
                audio_format["encoding"] == "AUDIO_ENCODING_OPUS" and audio_format.get("frameDurationMs", 0) < 1
            ) or ("totalAudioMs" in body and not is_uint32(body["totalAudioMs"])):
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


def transcript_violations(payload: dict[str, Any]) -> set[str]:
    result: set[str] = set()
    kind = payload.get("kind")
    if not is_known_enum(kind, TRANSCRIPT_KINDS) or not isinstance(payload.get("text"), str):
        result.add("invalid-enum")
    elif "speakerVerification" in payload and (
        not is_known_enum(payload["speakerVerification"], SPEAKER_VERIFICATION_RESULTS)
        or (is_set(payload, "speakerVerification") and payload["speakerVerification"] not in SPEAKER_RESULTS_BY_KIND[kind])
    ):
        result.add("invalid-enum")
    if "words" in payload and not valid_words(payload["words"]):
        result.add("invalid-word-timing")
    return result


def valid_words(words: Any) -> bool:
    if not isinstance(words, list):
        return False
    previous_start = 0
    for word in words:
        if not isinstance(word, dict) or not isinstance(word.get("text"), str):
            return False
        start, end = word.get("startOffsetMs", 0), word.get("endOffsetMs", 0)
        if not is_uint32(start) or not is_uint32(end) or start > end or start < previous_start:
            return False
        if "confidence" in word and not is_unit_interval(word["confidence"]):
            return False
        previous_start = start
    return True


def engine_payload_violations(arm: str, payload: dict[str, Any]) -> set[str]:
    result: set[str] = set()
    if arm == "engineStatus":
        engine = payload.get("engine")
        readiness = payload.get("readiness")
        if not isinstance(engine, dict) or not is_required_enum(readiness, ENGINE_READINESS):
            result.add("invalid-enum")
            return result
        locality = engine.get("locality")
        capabilities = engine.get("capabilities", [])
        platform_valid = (
            is_required_enum(engine.get("platform"), ENGINE_PLATFORMS)
            if locality == "ENGINE_LOCALITY_ON_DEVICE"
            else "platform" not in engine or is_known_enum(engine["platform"], ENGINE_PLATFORMS)
        )
        if not (
            is_required_enum(locality, ENGINE_LOCALITIES) and platform_valid
            and isinstance(capabilities, list) and all(is_non_empty_string(token) for token in capabilities)
        ):
            result.add("invalid-enum")
        if not valid_outcome(
            payload, readiness == "ENGINE_READINESS_FAILED",
            error_allowed=readiness == "ENGINE_READINESS_NOT_READY",
        ):
            result.add("invalid-outcome")
    elif arm == "voicePackStatus":
        components = payload.get("components", [])
        if not isinstance(components, list) or not all(isinstance(item, dict) for item in components):
            result.add("invalid-enum")
            return result
        items = [("packId", payload)] + [("componentId", component) for component in components]
        for id_field, item in items:
            if not is_non_empty_string(item.get(id_field)):
                result.add("invalid-identifier")
            state = item.get("state")
            if not is_required_enum(state, VOICE_PACK_STATES) or (
                id_field == "componentId" and not is_required_enum(item.get("kind"), VOICE_PACK_COMPONENT_KINDS)
            ):
                result.add("invalid-enum")
            elif not valid_outcome(item, state == "VOICE_PACK_STATE_FAILED"):
                result.add("invalid-outcome")
            completed, total = item.get("bytesCompleted", "0"), item.get("bytesTotal", "0")
            if not is_uint64_string(completed) or not is_uint64_string(total):
                result.add("invalid-uint64")
            elif not valid_progress(int(completed), int(total)):
                result.add("invalid-progress")
    elif arm == "microphoneStatus":
        if not is_non_empty_string(payload.get("sourceId")):
            result.add("invalid-identifier")
        readiness = payload.get("readiness")
        if not (
            is_required_enum(payload.get("permission"), MICROPHONE_PERMISSIONS)
            and is_required_enum(readiness, MICROPHONE_READINESS)
            and ("route" not in payload or is_known_enum(payload["route"], MICROPHONE_ROUTES))
            and ("interruption" not in payload or is_known_enum(payload["interruption"], MICROPHONE_INTERRUPTIONS))
            and is_set(payload, "interruption") == (readiness == "MICROPHONE_READINESS_INTERRUPTED")
        ):
            result.add("invalid-enum")
    elif arm == "speechOutput":
        if not is_non_empty_string(payload.get("outputId")):
            result.add("invalid-identifier")
        state = payload.get("state")
        if not is_required_enum(state, SPEECH_OUTPUT_STATES):
            result.add("invalid-enum")
        elif not valid_outcome(payload, state == "SPEECH_OUTPUT_STATE_FAILED"):
            result.add("invalid-outcome")
    return result


def engine_command_violations(arm: str, body: dict[str, Any]) -> set[str]:
    result: set[str] = set()
    if arm == "voicePack":
        if not is_non_empty_string(body.get("packId")):
            result.add("invalid-identifier")
        if not is_required_enum(body.get("action"), VOICE_PACK_ACTIONS):
            result.add("invalid-enum")
    elif arm == "speak":
        if not is_non_empty_string(body.get("outputId")) or not is_non_empty_string(body.get("text")):
            result.add("invalid-identifier")
        if ("fullDuplex" in body and not isinstance(body["fullDuplex"], bool)) or (
            "echoClearanceMs" in body and not is_uint32(body["echoClearanceMs"])
        ):
            result.add("invalid-enum")
    elif arm == "cancelSpeech" and not is_non_empty_string(body.get("outputId")):
        result.add("invalid-identifier")
    return result


def synthetic_texts(message: str, value: dict[str, Any]) -> list[Any]:
    """Free text that fixtures must mark as synthetic."""
    if message == "RuntimeEvent" and isinstance(value.get("transcript"), dict):
        transcript = value["transcript"]
        words = transcript.get("words")
        return [transcript.get("text")] + [
            word.get("text") for word in (words if isinstance(words, list) else []) if isinstance(word, dict)
        ]
    if message == "EngineControl" and isinstance(value.get("speak"), dict):
        return [value["speak"].get("text")]
    return []


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
    assert manifest.get("protocol") == {"major": 1, "minor": 1}, "unexpected conformance protocol"
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
        routing_id: str | None = None
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
                current_routing = value.get(ROUTING_FIELDS[message])
                if is_non_empty_string(current_routing):
                    routing_id = routing_id or current_routing
                    assert current_routing == routing_id, f"fixture changed {ROUTING_FIELDS[message]} at {location}"
            ordering_field = ORDERING_FIELDS.get(message)
            if ordering_field and not violations:
                current = int(value[ordering_field])
                ordered = previous is None or current > previous
                if fixture_set.get("rejection") == "order" and line_number >= reject_line:
                    assert not ordered, f"{location}: expected ordering rejection"
                else:
                    assert ordered, f"{location}: ordering key must increase"
                if ordered:
                    previous = current
            for text in synthetic_texts(message, value):
                if isinstance(text, str) and text:
                    assert "synthetic" in text.lower(), f"non-synthetic text at {location}"
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
    total_lines = sum(fixture_set["lines"] for fixture_set in fixture_sets)
    print(
        "Murmur protocol fixtures and connector manifests are consistent "
        f"({len(fixture_sets)} sets, {total_lines} lines)."
    )


if __name__ == "__main__":
    main()
