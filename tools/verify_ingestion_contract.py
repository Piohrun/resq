#!/usr/bin/env python3
"""Validate normalized ingestion joins, schema shape, and example cardinality."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

from resq_to_tables import table_contract
from review_corpus import scale_report


ROOT = Path(__file__).resolve().parents[1]


def sample_coverage(test_id: str) -> dict[str, object]:
    return {
        "schemaVersion": 2,
        "framework": "resQ",
        "frameworkVersion": "1.8.0",
        "summary": {"functionsFound": 1, "functionsHit": 1},
        "files": [
            {
                "path": "src/orders.q",
                "loaded": True,
                "functionFound": 1,
                "functionHit": 1,
                "lineFound": 1,
                "lineHit": 1,
                "functions": [
                    {"name": ".orders.create", "line": 10, "hits": 1, "covered": True}
                ],
                "statementSites": [
                    {
                        "siteId": "site_statement_1",
                        "function": ".orders.create",
                        "line": 11,
                        "column": 4,
                        "eligible": True,
                        "instrumented": True,
                        "hits": 1,
                    }
                ],
                "branches": [
                    {
                        "siteId": "site_branch_1",
                        "function": ".orders.create",
                        "line": 12,
                        "column": 4,
                        "eligible": True,
                        "instrumented": True,
                        "edges": [
                            {"edgeId": "edge_true", "label": "true", "hits": 1, "covered": True},
                            {"edgeId": "edge_false", "label": "false", "hits": 0, "covered": False},
                        ],
                    }
                ],
            }
        ],
        "contextMeasurement": {
            "contexts": [
                {
                    "contextId": test_id,
                    "kind": "test",
                    "testId": test_id,
                    "attempt": 0,
                    "suite": "review scale corpus",
                    "description": "generated case 00000",
                    "file": "tests/generated/review_scale.q",
                    "metrics": [
                        {
                            "metricId": "metric_statement_1",
                            "kind": "statement",
                            "file": "src/orders.q",
                            "function": ".orders.create",
                            "siteId": "site_statement_1",
                            "edgeIndex": 0,
                            "edgeLabel": "",
                            "hits": 1,
                        }
                    ],
                }
            ]
        },
    }


def verify() -> None:
    report = scale_report(3)
    report["run"]["labels"] = {
        "artifactDigest": "sha256:fixture",
        "environment": "test",
        "service": "orders",
    }
    test_id = report["tests"][0]["testId"]
    payload = table_contract(report, sample_coverage(test_id))
    tables = payload["tables"]
    run_ids = {row["runId"] for row in tables["runs"]}
    tests = {(row["runId"], row["executionId"]): row for row in tables["tests"]}
    if len(run_ids) != 1 or len(tests) != 3:
        raise AssertionError("run/test normalization lost rows")
    for name, rows in tables.items():
        for row in rows:
            if row["runId"] not in run_ids:
                raise AssertionError(f"{name} has an orphan run: {row!r}")
    for row in tables["attempts"]:
        if (row["runId"], row["executionId"]) not in tests:
            raise AssertionError(f"attempt has an orphan execution: {row!r}")

    file_keys = {row["coverageFileKey"] for row in tables["coverageFiles"]}
    function_keys = {row["coverageFunctionKey"] for row in tables["coverageFunctions"]}
    site_keys = {row["coverageSiteKey"] for row in tables["coverageSites"]}
    context_keys = {row["coverageContextKey"] for row in tables["coverageContexts"]}
    if any(row["coverageFileKey"] not in file_keys for row in tables["coverageFunctions"]):
        raise AssertionError("coverage function has an orphan file")
    if any(row["coverageFunctionKey"] and row["coverageFunctionKey"] not in function_keys for row in tables["coverageSites"]):
        raise AssertionError("coverage site has an orphan function")
    if any(row["coverageSiteKey"] not in site_keys for row in tables["coverageEdges"]):
        raise AssertionError("coverage edge has an orphan site")
    if any(row["coverageContextKey"] not in context_keys for row in tables["coverageContextMetrics"]):
        raise AssertionError("coverage metric has an orphan context")
    if any(row["coverageSiteKey"] and row["coverageSiteKey"] not in site_keys for row in tables["coverageContextMetrics"]):
        raise AssertionError("coverage metric has an orphan site")

    schema = json.loads(
        (ROOT / "docs/schema/resq-ingestion-tables-v1.schema.json").read_text(encoding="utf-8")
    )
    expected_tables = set(schema["properties"]["tables"]["required"])
    if set(tables) != expected_tables:
        raise AssertionError("converter tables disagree with the published schema")

    dashboard_path = ROOT / "docs/examples/grafana-resq-overview.json"
    dashboard = json.loads(dashboard_path.read_text(encoding="utf-8"))
    rendered = json.dumps(dashboard)
    allowed_labels = {"service", "environment", "cluster", "region", "status", "kind", "provider", "le"}
    import re

    for grouping in re.findall(r"(?:by|without)\s*\(([^)]*)\)", rendered):
        labels = {label.strip() for label in grouping.split(",") if label.strip()}
        if not labels <= allowed_labels:
            raise AssertionError(f"dashboard uses high-cardinality labels: {sorted(labels - allowed_labels)}")
    for forbidden in ("runId=", "testId=", "caseId=", "file=", "message="):
        if forbidden in rendered:
            raise AssertionError(f"dashboard indexes forbidden label {forbidden[:-1]}")

    sql = (ROOT / "docs/examples/resq_ingestion.sql").read_text(encoding="utf-8")
    for required in ("resq_runs", "resq_tests", "resq_attempts", "resq_coverage_sites", "FOREIGN KEY"):
        if required not in sql:
            raise AssertionError(f"reference SQL is missing {required}")

    with tempfile.TemporaryDirectory(prefix="resq-ingestion-") as raw:
        rendered_path = Path(raw) / "tables.json"
        rendered_path.write_text(json.dumps(payload), encoding="utf-8")
        round_trip = json.loads(rendered_path.read_text(encoding="utf-8"))
        if round_trip["source"]["runId"] not in run_ids:
            raise AssertionError("normalized artifact did not round-trip")


def main() -> int:
    verify()
    print("ingestion contract verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
