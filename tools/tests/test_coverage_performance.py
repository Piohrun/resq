from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from verify_coverage_performance import summarize, verify  # noqa: E402


class CoveragePerformanceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = json.loads(
            (ROOT / "tests/contracts/coverage-performance-baseline.json").read_text(
                encoding="utf-8"
            )
        )

    def test_checked_pre_fix_samples_recompute_to_recorded_medians(self) -> None:
        workload = self.baseline["workload"]
        payload = {
            "samples": self.baseline["preFix"]["samples"],
            "iterations": workload["iterations"],
            "reportContexts": workload["reportContexts"],
            "metricsPerContext": workload["metricsPerContext"],
        }
        observed = summarize(payload)
        for name, expected in self.baseline["preFix"]["medians"].items():
            self.assertAlmostEqual(float(expected), observed[name], places=6)

    def test_policy_accepts_improvement_and_rejects_old_costs(self) -> None:
        improved = {
            "statementOverheadRatio": 4.5,
            "contextOverheadRatio": 18.0,
            "reportNsPerEntry": 3300.0,
        }
        self.assertEqual([], verify(improved, self.baseline))
        failures = verify(
            {
                "statementOverheadRatio": 5.3,
                "contextOverheadRatio": 42.0,
                "reportNsPerEntry": 109000.0,
            },
            self.baseline,
        )
        self.assertTrue(any("statementOverheadRatio" in item for item in failures))
        self.assertTrue(any("contextOverheadRatio" in item for item in failures))
        self.assertTrue(any("reportNsPerEntry" in item for item in failures))


if __name__ == "__main__":
    unittest.main()
