from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from self_coverage_trend import append_point, update_file, validate_trend  # noqa: E402


def artifact(timestamp: str = "2026-08-14T12:00:00.000000000Z") -> dict:
    return {
        "schemaVersion": 1,
        "kind": "resq-self-coverage",
        "framework": "resQ",
        "frameworkVersion": "1.8.0",
        "generatedAt": timestamp,
        "qVersion": "4.1",
        "measurement": {
            "basis": "logical lines and conditional/loop blocks",
            "complete": False,
            "gatingSupported": False,
        },
        "summary": {
            "functionsMeasured": 10, "functionsHit": 8,
            "logicalLinesMeasured": 20, "logicalLinesHit": 15,
            "blocksMeasured": 6, "blocksHit": 4,
        },
    }


class SelfCoverageTrendTests(unittest.TestCase):
    def test_appends_deduplicates_and_bounds_points(self) -> None:
        first = append_point(artifact(), limit=2)
        second = append_point(artifact("2026-08-14T13:00:00.000000000Z"), first, limit=2)
        duplicate = copy.deepcopy(artifact("2026-08-14T13:00:00.000000000Z"))
        duplicate["summary"]["functionsHit"] = 9
        third = append_point(duplicate, second, limit=2)
        self.assertEqual(2, len(third["points"]))
        self.assertEqual(9, third["points"][-1]["summary"]["functionsHit"])
        validate_trend(third)

    def test_rejects_impossible_counts_and_gating_claims(self) -> None:
        bad = artifact()
        bad["summary"]["blocksHit"] = 7
        with self.assertRaisesRegex(RuntimeError, "blocks"):
            append_point(bad)
        bad = artifact()
        bad["measurement"]["gatingSupported"] = True
        with self.assertRaisesRegex(RuntimeError, "partial and non-gating"):
            append_point(bad)

    def test_updates_file_atomically(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trend.json"
            update_file(path, artifact())
            result = update_file(path, artifact("2026-08-14T13:00:00.000000000Z"))
            self.assertEqual(2, len(result["points"]))
            self.assertFalse(path.with_suffix(".json.tmp").exists())


if __name__ == "__main__":
    unittest.main()
