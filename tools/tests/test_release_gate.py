from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

from tools.review_corpus import scale_report
from tools.verify_release_gate import private_state_args, reconcile_suites, verdict


class ReleaseGateContractTests(unittest.TestCase):
    def test_reconciliation_uses_execution_identity_and_ignores_only_timing(self) -> None:
        normal = scale_report(2)
        isolated = copy.deepcopy(normal)
        isolated["summary"]["duration"] = "0D00:00:01.000000000"
        isolated["summary"]["durationSeconds"] = 1.0
        isolated["summary"]["testDurationSumSeconds"] = 1.0
        isolated["tests"][0]["caseId"] = "case_" + "a" * 32
        normal["tests"][0]["caseId"] = isolated["tests"][0]["caseId"]
        isolated["tests"][0]["durationSeconds"] = 0.9
        isolated["tests"][0]["time"] = "0D00:00:00.900000000"
        with tempfile.TemporaryDirectory() as raw:
            receipt = reconcile_suites(normal, isolated, Path(raw) / "receipt.json")
        self.assertTrue(receipt["semanticInventoryParity"])
        self.assertEqual(2, len(verdict(normal)))

    def test_reconciliation_rejects_policy_state_drift(self) -> None:
        normal = scale_report(1)
        isolated = copy.deepcopy(normal)
        isolated["tests"][0]["quarantine"] = {
            "schemaVersion": 1,
            "state": "healthy",
        }
        with tempfile.TemporaryDirectory() as raw:
            with self.assertRaisesRegex(RuntimeError, "semantic test inventory"):
                reconcile_suites(normal, isolated, Path(raw) / "receipt.json")

    def test_private_state_paths_are_lane_scoped_and_complete(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            normal = private_state_args(root, "normal")
            isolated = private_state_args(root, "isolated")
            self.assertEqual(
                {
                    "-state-file", "-flake-history", "-quarantine-file",
                    "-flake-proposal-file",
                },
                set(normal[::2]),
            )
            self.assertTrue(all(str(root / "state") in path for path in normal[1::2]))
            self.assertTrue(set(normal[1::2]).isdisjoint(isolated[1::2]))


if __name__ == "__main__":
    unittest.main()
