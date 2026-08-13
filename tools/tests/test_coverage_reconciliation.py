from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from reconcile_coverage import reconcile_reports  # noqa: E402
from review_corpus import scale_report  # noqa: E402
from tools.tests.test_coverage_contract import report_coverage  # noqa: E402


def lanes() -> tuple[dict, dict]:
    correctness = scale_report(2)
    correctness["run"]["config"]["isolate"] = True
    coverage = copy.deepcopy(correctness)
    coverage["run"]["config"]["isolate"] = False
    coverage["run"]["config"]["runCoverage"] = True
    coverage["coverage"] = report_coverage()
    return correctness, coverage


class CoverageReconciliationTests(unittest.TestCase):
    def test_accepts_documented_lane_differences(self) -> None:
        correctness, coverage = lanes()
        result = reconcile_reports(correctness, coverage)
        self.assertTrue(result["matched"])
        self.assertEqual(2, result["inventory"]["tests"])
        self.assertIn("wall-clock and per-test durations", result["allowedDifferences"])

    def test_rejects_verdict_assertion_and_inventory_mutations(self) -> None:
        for field, value, message in (
            ("status", "fail", "status|passCount"),
            ("assertsRun", 2, "assertsRun|assertionCount"),
            ("description", "mutated", "description"),
        ):
            correctness, coverage = lanes()
            coverage["tests"][0][field] = value
            with self.assertRaisesRegex(ValueError, message):
                reconcile_reports(correctness, coverage)

    def test_rejects_wrong_lane_modes_and_manifest_drift(self) -> None:
        correctness, coverage = lanes()
        correctness["run"]["config"]["isolate"] = False
        with self.assertRaisesRegex(ValueError, "must be isolated"):
            reconcile_reports(correctness, coverage)

        correctness, coverage = lanes()
        coverage["manifest"]["digest"] = "manifest_" + "f" * 32
        with self.assertRaisesRegex(ValueError, "manifest (digest|identity)"):
            reconcile_reports(correctness, coverage)


if __name__ == "__main__":
    unittest.main()
