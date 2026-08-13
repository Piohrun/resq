from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from resq_to_tables import table_contract  # noqa: E402
from review_corpus import scale_report  # noqa: E402


class IngestionTests(unittest.TestCase):
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
            (ROOT / "docs/schema/resq-ingestion-tables-v1.schema.json").read_text(encoding="utf-8")
        )
        self.assertEqual(
            set(payload["tables"]),
            set(schema["properties"]["tables"]["required"]),
        )
