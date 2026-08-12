#!/usr/bin/env python3
"""Dependency-free validator for the checked-in resQ report-v2 contract.

This intentionally validates the contract's required topology and invariants
without importing resQ or requiring a kdb+ licence. Full JSON Schema validators
may consume docs/schema/resq-report-v2.schema.json; CI can always run this file.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


HEX_ID = re.compile(r"^(?:run|test|case)_[0-9a-f]{32}$")
STATUSES = {"pass", "fail", "error", "skip", "pending"}


def require(obj: dict[str, Any], keys: set[str], where: str) -> None:
    missing = sorted(keys - obj.keys())
    if missing:
        raise ValueError(f"{where}: missing {', '.join(missing)}")


def iso8601(value: Any, where: str) -> None:
    if not isinstance(value, str):
        raise ValueError(f"{where}: expected ISO-8601 string")
    datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_test(row: Any, index: int) -> None:
    where = f"tests[{index}]"
    if not isinstance(row, dict):
        raise ValueError(f"{where}: expected object")
    require(
        row,
        {
            "suite", "description", "status", "message", "time",
            "durationSeconds", "failures", "assertsRun", "file", "line",
            "namespace", "tags", "output", "testId", "caseId", "kind",
            "attempts", "retried", "flaky", "attemptHistory",
            "parameterCases", "property", "diagnostics", "snapshots",
            "benchmark",
        },
        where,
    )
    if row["status"] not in STATUSES:
        raise ValueError(f"{where}.status: unknown value {row['status']!r}")
    if not isinstance(row["testId"], str) or not HEX_ID.fullmatch(row["testId"]):
        raise ValueError(f"{where}.testId: invalid stable identity")
    if not isinstance(row["attempts"], int) or row["attempts"] < 1:
        raise ValueError(f"{where}.attempts: expected positive integer")
    if not isinstance(row["retried"], bool) or not isinstance(row["flaky"], bool):
        raise ValueError(f"{where}: retry flags must be boolean")
    if row["flaky"] and (row["status"] != "pass" or row["attempts"] < 2):
        raise ValueError(f"{where}: flaky requires a late pass")
    if len(row["attemptHistory"]) not in (0, row["attempts"]):
        raise ValueError(f"{where}: attempt history must be empty or complete")
    if row["retried"] != (row["attempts"] > 1):
        raise ValueError(f"{where}: retried must agree with attempts")
    for attempt_index, attempt in enumerate(row["attemptHistory"], start=1):
        attempt_where = f"{where}.attemptHistory[{attempt_index - 1}]"
        require(
            attempt,
            {"attempt", "status", "duration", "durationSeconds", "message", "failures", "assertsRun"},
            attempt_where,
        )
        if attempt["attempt"] != attempt_index:
            raise ValueError(f"{attempt_where}.attempt: expected {attempt_index}")
        if attempt["status"] not in STATUSES:
            raise ValueError(f"{attempt_where}.status: unknown value")
    case_ids: list[str] = []
    case_indices: list[int] = []
    for case_index, case in enumerate(row["parameterCases"]):
        require(case, {"caseId", "index", "parameters", "status"}, f"{where}.parameterCases[{case_index}]")
        if not HEX_ID.fullmatch(case["caseId"]):
            raise ValueError(f"{where}.parameterCases[{case_index}].caseId: invalid")
        if case["status"] not in STATUSES:
            raise ValueError(f"{where}.parameterCases[{case_index}].status: unknown value")
        case_ids.append(case["caseId"])
        case_indices.append(case["index"])
    if len(case_ids) != len(set(case_ids)) or len(case_indices) != len(set(case_indices)):
        raise ValueError(f"{where}.parameterCases: identities and indices must be unique")
    property_data = row["property"]
    if property_data:
        require(
            property_data,
            {"seed", "runs", "maxFailRate", "failRate", "passCount", "failCount", "failedInputs", "shrunkInput"},
            f"{where}.property",
        )
        if property_data["passCount"] + property_data["failCount"] != property_data["runs"]:
            raise ValueError(f"{where}.property: pass/fail totals must equal runs")
    for snap_index, snapshot in enumerate(row["snapshots"]):
        require(snapshot, {"backend", "name", "status", "path", "timestamp"}, f"{where}.snapshots[{snap_index}]")
        iso8601(snapshot["timestamp"], f"{where}.snapshots[{snap_index}].timestamp")


def validate(document: Any) -> None:
    if not isinstance(document, dict):
        raise ValueError("report: expected object")
    require(
        document,
        {"schemaVersion", "framework", "frameworkVersion", "run", "summary", "tests", "performance", "coverage", "diagnostics"},
        "report",
    )
    if document["schemaVersion"] != 2 or document["framework"] != "resQ":
        raise ValueError("report: expected resQ schemaVersion 2")
    run = document["run"]
    require(run, {"id", "startedAt", "finishedAt", "durationSeconds", "hostname", "cwd", "qVersion", "qRelease", "os", "resqVersion", "vcs", "ci", "config"}, "run")
    if not HEX_ID.fullmatch(run["id"]):
        raise ValueError("run.id: invalid")
    iso8601(run["startedAt"], "run.startedAt")
    iso8601(run["finishedAt"], "run.finishedAt")
    summary = document["summary"]
    if run["resqVersion"] != document["frameworkVersion"]:
        raise ValueError("run.resqVersion does not match frameworkVersion")
    require(summary, {"suiteCount", "testCount", "assertionCount", "passCount", "failCount", "errorCount", "skipCount", "duration", "durationSeconds"}, "summary")
    if summary["testCount"] != len(document["tests"]):
        raise ValueError("summary.testCount does not match tests length")
    if summary["testCount"] != sum(summary[k] for k in ("passCount", "failCount", "errorCount", "skipCount")):
        raise ValueError("summary status counts do not add up")
    test_ids: list[str] = []
    case_ids: list[str] = []
    for index, row in enumerate(document["tests"]):
        validate_test(row, index)
        test_ids.append(row["testId"])
        case_ids.extend(case["caseId"] for case in row["parameterCases"])
    if len(test_ids) != len(set(test_ids)):
        raise ValueError("tests: duplicate testId")
    if len(case_ids) != len(set(case_ids)):
        raise ValueError("tests: duplicate parameter caseId")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    try:
        validate(json.loads(args.report.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        print(f"invalid resQ report: {exc}", file=sys.stderr)
        return 1
    print(f"valid resQ report v2: {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
