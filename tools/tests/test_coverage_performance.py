from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from verify_coverage_performance import PREFIX, run_probe, summarize, verify  # noqa: E402


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

    def test_probe_routes_all_state_outside_the_checkout(self) -> None:
        payload = {
            "schemaVersion": 1,
            "kind": "resq-coverage-performance-probe",
        }
        completed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=PREFIX + json.dumps(payload) + "\n",
        )
        with patch("verify_coverage_performance.subprocess.run", return_value=completed) as mocked:
            self.assertEqual(payload, run_probe("q"))
        command = mocked.call_args.args[0]
        for flag in (
            "-state-file", "-flake-history", "-quarantine-file", "-flake-proposal-file",
        ):
            self.assertIn(flag, command)
            state_path = Path(command[command.index(flag) + 1])
            self.assertIn("resq-coverage-performance-", str(state_path.parent))


if __name__ == "__main__":
    unittest.main()
