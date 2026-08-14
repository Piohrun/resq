from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from merge_shards import lifecycle  # noqa: E402
from validate_report import validate  # noqa: E402
from verify_report_scale import (  # noqa: E402
    LIFECYCLE_SCALE_SELECTOR,
    lifecycle_document,
    python_lifecycle_measurement,
)


class ReportScaleContractTests(unittest.TestCase):
    def test_lifecycle_topology_is_valid_complete_and_deterministic(self) -> None:
        document = lifecycle_document(23, 4, 3)
        document["events"] = lifecycle(
            document["run"], document["manifest"], document["tests"],
            document["summary"], document["coverage"], document["diagnostics"],
            document["snapshotInventory"], document["benchmarkAnalysis"],
        )
        validate(document)
        self.assertEqual(4, len(document["manifest"]["files"]))
        self.assertEqual(12, document["summary"]["suiteCount"])
        self.assertEqual(list(range(1, 129)), [event["sequence"] for event in document["events"]])
        benchmark = next(
            event for event in document["events"] if event["type"] == "benchmark.finished"
        )
        self.assertEqual(document["tests"][0]["finishedAt"], benchmark["occurredAt"])

    def test_lifecycle_measurement_carries_checked_qualification_contract(self) -> None:
        budgets = json.loads(
            (ROOT / "tests/contracts/report-scale-budgets.json").read_text(encoding="utf-8")
        )
        self.assertEqual(2, budgets["schemaVersion"])
        self.assertEqual(100_000, budgets["lifecycle"]["qualificationTests"])
        self.assertEqual(3, budgets["lifecycle"]["baselineSamples"])
        measurement = python_lifecycle_measurement(lifecycle_document(23, 4, 3))
        self.assertEqual(128, measurement["eventCount"])
        self.assertTrue(measurement["sequenceComplete"])
        self.assertTrue(measurement["benchmarkTimeCorrect"])
        self.assertEqual("lifecycle 100k near-linear", LIFECYCLE_SCALE_SELECTOR)


if __name__ == "__main__":
    unittest.main()
