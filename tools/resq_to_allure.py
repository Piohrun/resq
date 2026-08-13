#!/usr/bin/env python3
"""Convert resQ report v2 into Allure 2 result files without runtime plugins."""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from validate_report import validate


STATUS = {
    "pass": "passed",
    "fail": "failed",
    "error": "broken",
    "skip": "skipped",
    "pending": "skipped",
}


def epoch_millis(timestamp: str) -> int:
    parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    return int(parsed.timestamp() * 1000)


def result_uuid(run_id: str, test_id: str, case_id: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"resq:{run_id}:{test_id}:{case_id}"))


def detail(row: dict[str, Any]) -> dict[str, Any]:
    message = row.get("message") or (row.get("failures") or [""])[0]
    trace_parts = [str(item) for item in row.get("failures", [])]
    if row.get("output"):
        trace_parts.append(str(row["output"]))
    return {
        "known": False,
        "muted": False,
        "flaky": bool(row.get("flaky")),
        "message": str(message),
        "trace": "\n".join(trace_parts),
    }


def labels(document: dict[str, Any], row: dict[str, Any]) -> list[dict[str, str]]:
    run = document["run"]
    result = [
        {"name": "suite", "value": str(row["suite"])},
        {"name": "framework", "value": f"resQ {document['frameworkVersion']}"},
        {"name": "language", "value": "q"},
        {"name": "host", "value": str(run.get("hostname", ""))},
        {"name": "package", "value": str(row.get("file", ""))},
    ]
    result.extend({"name": "tag", "value": str(tag)} for tag in row.get("tags", []))
    if row.get("flaky"):
        result.append({"name": "resq.flaky", "value": "true"})
    return result


def parameters(row: dict[str, Any]) -> list[dict[str, str]]:
    values = [{"name": "attempts", "value": str(row.get("attempts", 1))}]
    for name, value in sorted((row.get("parameters") or {}).items()):
        rendered = json.dumps(value, ensure_ascii=False, sort_keys=True) if isinstance(
            value, (dict, list, bool, int, float, type(None))
        ) else str(value)
        values.append({"name": str(name), "value": rendered})
    property_data = row.get("property") or {}
    if "seed" in property_data:
        values.append({"name": "propertySeed", "value": str(property_data["seed"])})
    if row.get("caseId"):
        values.append({"name": "caseId", "value": str(row["caseId"])})
    return values


def allure_result(document: dict[str, Any], row: dict[str, Any]) -> dict[str, Any]:
    run = document["run"]
    start = epoch_millis(run["startedAt"])
    stop = start + max(0, int(float(row.get("durationSeconds", 0)) * 1000))
    history_id = row["testId"] + (f":{row['caseId']}" if row.get("caseId") else "")
    full_name = f"{row['file']}::{row['suite']}::{row['description']}"
    return {
        "uuid": result_uuid(run["id"], row["testId"], str(row.get("caseId", ""))),
        "historyId": history_id,
        "testCaseId": row["testId"],
        "name": str(row["description"]),
        "fullName": full_name,
        "status": STATUS[row["status"]],
        "statusDetails": detail(row),
        "stage": "finished",
        "start": start,
        "stop": stop,
        "labels": labels(document, row),
        "parameters": parameters(row),
        "links": [],
    }


def convert(source: Path, destination: Path) -> int:
    document = json.loads(source.read_text(encoding="utf-8"))
    validate(document)
    destination.mkdir(parents=True, exist_ok=True)
    for row in document["tests"]:
        result = allure_result(document, row)
        path = destination / f"{result['uuid']}-result.json"
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    run = document["run"]
    executor = {
        "name": "resQ",
        "type": "local",
        "buildName": run["id"],
        "reportName": f"resQ {document['frameworkVersion']}",
    }
    (destination / "executor.json").write_text(
        json.dumps(executor, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    environment = {
        "resQ": document["frameworkVersion"],
        "q": run.get("qVersion", ""),
        "qRelease": run.get("qRelease", ""),
        "os": run.get("os", ""),
        "commit": run.get("vcs", {}).get("sha", ""),
        "branch": run.get("vcs", {}).get("branch", ""),
    }
    (destination / "environment.properties").write_text(
        "".join(f"{key}={str(value).replace(chr(10), ' ')}\n" for key, value in environment.items()),
        encoding="utf-8",
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="resQ test-results.json")
    parser.add_argument("output", type=Path, help="Allure results directory")
    args = parser.parse_args()
    try:
        return convert(args.report, args.output)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        print(f"resq-to-allure: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
