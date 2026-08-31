#!/usr/bin/env python3
"""Validate shared fixtures without requiring a language SDK."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_FIELDS = {
    "sessionStateChanged",
    "captureReadiness",
    "audioLevel",
    "transcript",
    "error",
    "intentProposal",
    "confirmationRequest",
    "actionResult",
}


def main() -> None:
    manifest = json.loads((ROOT / "conformance/manifest.json").read_text(encoding="utf-8"))
    protocol = manifest["protocol"]
    assert protocol == {"major": 1, "minor": 0}, "unexpected conformance protocol version"

    for fixture_set in manifest["fixtureSets"]:
        path = ROOT / "conformance" / fixture_set["path"]
        lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line]
        assert len(lines) == fixture_set["events"], f"incorrect event count in {path}"
        previous_sequence = 0
        session_id: str | None = None
        for line_number, line in enumerate(lines, start=1):
            event = json.loads(line)
            assert event["protocol"] == protocol, f"protocol mismatch at {path}:{line_number}"
            assert isinstance(event["sequence"], str), f"sequence must be a string at {path}:{line_number}"
            assert isinstance(event["monotonicTimeUs"], str), (
                f"monotonicTimeUs must be a string at {path}:{line_number}"
            )
            sequence = int(event["sequence"])
            assert sequence > previous_sequence, f"sequence must increase at {path}:{line_number}"
            previous_sequence = sequence
            session_id = session_id or event["sessionId"]
            assert event["sessionId"] == session_id, f"fixture changed sessions at {path}:{line_number}"
            present = PAYLOAD_FIELDS.intersection(event)
            assert len(present) == 1, f"expected one payload at {path}:{line_number}"

    connector = json.loads((ROOT / "connectors/omi/connector.json").read_text(encoding="utf-8"))
    assert connector["protocolMajor"] == protocol["major"], "connector protocol major mismatch"
    implementation = ROOT / connector["implementation"]["path"]
    assert implementation.is_dir(), "connector implementation path does not exist"

    print("Murmur protocol fixtures and connector manifests are consistent.")


if __name__ == "__main__":
    main()
