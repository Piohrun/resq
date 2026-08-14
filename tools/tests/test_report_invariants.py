from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


class ReportInvariantTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(
            (ROOT / "tests/contracts/report-v2.json").read_text(encoding="utf-8")
        )

    def document(self) -> dict:
        return copy.deepcopy(self.contract)

    def assert_invalid(self, document: dict, message: str) -> None:
        with self.assertRaisesRegex(ValueError, message):
            validate(document)

    def add_complete_marker(self, document: dict) -> None:
        selected = document["run"]["shard"]["selectedExecutionIds"]
        document["run"]["completion"] = {
            "state": "complete",
            "complete": True,
            "truncated": False,
            "reason": "completed",
            "selectedTestCount": len(selected),
            "resultCount": len(document["tests"]),
            "missingExecutionIds": [],
        }

    def test_accepts_exact_complete_evidence(self) -> None:
        document = self.document()
        self.add_complete_marker(document)
        validate(document)

    def test_rejects_summary_status_drift(self) -> None:
        document = self.document()
        document["summary"]["passCount"] = 0
        document["summary"]["failCount"] = 1
        self.assert_invalid(document, "summary.passCount disagrees")

    def test_rejects_summary_assertion_drift(self) -> None:
        document = self.document()
        document["summary"]["assertionCount"] = 2
        self.assert_invalid(document, "summary.assertionCount disagrees")

    def test_rejects_run_duration_drift(self) -> None:
        document = self.document()
        document["run"]["durationSeconds"] = 2.0
        self.assert_invalid(document, "run.durationSeconds disagrees")

    def test_rejects_manifest_file_count_drift(self) -> None:
        document = self.document()
        document["run"]["shard"]["allFileCount"] = 2
        self.assert_invalid(document, "allFileCount disagrees")

    def test_rejects_selection_count_drift(self) -> None:
        document = self.document()
        document["run"]["selection"]["selectedTestCount"] = 2
        self.assert_invalid(document, "selectedTestCount disagrees")

    def test_rejects_false_complete_marker(self) -> None:
        document = self.document()
        self.add_complete_marker(document)
        document["run"]["completion"]["missingExecutionIds"] = [
            "test_cccccccccccccccccccccccccccccccc"
        ]
        self.assert_invalid(document, "missingExecutionIds")

    def test_accepts_explicit_fail_fast_subset(self) -> None:
        document = self.document()
        missing_id = "test_cccccccccccccccccccccccccccccccc"
        extra = copy.deepcopy(document["manifest"]["tests"][0])
        extra.update(
            executionId=missing_id,
            testId=missing_id,
            description="not reached after fail-fast",
            shardKey=missing_id,
        )
        document["manifest"]["tests"].append(extra)
        document["run"]["shard"]["selectedExecutionIds"].append(missing_id)
        document["run"]["selection"]["selectedTestCount"] = 2
        document["run"]["completion"] = {
            "state": "incomplete",
            "complete": False,
            "truncated": True,
            "reason": "failFast",
            "selectedTestCount": 2,
            "resultCount": 1,
            "missingExecutionIds": [missing_id],
        }
        validate(document)

    def test_rejects_verdict_error_diagnostic_in_green_report(self) -> None:
        document = self.document()
        document["diagnostics"] = [{
            "type": "framework",
            "severity": "error",
            "phase": "execution",
            "message": "hidden failure",
            "data": {},
        }]
        self.assert_invalid(document, "all-green report")

    def test_accepts_explicit_non_verdict_error_diagnostic(self) -> None:
        document = self.document()
        document["diagnostics"] = [{
            "type": "probe",
            "severity": "error",
            "phase": "self-test",
            "message": "expected probe failure",
            "data": {"expected": True},
        }]
        validate(document)

    def test_accepts_verdict_error_for_a_failed_non_test_gate(self) -> None:
        document = self.document()
        document.pop("manifest", None)
        document.pop("events", None)
        inventory = document["snapshotInventory"]
        inventory.update(enabled=True, complete=True, completenessReasons=[])
        inventory["gate"] = {
            "enabled": True,
            "passed": False,
            "reasons": ["obsolete-snapshots"],
        }
        document["diagnostics"] = [{
            "type": "snapshot",
            "severity": "error",
            "phase": "inventory",
            "message": "snapshot gate failed",
            "data": {},
        }]
        validate(document)


if __name__ == "__main__":
    unittest.main()
