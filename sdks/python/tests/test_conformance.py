import json
import sys
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE_ROOT / "src"))

from murmur_protocol import PayloadKind, RuntimeEvent  # noqa: E402


class ConformanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        fixture = Path(__file__).resolve().parents[3] / "conformance/fixtures/runtime-events.jsonl"
        cls.lines = [line for line in fixture.read_text(encoding="utf-8").splitlines() if line]

    def test_parses_and_preserves_shared_fixtures(self) -> None:
        events = [RuntimeEvent.from_json(line) for line in self.lines]
        self.assertEqual(len(events), 7)
        self.assertEqual([event.sequence for event in events], list(range(1, 8)))
        self.assertEqual(events[3].kind, PayloadKind.TRANSCRIPT)
        self.assertEqual(events[3].payload["text"], "synthetic hello")
        for event, line in zip(events, self.lines, strict=True):
            self.assertEqual(event.to_dict(), json.loads(line))

    def test_rejects_unknown_or_ambiguous_payloads(self) -> None:
        base = {
            "protocol": {"major": 1, "minor": 0},
            "sessionId": "test",
            "sequence": "1",
            "monotonicTimeUs": "1",
        }
        with self.assertRaises(ValueError):
            RuntimeEvent.from_dict({**base, "unknownEvent": {}})
        with self.assertRaises(ValueError):
            RuntimeEvent.from_dict(
                {**base, "captureReadiness": {"live": True}, "audioLevel": {"amplitude": 0.5}}
            )


if __name__ == "__main__":
    unittest.main()
