import copy
import json
import sys
import unittest
from pathlib import Path
from typing import Any

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PACKAGE_ROOT / "src"))

from murmur_protocol import AudioFrame, RuntimeEvent, SessionControl, VoiceSource  # noqa: E402

PARSERS = {
    "RuntimeEvent": RuntimeEvent.from_dict,
    "SessionControl": SessionControl.from_dict,
    "AudioFrame": AudioFrame.from_dict,
    "VoiceSource": VoiceSource.from_dict,
}
ORDER_FIELDS = {
    "RuntimeEvent": "sequence",
    "SessionControl": "request_sequence",
    "AudioFrame": "sequence",
}


def _remove_path(value: dict[str, Any], path: str) -> None:
    parts = path.split("/")
    current: Any = value
    for part in parts[:-1]:
        if not isinstance(current, dict) or part not in current:
            return
        current = current[part]
    if isinstance(current, dict):
        current.pop(parts[-1], None)


class ConformanceTest(unittest.TestCase):
    def test_manifest(self) -> None:
        conformance = REPOSITORY_ROOT / "conformance"
        manifest = json.loads((conformance / "manifest.json").read_text(encoding="utf-8"))
        for fixture_set in manifest["fixtureSets"]:
            path = conformance / fixture_set["path"]
            lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line]
            self.assertEqual(len(lines), fixture_set["lines"], f"python · {fixture_set['name']} · count")
            previous: int | None = None
            reject_line = fixture_set.get("rejectLine", 1)
            for line_number, line in enumerate(lines, start=1):
                label = f"python · {fixture_set['name']} · line {line_number}"
                with self.subTest(set=fixture_set["name"], line=line_number):
                    source = json.loads(line)
                    try:
                        parsed = PARSERS[fixture_set["message"]](source)
                    except (TypeError, ValueError, KeyError) as error:
                        should_reject = (
                            fixture_set["expect"] == "reject"
                            and fixture_set["rejection"] == "parse"
                            and line_number >= reject_line
                        )
                        self.assertTrue(should_reject, f"{label} · {error}")
                        continue
                    if (
                        fixture_set["expect"] == "reject"
                        and fixture_set["rejection"] == "parse"
                        and line_number >= reject_line
                    ):
                        self.fail(f"{label} · expected {fixture_set['reason']}")

                    order_field = ORDER_FIELDS.get(fixture_set["message"])
                    if order_field is not None:
                        current = getattr(parsed, order_field)
                        ordered = previous is None or current > previous
                        if (
                            fixture_set["expect"] == "reject"
                            and fixture_set["rejection"] == "order"
                            and line_number >= reject_line
                        ):
                            self.assertFalse(ordered, f"{label} · {fixture_set['reason']}")
                        else:
                            self.assertTrue(ordered, f"{label} · ordering")
                        if ordered:
                            previous = current

                    expected = copy.deepcopy(source)
                    actual = parsed.to_dict()
                    for unknown_path in fixture_set.get("unknownFields", []):
                        _remove_path(expected, unknown_path)
                        _remove_path(actual, unknown_path)
                    self.assertEqual(actual, expected, f"{label} · round-trip")


if __name__ == "__main__":
    unittest.main()
