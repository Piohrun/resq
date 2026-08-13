#!/usr/bin/env python3
"""Reconcile an isolated correctness report with a coverage-lane report."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


SUMMARY_KEYS = (
    "suiteCount", "testCount", "assertionCount", "passCount", "failCount",
    "errorCount", "skipCount",
)
ROW_KEYS = (
    "testId", "caseId", "suite", "description", "file", "status", "assertsRun",
)
DOCUMENTED_DIFFERENCES = (
    "run identity and timestamps",
    "wall-clock and per-test durations",
    "coverage configuration, diagnostics, events, and artifacts",
    "isolation process metadata",
)


def execution_id(row: dict[str, Any]) -> str:
    return str(row.get("caseId") or row.get("testId") or row.get("executionId") or "")


def rows_by_identity(document: dict[str, Any], label: str) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for row in document["tests"]:
        identity = execution_id(row)
        if not identity or identity in rows:
            raise ValueError(f"{label}: missing or duplicate execution identity {identity!r}")
        rows[identity] = row
    return rows


def reconcile_reports(
    correctness: dict[str, Any], coverage: dict[str, Any]
) -> dict[str, Any]:
    validate(correctness)
    validate(coverage)
    if correctness.get("profile", "full") != "full" or coverage.get("profile", "full") != "full":
        raise ValueError("coverage reconciliation requires full report profiles")
    if correctness.get("coverage"):
        raise ValueError("correctness lane must not contain source-coverage evidence")
    if not coverage.get("coverage", {}).get("enabled"):
        raise ValueError("coverage lane lacks enabled source-coverage evidence")
    if not correctness.get("run", {}).get("config", {}).get("isolate"):
        raise ValueError("correctness lane must be isolated")
    if coverage.get("run", {}).get("config", {}).get("isolate"):
        raise ValueError("coverage lane must be non-isolated")

    for key in ("framework", "frameworkVersion"):
        if correctness.get(key) != coverage.get(key):
            raise ValueError(f"lane {key} differs")
    for key in ("revision", "digest"):
        if correctness["manifest"].get(key) != coverage["manifest"].get(key):
            raise ValueError(f"lane manifest {key} differs")
    correctness_selected = [
        row["executionId"] for row in correctness["manifest"]["tests"] if row.get("selected")
    ]
    coverage_selected = [
        row["executionId"] for row in coverage["manifest"]["tests"] if row.get("selected")
    ]
    if correctness_selected != coverage_selected:
        raise ValueError("lane selected test inventory differs")
    for key in SUMMARY_KEYS:
        if correctness["summary"].get(key) != coverage["summary"].get(key):
            raise ValueError(f"lane summary {key} differs")

    correctness_rows = rows_by_identity(correctness, "correctness lane")
    coverage_rows = rows_by_identity(coverage, "coverage lane")
    if set(correctness_rows) != set(coverage_rows):
        raise ValueError("lane execution inventory differs")
    for identity in sorted(correctness_rows):
        left = correctness_rows[identity]
        right = coverage_rows[identity]
        for key in ROW_KEYS:
            if left.get(key) != right.get(key):
                raise ValueError(f"lane execution {identity} field {key} differs")

    return {
        "schemaVersion": 1,
        "kind": "resq-coverage-reconciliation",
        "framework": correctness["framework"],
        "frameworkVersion": correctness["frameworkVersion"],
        "matched": True,
        "correctnessRunId": correctness["run"]["id"],
        "coverageRunId": coverage["run"]["id"],
        "manifestDigest": correctness["manifest"]["digest"],
        "inventory": {
            "tests": correctness["summary"]["testCount"],
            "assertions": correctness["summary"]["assertionCount"],
            "passes": correctness["summary"]["passCount"],
            "failures": correctness["summary"]["failCount"],
            "errors": correctness["summary"]["errorCount"],
            "skips": correctness["summary"]["skipCount"],
        },
        "comparedExecutionFields": list(ROW_KEYS),
        "allowedDifferences": list(DOCUMENTED_DIFFERENCES),
    }


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected JSON object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("correctness", type=Path, help="isolated correctness test-results.json")
    parser.add_argument("coverage", type=Path, help="non-isolated coverage test-results.json")
    parser.add_argument("--out", type=Path, help="write reconciliation evidence")
    args = parser.parse_args()
    try:
        result = reconcile_reports(load(args.correctness), load(args.coverage))
        rendered = json.dumps(result, indent=2) + "\n"
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(rendered, encoding="utf-8")
        else:
            print(rendered, end="")
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        print(f"coverage reconciliation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
