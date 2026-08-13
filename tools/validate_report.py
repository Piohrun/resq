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
MANIFEST_ID = re.compile(r"^manifest_[0-9a-f]{32}$")
FILE_ID = re.compile(r"^file_[0-9a-f]{32}$")
SUITE_ID = re.compile(r"^suite_[0-9a-f]{32}$")
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
            "parameters",
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
    if not isinstance(row["caseId"], str) or (
        row["caseId"] and not HEX_ID.fullmatch(row["caseId"])
    ):
        raise ValueError(f"{where}.caseId: invalid stable identity")
    if row["kind"] == "case" and not row["caseId"]:
        raise ValueError(f"{where}: declarative case requires caseId")
    if not isinstance(row["parameters"], dict):
        raise ValueError(f"{where}.parameters: expected object")
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


def validate_manifest(manifest: Any, document: dict[str, Any]) -> None:
    if not isinstance(manifest, dict):
        raise ValueError("manifest: expected object")
    require(
        manifest,
        {
            "schemaVersion", "kind", "digest", "digestAlgorithm",
            "identityAlgorithm", "frameworkVersion", "revision", "shard",
            "files", "tests",
        },
        "manifest",
    )
    if manifest["schemaVersion"] != 2 or manifest["kind"] != "resq-execution-manifest":
        raise ValueError("manifest: expected resQ execution manifest v2")
    if not isinstance(manifest["digest"], str) or not MANIFEST_ID.fullmatch(manifest["digest"]):
        raise ValueError("manifest.digest: invalid")
    if manifest["digestAlgorithm"] != "md5-source-topology-v2":
        raise ValueError("manifest.digestAlgorithm: unsupported")
    if manifest["identityAlgorithm"] != "resq-test-case-id-v2":
        raise ValueError("manifest.identityAlgorithm: unsupported")
    if manifest["frameworkVersion"] != document["frameworkVersion"]:
        raise ValueError("manifest.frameworkVersion does not match report")
    if not isinstance(manifest["files"], list) or not isinstance(manifest["tests"], list):
        raise ValueError("manifest files/tests: expected arrays")
    file_ids: list[str] = []
    file_paths: list[str] = []
    shard_count = document["run"].get("shard", {}).get("count", 1)
    for index, entry in enumerate(manifest["files"]):
        where = f"manifest.files[{index}]"
        if not isinstance(entry, dict):
            raise ValueError(f"{where}: expected object")
        require(
            entry,
            {"fileId", "path", "sourceDigest", "assignedShard", "selected", "shardable"},
            where,
        )
        if not isinstance(entry["fileId"], str) or not FILE_ID.fullmatch(entry["fileId"]):
            raise ValueError(f"{where}.fileId: invalid")
        if not isinstance(entry["path"], str) or not entry["path"]:
            raise ValueError(f"{where}.path: expected non-empty string")
        if not isinstance(entry["sourceDigest"], str) or (
            entry["sourceDigest"] and not re.fullmatch(r"[0-9a-f]{32}", entry["sourceDigest"])
        ):
            raise ValueError(f"{where}.sourceDigest: invalid")
        unit = document["run"].get("shard", {}).get("unit", "file")
        if not isinstance(entry["assignedShard"], int):
            raise ValueError(f"{where}.assignedShard: outside shard range")
        valid_assignment = entry["assignedShard"] == -1 if unit != "file" else 0 <= entry["assignedShard"] < shard_count
        if not valid_assignment:
            raise ValueError(f"{where}.assignedShard: outside shard range")
        if not isinstance(entry["selected"], bool) or not isinstance(entry["shardable"], bool):
            raise ValueError(f"{where}: selection flags must be boolean")
        file_ids.append(entry["fileId"])
        file_paths.append(entry["path"])
    if len(file_ids) != len(set(file_ids)) or len(file_paths) != len(set(file_paths)):
        raise ValueError("manifest.files: duplicate identity or path")
    if file_paths != sorted(file_paths):
        raise ValueError("manifest.files: paths must be deterministically sorted")
    execution_ids: list[str] = []
    known_files = set(file_ids)
    for index, entry in enumerate(manifest["tests"]):
        where = f"manifest.tests[{index}]"
        if not isinstance(entry, dict):
            raise ValueError(f"{where}: expected object")
        require(
            entry,
            {"executionId", "testId", "caseId", "suiteId", "fileId", "file", "suite", "description", "line", "kind", "parameters", "tags", "shardKey", "assignedShard", "selected", "shardable"},
            where,
        )
        if not isinstance(entry["testId"], str) or not HEX_ID.fullmatch(entry["testId"]):
            raise ValueError(f"{where}.testId: invalid")
        if not isinstance(entry["suiteId"], str) or not SUITE_ID.fullmatch(entry["suiteId"]):
            raise ValueError(f"{where}.suiteId: invalid")
        if entry["fileId"] not in known_files and entry["file"]:
            raise ValueError(f"{where}.fileId: not present in file inventory")
        execution_id = entry["caseId"] or entry["testId"]
        if entry["executionId"] != execution_id or not HEX_ID.fullmatch(execution_id):
            raise ValueError(f"{where}.executionId: invalid or inconsistent")
        if not isinstance(entry["assignedShard"], int) or not 0 <= entry["assignedShard"] < shard_count:
            raise ValueError(f"{where}.assignedShard: outside shard range")
        if not isinstance(entry["selected"], bool) or not isinstance(entry["shardable"], bool):
            raise ValueError(f"{where}: selection flags must be boolean")
        run_shard_index = document["run"].get("shard", {}).get("index", 0)
        if run_shard_index >= 0 and entry["shardable"] and (
            entry["selected"] != (entry["assignedShard"] == run_shard_index)
        ):
            raise ValueError(f"{where}.selected: disagrees with shard assignment")
        if run_shard_index >= 0 and not entry["shardable"] and not entry["selected"]:
            raise ValueError(f"{where}.selected: run-level execution must be selected")
        execution_ids.append(execution_id)
    if len(execution_ids) != len(set(execution_ids)):
        raise ValueError("manifest.tests: duplicate executionId")
    report_execution_ids = [row["caseId"] or row["testId"] for row in document["tests"]]
    if not set(report_execution_ids).issubset(set(execution_ids)):
        raise ValueError("manifest.tests: report contains identity outside inventory")
    shard = document["run"].get("shard")
    if not isinstance(shard, dict):
        raise ValueError("run.shard: expected object")
    require(
        shard,
        {
            "index", "count", "unit", "algorithm", "allFileCount",
            "selectedFileCount", "allUnitCount", "selectedUnitCount",
            "selectedFiles", "selectedExecutionIds",
        },
        "run.shard",
    )
    if not isinstance(shard["count"], int) or shard["count"] < 1:
        raise ValueError("run.shard.count: expected positive integer")
    if shard["unit"] not in {"file", "test", "case"}:
        raise ValueError("run.shard.unit: unsupported")
    if shard["index"] == -1:
        if shard.get("merged") is not True or shard.get("indices") != list(range(shard["count"])):
            raise ValueError("run.shard: aggregate index requires a complete merged topology")
    elif not isinstance(shard["index"], int) or not 0 <= shard["index"] < shard["count"]:
        raise ValueError("run.shard.index: outside shard range")
    selected_ids = shard["selectedExecutionIds"]
    if not isinstance(selected_ids, list) or len(selected_ids) != len(set(selected_ids)):
        raise ValueError("run.shard.selectedExecutionIds: expected unique array")
    expected_selected = {
        entry["executionId"] for entry in manifest["tests"] if entry["selected"]
    }
    if set(selected_ids) != expected_selected:
        raise ValueError("run.shard.selectedExecutionIds: disagrees with manifest selection")


def validate_events(events: Any, document: dict[str, Any]) -> None:
    if not isinstance(events, list) or not events:
        raise ValueError("events: expected non-empty array")
    run_id = document["run"]["id"]
    for index, event in enumerate(events):
        where = f"events[{index}]"
        if not isinstance(event, dict):
            raise ValueError(f"{where}: expected object")
        require(
            event,
            {"schemaVersion", "sequence", "type", "runId", "entityId", "parentId", "occurredAt", "payload"},
            where,
        )
        if event["schemaVersion"] != 1:
            raise ValueError(f"{where}.schemaVersion: expected 1")
        if event["sequence"] != index + 1:
            raise ValueError(f"{where}.sequence: expected {index + 1}")
        if event["runId"] != run_id:
            raise ValueError(f"{where}.runId: does not match run")
        if not isinstance(event["type"], str) or "." not in event["type"]:
            raise ValueError(f"{where}.type: invalid")
        if not all(isinstance(event[key], str) for key in ("entityId", "parentId", "occurredAt")):
            raise ValueError(f"{where}: identity/timestamp fields must be strings")
        iso8601(event["occurredAt"], f"{where}.occurredAt")
        if not isinstance(event["payload"], dict):
            raise ValueError(f"{where}.payload: expected object")
    types = [event["type"] for event in events]
    if types[:2] != ["run.started", "manifest.published"] or types[-1] != "run.finished":
        raise ValueError("events: invalid run lifecycle boundary")
    if events[1]["entityId"] != document["manifest"]["digest"]:
        raise ValueError("events[1]: manifest identity differs from report manifest")
    if events[-1]["payload"] != document["summary"]:
        raise ValueError("events[-1]: run summary differs from report summary")


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
    require(
        run,
        {
            "id", "startedAt", "finishedAt", "durationSeconds", "hostname", "cwd",
            "qVersion", "qRelease", "os", "resqVersion", "vcs", "ci", "config",
            "ordering", "selection", "shard",
        },
        "run",
    )
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
    execution_ids: list[str] = []
    case_ids: list[str] = []
    for index, row in enumerate(document["tests"]):
        validate_test(row, index)
        execution_ids.append(row["caseId"] or row["testId"])
        case_ids.extend(case["caseId"] for case in row["parameterCases"])
    if len(execution_ids) != len(set(execution_ids)):
        raise ValueError("tests: duplicate execution identity")
    if len(case_ids) != len(set(case_ids)):
        raise ValueError("tests: duplicate parameter caseId")
    if "manifest" in document or "events" in document:
        require(document, {"manifest", "events"}, "report lifecycle extension")
        validate_manifest(document["manifest"], document)
        validate_events(document["events"], document)


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
