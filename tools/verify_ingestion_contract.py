#!/usr/bin/env python3
"""Execute the normalized resQ ingestion contract against SQLite/PostgreSQL."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from copy import deepcopy
from pathlib import Path
from typing import Any

from ingestion_contract import (
    QUERIES, TABLES, execute_ddl, execute_queries, load_payload, query_sql,
)
from render_ingestion_assets import expected_assets
from resq_to_tables import table_contract
from review_corpus import coverage_artifact, scale_report


ROOT = Path(__file__).resolve().parents[1]
PARAMETERS = {"service": "orders", "environment": "test"}


def benchmark_record(report: dict[str, Any]) -> dict[str, Any]:
    benchmark_id = "benchmark_" + "5" * 32
    test_id = report["tests"][0]["testId"]
    comparison = {
        "benchmarkId": benchmark_id, "testId": test_id,
        "file": "tests/generated/review_scale.q", "suite": "review scale corpus",
        "description": "generated benchmark", "classification": "stable",
        "reason": "fixture", "baselineFound": True, "comparable": True,
        "environmentMatch": True, "workloadMatch": True,
        "environmentAccepted": False, "metric": "timeNs", "unit": "nanoseconds",
        "baselineMedian": 100.0, "currentMedian": 101.0,
        "relativeChangePercent": 1.0, "u": 4.0, "z": 0.0,
        "pValue": 0.5, "adjustedPValue": 0.5, "alpha": 0.05,
        "practicalEffectPercent": 5.0, "baselineRuns": 3, "currentRuns": 3,
        "numericStatus": {
            name: "finite" for name in (
                "baselineMedian", "currentMedian", "relativeChangePercent", "u", "z",
                "pValue", "adjustedPValue", "alpha", "practicalEffectPercent",
            )
        },
    }
    return {
        "benchmarkId": benchmark_id, "testId": test_id,
        "file": "tests/generated/review_scale.q", "suite": "review scale corpus",
        "description": "generated benchmark", "metric": "time", "unit": "nanoseconds",
        "runs": 3, "avgTimeMs": 0.101, "minTimeMs": 0.100,
        "medTimeMs": 0.101, "maxTimeMs": 0.102, "devTimeMs": 0.001,
        "avgSpaceBytes": 32.0, "maxSpaceBytes": 32.0,
        "timeLimitMs": None, "spaceLimitBytes": None,
        "workload": {"runs": 3, "warmup": 1, "gcBefore": True, "gcEach": False, "space": True},
        "samples": {"timeNs": [100000, 101000, 102000], "retainedBytes": [32, 32, 32], "heapGrowthBytes": [0, 0, 0]},
        "measurement": {"clock": "q .z.p", "space": "q -22!"},
        "environment": deepcopy(report["benchmarkAnalysis"]["environment"]),
        "comparison": comparison,
        "numericStatus": {
            "avgTimeMs": "finite", "minTimeMs": "finite", "medTimeMs": "finite",
            "maxTimeMs": "finite", "devTimeMs": "finite", "avgSpaceBytes": "finite",
            "maxSpaceBytes": "finite", "timeLimitMs": "notConfigured",
            "spaceLimitBytes": "notConfigured",
        },
    }


def populated_report() -> dict[str, Any]:
    report = scale_report(3, include_events=False, include_manifest=False)
    report["run"]["labels"] = {
        "artifactDigest": "sha256:fixture", "deploymentId": "deploy-42",
        "environment": "test", "service": "orders",
    }
    measurement = benchmark_record(report)
    report["performance"] = [measurement]
    report["tests"][0]["kind"] = "perf"
    report["tests"][0]["benchmark"] = {
        "benchmarkId": measurement["benchmarkId"], "testId": measurement["testId"],
        "file": measurement["file"], "suite": measurement["suite"],
        "description": measurement["description"], "status": "pass",
        "runs": measurement["runs"], "metric": measurement["metric"],
        "unit": measurement["unit"], "measurement": measurement["measurement"],
        "limits": {"timeLimitMs": None, "spaceLimitBytes": None},
        "workload": measurement["workload"], "samples": measurement["samples"],
        "comparison": measurement["comparison"],
    }
    report["diagnostics"] = [{
        "type": "ingestion.fixture", "severity": "warning", "phase": "report",
        "message": "fixture diagnostic", "data": {"source": "contract"},
    }]
    return report


def replace_run(value: Any, old: str, new: str) -> Any:
    if isinstance(value, str):
        return value.replace(old, new)
    if isinstance(value, list):
        return [replace_run(item, old, new) for item in value]
    if isinstance(value, dict):
        return {key: replace_run(item, old, new) for key, item in value.items()}
    return value


def assert_loaded(connection: Any, dialect: str, payloads: list[dict[str, Any]]) -> None:
    expected = {
        table.source: sum(len(payload["tables"][table.source]) for payload in payloads)
        for table in TABLES
    }
    for table in TABLES:
        if dialect == "sqlite":
            count = connection.execute(f"SELECT COUNT(*) FROM {table.name}").fetchone()[0]
        else:
            with connection.cursor() as cursor:
                cursor.execute(f"SELECT COUNT(*) FROM {table.name}")
                count = cursor.fetchone()[0]
        if count != expected[table.source]:
            raise AssertionError(f"{dialect} {table.name}: expected {expected[table.source]}, got {count}")

    results = execute_queries(connection, dialect, PARAMETERS)
    if set(results) != {query.key for query in QUERIES}:
        raise AssertionError(f"{dialect}: query inventory drift")
    for key in (
        "pass_fail_rate", "run_duration", "test_history", "benchmark_history",
        "coverage_trend", "deployment_host", "coverage_context",
    ):
        if not results[key]:
            raise AssertionError(f"{dialect}: dashboard query {key} returned no fixture rows")
    correlation = results["deployment_host"][0]
    rendered = " ".join(str(value) for value in correlation)
    if "deploy-42" not in rendered or "contract-runner" not in rendered:
        raise AssertionError(f"{dialect}: labels and hostname did not survive the same query")


def verify_sqlite(empty: dict[str, Any], populated: dict[str, Any]) -> None:
    connection = sqlite3.connect(":memory:")
    try:
        execute_ddl(connection, "sqlite")
        load_payload(connection, "sqlite", empty)
        load_payload(connection, "sqlite", populated)
        assert_loaded(connection, "sqlite", [empty, populated])

        before = connection.execute("SELECT COUNT(*) FROM resq_runs").fetchone()[0]
        broken = replace_run(
            deepcopy(populated), populated["source"]["runId"], "run_" + "e" * 32,
        )
        broken["source"]["runId"] = "run_" + "e" * 32
        broken["tables"]["attempts"][0]["executionId"] = "test_" + "f" * 32
        try:
            load_payload(connection, "sqlite", broken)
        except sqlite3.IntegrityError:
            pass
        else:
            raise AssertionError("SQLite accepted an orphan attempt")
        after = connection.execute("SELECT COUNT(*) FROM resq_runs").fetchone()[0]
        if after != before:
            raise AssertionError("SQLite failed to roll back the rejected run transaction")

        dashboard = json.loads(
            (ROOT / "docs/examples/grafana-resq-overview.json").read_text(encoding="utf-8")
        )
        for panel in dashboard["panels"]:
            raw = panel["targets"][0]["rawSql"]
            executable = raw.replace("${service:sqlstring}", ":service").replace(
                "${environment:sqlstring}", ":environment"
            )
            connection.execute(executable, PARAMETERS).fetchall()
    finally:
        connection.close()


def verify_postgres(dsn: str, empty: dict[str, Any], populated: dict[str, Any]) -> None:
    try:
        import psycopg  # type: ignore[import-not-found]
        from psycopg import sql  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError("PostgreSQL contract requires psycopg 3") from exc
    schema = "resq_contract_" + uuid.uuid4().hex
    connection = psycopg.connect(dsn, autocommit=True)
    try:
        try:
            with connection.cursor() as cursor:
                cursor.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(schema)))
                cursor.execute(sql.SQL("SET search_path TO {}").format(sql.Identifier(schema)))
            execute_ddl(connection, "postgres")
            load_payload(connection, "postgres", empty)
            load_payload(connection, "postgres", populated)
            assert_loaded(connection, "postgres", [empty, populated])
            with connection.cursor() as cursor:
                cursor.execute("SELECT COUNT(*) FROM resq_runs")
                before = cursor.fetchone()[0]
            broken = replace_run(
                deepcopy(populated), populated["source"]["runId"], "run_" + "d" * 32,
            )
            broken["source"]["runId"] = "run_" + "d" * 32
            broken["tables"]["attempts"][0]["executionId"] = "test_" + "f" * 32
            try:
                load_payload(connection, "postgres", broken)
            except psycopg.IntegrityError:
                pass
            else:
                raise AssertionError("PostgreSQL accepted an orphan attempt")
            with connection.cursor() as cursor:
                cursor.execute("SELECT COUNT(*) FROM resq_runs")
                after = cursor.fetchone()[0]
            if after != before:
                raise AssertionError("PostgreSQL failed to roll back the rejected run transaction")
        except psycopg.Error as exc:
            raise RuntimeError(f"PostgreSQL ingestion contract failed: {exc}") from exc
    finally:
        with connection.cursor() as cursor:
            cursor.execute(sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(sql.Identifier(schema)))
        connection.close()


def verify_cli(report: dict[str, Any], coverage: dict[str, Any]) -> None:
    with tempfile.TemporaryDirectory(prefix="resq-ingestion-cli-") as raw:
        root = Path(raw)
        report_path, coverage_path = root / "report.json", root / "coverage.json"
        database, tables_path = root / "warehouse.sqlite", root / "tables.json"
        report_path.write_text(json.dumps(report, allow_nan=False), encoding="utf-8")
        coverage_path.write_text(json.dumps(coverage, allow_nan=False), encoding="utf-8")
        completed = subprocess.run(
            [
                sys.executable, str(ROOT / "tools/resq_ingest.py"), str(report_path),
                "--coverage", str(coverage_path), "--sqlite", str(database),
                "--tables-out", str(tables_path),
            ],
            check=False, capture_output=True, text=True, timeout=30,
        )
        if completed.returncode:
            raise AssertionError(f"reference ingestion command failed: {completed.stderr}")
        normalized = json.loads(tables_path.read_text(encoding="utf-8"))
        if normalized["source"]["runId"] != report["run"]["id"]:
            raise AssertionError("reference ingestion command changed run identity")
        with sqlite3.connect(database) as connection:
            if connection.execute("SELECT COUNT(*) FROM resq_runs").fetchone()[0] != 1:
                raise AssertionError("reference ingestion command did not commit one run")


def verify_assets() -> None:
    for path, expected in expected_assets().items():
        if path.read_text(encoding="utf-8") != expected:
            raise AssertionError(f"generated ingestion asset is stale: {path.relative_to(ROOT)}")
    dashboard = json.loads(
        (ROOT / "docs/examples/grafana-resq-overview.json").read_text(encoding="utf-8")
    )
    rendered = json.dumps(dashboard)
    if '"expr"' in rendered or "resq_tests_total" in rendered:
        raise AssertionError("Grafana example still references an unshipped Prometheus metric")
    dashboard_sql = {panel["title"]: panel["targets"][0]["rawSql"] for panel in dashboard["panels"]}
    expected_sql = {
        query.title: query_sql(query, "grafana")
        for query in QUERIES if query.key not in {"services", "environments"}
    }
    if dashboard_sql != expected_sql:
        raise AssertionError("dashboard queries differ from the executable SQL contract")


def verify(postgres_dsn: str | None = None) -> None:
    empty_report = scale_report(1)
    empty = table_contract(empty_report)
    report = populated_report()
    coverage = coverage_artifact(report)
    populated = table_contract(report, coverage)
    verify_assets()
    verify_sqlite(empty, populated)
    verify_cli(report, coverage)
    if postgres_dsn:
        verify_postgres(postgres_dsn, empty, populated)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--postgres-dsn", default=os.environ.get("RESQ_POSTGRES_DSN"))
    args = parser.parse_args()
    try:
        verify(args.postgres_dsn)
    except (
        OSError, RuntimeError, ValueError, KeyError, AssertionError,
        json.JSONDecodeError, sqlite3.DatabaseError, subprocess.SubprocessError,
    ) as exc:
        print(f"ingestion contract failed: {exc}", file=sys.stderr)
        return 1
    lanes = "SQLite + PostgreSQL" if args.postgres_dsn else "SQLite"
    print(f"ingestion contract passed: {lanes} DDL/load/query/dashboard transaction path")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
