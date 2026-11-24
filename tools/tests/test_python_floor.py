from __future__ import annotations

import re
import unittest
from datetime import timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from validate_report import parse_timestamp  # noqa: E402


class PythonFloorTests(unittest.TestCase):
    """The tools run on Python 3.8, which many CI images still ship.

    CI itself runs a newer Python, where the constructs below work, so they
    are checked for by name.
    """

    def test_nanosecond_timestamps_parse(self) -> None:
        parsed = parse_timestamp("2026-11-23T21:48:21.402222384Z")
        self.assertEqual(parsed.microsecond, 402222)
        self.assertEqual(parsed.tzinfo, timezone.utc)
        self.assertEqual(parse_timestamp("2026-11-23T21:48:21.4+00:00").microsecond, 400000)
        self.assertEqual(parse_timestamp("2026-11-23T21:48:21+00:00").microsecond, 0)

    def test_tools_use_nothing_newer_than_python_3_8(self) -> None:
        newer = {
            "datetime.fromisoformat(": "takes nanoseconds and Z only from 3.11; use validate_report.parse_timestamp",
            "strict=True": "zip(strict=) is 3.10",
            ".removeprefix(": "3.9",
            ".removesuffix(": "3.9",
        }
        allowed = {("validate_report.py", "datetime.fromisoformat(")}
        found = []
        for path in sorted((ROOT / "tools").glob("*.py")):
            text = path.read_text(encoding="utf-8")
            for token, why in newer.items():
                if token in text and (path.name, token) not in allowed:
                    found.append(f"{path.name}: {token} ({why})")
            if re.search(r"^\s*match\s+\S.*:\s*$", text, flags=re.M):
                found.append(f"{path.name}: match statement (3.10)")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
