from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))

from resq_to_tables import table_contract  # noqa: E402
from review_corpus import coverage_artifact, scale_report  # noqa: E402


class IngestionTests(unittest.TestCase):
    def test_tables_branch_and_run_join_contract(self) -> None:
        report = scale_report(1)
        run_id = report["run"]["id"]
        coverage = coverage_artifact(report)
        payload = table_contract(report, coverage)
        self.assertEqual(2, payload["schemaVersion"])
        self.assertEqual(run_id, payload["source"]["runId"])
        self.assertEqual(run_id, payload["tables"]["coverageRuns"][0]["runId"])
        self.assertEqual(
            {"hostname": report["run"]["hostname"],
             "qVersion": report["run"]["qVersion"], "os": report["run"]["os"]},
            {name: payload["tables"]["runs"][0][name]
             for name in ("hostname", "qVersion", "os")},
        )
        sites = {row["kind"]: row for row in payload["tables"]["coverageSites"]}
        self.assertEqual(1, sites["statement"]["hits"])
        self.assertNotIn("edgesHit", sites["statement"])
        self.assertEqual(1, sites["branch"]["edgesHit"])
        self.assertNotIn("hits", sites["branch"])

        legacy = table_contract(report, coverage, contract_version=1)
        legacy_branch = next(
            row for row in legacy["tables"]["coverageSites"] if row["kind"] == "branch"
        )
        self.assertEqual(1, legacy["schemaVersion"])
        self.assertEqual(1, legacy_branch["hits"])
        self.assertNotIn("edgesHit", legacy_branch)

        coverage["runId"] = "run_" + "f" * 32
        with self.assertRaisesRegex(ValueError, "runId differs"):
            table_contract(report, coverage)

    def test_table_contract_preserves_stable_run_and_execution_joins(self) -> None:
        report = scale_report(4)
        payload = table_contract(report)
        tables = payload["tables"]
        run_id = report["run"]["id"]
        self.assertEqual(tables["runs"][0]["runId"], run_id)
        self.assertEqual(
            {row["executionId"] for row in tables["tests"]},
            {row["testId"] for row in report["tests"]},
        )
        self.assertTrue(all(row["runId"] == run_id for row in tables["attempts"]))

    def test_published_ingestion_schema_names_every_converter_table(self) -> None:
        payload = table_contract(scale_report(1))
        schema = json.loads(
            (ROOT / "docs/schema/resq-ingestion-tables-v2.schema.json").read_text(encoding="utf-8")
        )
        self.assertEqual(2, schema["properties"]["schemaVersion"]["const"])
        self.assertEqual(
            set(payload["tables"]),
            set(schema["properties"]["tables"]["required"]),
        )
