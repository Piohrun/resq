from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "tests/contracts/review/fable-findings.json"


class FableFindingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        cls.findings = cls.contract["findings"]

    def test_contract_identity_and_numbered_finding_coverage(self) -> None:
        self.assertEqual(1, self.contract["schemaVersion"])
        self.assertEqual("resq-fable-review-findings", self.contract["kind"])
        self.assertEqual(40, len(self.contract["baselineCommit"]))
        identifiers = [finding["id"] for finding in self.findings]
        self.assertEqual(len(identifiers), len(set(identifiers)))
        self.assertEqual(
            {f"FB-{index}" for index in range(1, 19)},
            {identifier for identifier in identifiers if identifier.startswith("FB-")},
        )
        self.assertEqual(
            {f"P3-{index}" for index in range(1, 20)},
            {identifier for identifier in identifiers if identifier.startswith("P3-")},
        )
        self.assertEqual({"A-1", "A-2", "A-3", "A-4"}, {
            identifier for identifier in identifiers if identifier.startswith("A-")
        })
        self.assertEqual({"DOC-1", "DOC-2", "DOC-3"}, {
            identifier for identifier in identifiers if identifier.startswith("DOC-")
        })

    def test_every_finding_has_a_real_baseline_probe_and_regression_target(self) -> None:
        for finding in self.findings:
            with self.subTest(finding=finding["id"]):
                self.assertIn(finding["status"], {"open", "closed"})
                self.assertIn(finding["release"], {"1.8.1", "2.0.0"})
                self.assertIn(finding["step"], range(1, 14))
                probe = finding["baselineProbe"]
                regression = finding["regression"]
                probe_path = ROOT / probe["path"]
                regression_path = ROOT / regression["path"]
                self.assertTrue(probe_path.is_file(), probe_path)
                self.assertTrue(regression_path.is_file(), regression_path)
                self.assertTrue(regression["selector"])
                source = probe_path.read_text(encoding="utf-8")
                if finding["status"] == "open":
                    for needle in probe.get("contains", []):
                        self.assertIn(needle, source)
                    for needle in probe.get("absent", []):
                        self.assertNotIn(needle, source)
                else:
                    # Closed must mean the fixed state is observable, not merely
                    # that a regression test exists. The baselineProbe needles
                    # locate the area and may legitimately survive the fix, so
                    # the fixed state carries its own closedProbe needles.
                    closed = finding.get("closedProbe")
                    if finding.get("severity") == "P0":
                        self.assertIsNotNone(
                            closed, f"{finding['id']}: P0 findings require a closedProbe"
                        )
                    if closed is not None:
                        closed_path = ROOT / closed.get("path", probe["path"])
                        closed_source = closed_path.read_text(encoding="utf-8")
                        for needle in closed.get("contains", []):
                            self.assertIn(
                                needle, closed_source,
                                f"{finding['id']}: fixed-state pattern missing",
                            )
                        for needle in closed.get("absent", []):
                            self.assertNotIn(
                                needle, closed_source,
                                f"{finding['id']}: baseline bug pattern still present",
                            )
                    regression_source = regression_path.read_text(encoding="utf-8")
                    self.assertIn(regression["selector"], regression_source)

    def test_release_slicing_keeps_compatible_integrity_fixes_in_1_8_1(self) -> None:
        releases = {finding["id"]: finding["release"] for finding in self.findings}
        for identifier in (
            "FB-1", "FB-2", "FB-3", "FB-4", "FB-6", "FB-7", "FB-8",
            "FB-10", "FB-14", "P3-2", "P3-17", "P3-18", "P3-19",
        ):
            self.assertEqual("1.8.1", releases[identifier])
        self.assertEqual("2.0.0", releases["FB-5"])


if __name__ == "__main__":
    unittest.main()
