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

from coverage_contract import validate_report_coverage


HEX_ID = re.compile(r"^(?:run|test|case)_[0-9a-f]{32}$")
MANIFEST_ID = re.compile(r"^manifest_[0-9a-f]{32}$")
FILE_ID = re.compile(r"^file_[0-9a-f]{32}$")
SUITE_ID = re.compile(r"^suite_[0-9a-f]{32}$")
BENCHMARK_ID = re.compile(r"^benchmark_[0-9a-f]{32}$")
ENVIRONMENT_ID = re.compile(r"^environment_[0-9a-f]{32}$")
REPLAY_TOKEN = re.compile(r"^resq-pbt-v1/-?\d+/\d+$")
LABEL_KEY = re.compile(r"^(?!resq\.|vcs\.|ci\.|__)[A-Za-z][A-Za-z0-9_.-]{0,63}$")
STATUSES = {"pass", "fail", "error", "skip", "pending"}
BENCHMARK_CLASSES = {"improved", "stable", "inconclusive", "regressed"}
PROFILE_OMITTED_SECTIONS = [
    "performance", "coverage", "flake", "snapshotInventory",
    "benchmarkAnalysis", "manifest", "events",
]
TELEMETRY_OMITTED_TEST_FIELDS = [
    "time", "failures", "namespace", "tags", "output", "parameters",
    "attemptHistory", "parameterCases", "property", "diagnostics",
    "snapshots", "benchmark", "quarantine",
]
TELEMETRY_TEST_FIELDS = {
    "suite", "description", "status", "message", "durationSeconds",
    "assertsRun", "file", "line", "testId", "caseId", "kind",
    "attempts", "retried", "flaky", "startedAt", "finishedAt",
}


def require(obj: dict[str, Any], keys: set[str], where: str) -> None:
    missing = sorted(keys - obj.keys())
    if missing:
        raise ValueError(f"{where}: missing {', '.join(missing)}")


def iso8601(value: Any, where: str) -> datetime:
    if not isinstance(value, str):
        raise ValueError(f"{where}: expected ISO-8601 string")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def require_non_negative_number(value: Any, where: str) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        raise ValueError(f"{where}: expected non-negative number")


def validate_interval(record: dict[str, Any], where: str, duration_key: str = "durationSeconds") -> None:
    present = "startedAt" in record or "finishedAt" in record
    if not present:
        return
    if "startedAt" not in record or "finishedAt" not in record:
        raise ValueError(f"{where}: startedAt and finishedAt must appear together")
    started, finished = record["startedAt"], record["finishedAt"]
    if started is None and finished is None:
        return
    if started is None or finished is None:
        raise ValueError(f"{where}: timing interval must be fully known or null")
    parsed_start = iso8601(started, f"{where}.startedAt")
    parsed_finish = iso8601(finished, f"{where}.finishedAt")
    if parsed_finish < parsed_start:
        raise ValueError(f"{where}: finishedAt precedes startedAt")
    if duration_key in record:
        elapsed = (parsed_finish - parsed_start).total_seconds()
        if abs(float(record[duration_key]) - elapsed) > 0.001:
            raise ValueError(f"{where}.{duration_key} disagrees with timing interval")


def validate_diagnostic(diagnostic: Any, where: str) -> None:
    if not isinstance(diagnostic, dict):
        raise ValueError(f"{where}: expected object")
    require(diagnostic, {"type", "severity", "phase", "message", "data"}, where)
    if diagnostic["severity"] not in {"info", "warning", "error"}:
        raise ValueError(f"{where}.severity: invalid")
    if not isinstance(diagnostic["data"], dict):
        raise ValueError(f"{where}.data: expected object")
    if "timestamp" in diagnostic:
        iso8601(diagnostic["timestamp"], f"{where}.timestamp")


def rows_for_validation(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [value] if value else []
    raise ValueError("performance: expected array or empty object")


def validate_benchmark_samples(samples: Any, where: str, runs: int) -> None:
    if not isinstance(samples, dict):
        raise ValueError(f"{where}: expected object")
    require(samples, {"timeNs", "retainedBytes", "heapGrowthBytes"}, where)
    for name in ("timeNs", "retainedBytes", "heapGrowthBytes"):
        values = samples[name]
        if not isinstance(values, list) or len(values) != runs:
            raise ValueError(f"{where}.{name}: sample count must equal runs")
        if any(not isinstance(value, int) or value < 0 for value in values):
            raise ValueError(f"{where}.{name}: expected non-negative integer samples")


def validate_benchmark_workload(workload: Any, where: str, runs: int) -> None:
    if not isinstance(workload, dict):
        raise ValueError(f"{where}: expected object")
    require(workload, {"runs", "warmup", "gcBefore", "gcEach", "space"}, where)
    if workload["runs"] != runs or runs < 1 or workload["warmup"] < 0:
        raise ValueError(f"{where}: invalid runs/warmup")
    if any(not isinstance(workload[name], bool) for name in ("gcBefore", "gcEach", "space")):
        raise ValueError(f"{where}: GC/space controls must be boolean")


def validate_benchmark_environment(environment: Any, where: str) -> None:
    if not isinstance(environment, dict):
        raise ValueError(f"{where}: expected object")
    require(
        environment,
        {"qVersion", "qRelease", "os", "architecture", "cpuModel", "logicalCores", "fingerprint"},
        where,
    )
    if not isinstance(environment["fingerprint"], str) or not ENVIRONMENT_ID.fullmatch(environment["fingerprint"]):
        raise ValueError(f"{where}.fingerprint: invalid")


def validate_benchmark_comparison(comparison: Any, where: str) -> None:
    if not isinstance(comparison, dict):
        raise ValueError(f"{where}: expected object")
    require(
        comparison,
        {
            "benchmarkId", "testId", "file", "suite", "description", "classification", "reason",
            "baselineFound", "comparable", "environmentMatch", "workloadMatch", "environmentAccepted",
            "metric", "unit", "baselineMedian", "currentMedian", "relativeChangePercent", "u", "z",
            "pValue", "adjustedPValue", "alpha", "practicalEffectPercent", "baselineRuns", "currentRuns",
        },
        where,
    )
    if not BENCHMARK_ID.fullmatch(str(comparison["benchmarkId"])):
        raise ValueError(f"{where}.benchmarkId: invalid")
    if not HEX_ID.fullmatch(str(comparison["testId"])):
        raise ValueError(f"{where}.testId: invalid")
    if comparison["classification"] not in BENCHMARK_CLASSES:
        raise ValueError(f"{where}.classification: invalid")
    if not 0 <= float(comparison["pValue"]) <= float(comparison["adjustedPValue"]) <= 1:
        raise ValueError(f"{where}: invalid raw/adjusted p-values")
    if not 0 < float(comparison["alpha"]) <= 1:
        raise ValueError(f"{where}.alpha: invalid")
    if not comparison["comparable"] and comparison["classification"] != "inconclusive":
        raise ValueError(f"{where}: non-comparable benchmark must be inconclusive")


def validate_benchmark_telemetry(benchmark: Any, where: str, test_id: str) -> None:
    if not isinstance(benchmark, dict):
        raise ValueError(f"{where}: expected object")
    require(
        benchmark,
        {"benchmarkId", "testId", "file", "suite", "description", "status", "runs", "metric", "unit", "measurement", "limits", "workload", "samples", "comparison"},
        where,
    )
    if not BENCHMARK_ID.fullmatch(str(benchmark["benchmarkId"])) or benchmark["testId"] != test_id:
        raise ValueError(f"{where}: invalid benchmark/test identity")
    runs = benchmark["runs"]
    if not isinstance(runs, int) or runs < 1:
        raise ValueError(f"{where}.runs: expected positive integer")
    validate_benchmark_workload(benchmark["workload"], f"{where}.workload", runs)
    validate_benchmark_samples(benchmark["samples"], f"{where}.samples", runs)
    if benchmark["comparison"]:
        validate_benchmark_comparison(benchmark["comparison"], f"{where}.comparison")
        if benchmark["comparison"]["benchmarkId"] != benchmark["benchmarkId"]:
            raise ValueError(f"{where}.comparison: benchmark identity differs")


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
    require_non_negative_number(row["durationSeconds"], f"{where}.durationSeconds")
    validate_interval(row, where)
    if not isinstance(row["assertsRun"], int) or isinstance(row["assertsRun"], bool) or row["assertsRun"] < 0:
        raise ValueError(f"{where}.assertsRun: expected non-negative integer")
    if not isinstance(row["testId"], str) or not HEX_ID.fullmatch(row["testId"]):
        raise ValueError(f"{where}.testId: invalid stable identity")
    if not isinstance(row["caseId"], str) or (
        row["caseId"] and not HEX_ID.fullmatch(row["caseId"])
    ):
        raise ValueError(f"{where}.caseId: invalid stable identity")
    if not isinstance(row["kind"], str):
        raise ValueError(f"{where}.kind: expected string")
    if row["kind"] == "case" and not row["caseId"]:
        raise ValueError(f"{where}: declarative case requires caseId")
    if not isinstance(row.get("parameters", {}), dict):
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
        validate_interval(attempt, attempt_where)
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
        validate_interval(case, f"{where}.parameterCases[{case_index}]")
        case_ids.append(case["caseId"])
        case_indices.append(case["index"])
    if len(case_ids) != len(set(case_ids)) or len(case_indices) != len(set(case_indices)):
        raise ValueError(f"{where}.parameterCases: identities and indices must be unique")
    property_data = row["property"]
    if not isinstance(property_data, dict):
        raise ValueError(f"{where}.property: expected object")
    if property_data and "generatorProtocol" in property_data:
        require(
            property_data,
            {
                "seed", "runs", "maxFailRate", "failRate", "passCount", "failCount",
                "failedInputs", "shrunkInput", "generatorProtocol", "replayToken",
                "replayTokens", "originalInput", "minimalInput", "shrinkSteps",
                "shrinkCandidates", "shrinkTermination", "failureSignature",
                "shrinkDurationMs",
            },
            f"{where}.property",
        )
        if property_data["passCount"] + property_data["failCount"] != property_data["runs"]:
            raise ValueError(f"{where}.property: pass/fail totals must equal runs")
        if len(property_data["failedInputs"]) != property_data["failCount"]:
            raise ValueError(f"{where}.property: failed input count must equal failCount")
        if len(property_data["replayTokens"]) != property_data["failCount"]:
            raise ValueError(f"{where}.property: replay token count must equal failCount")
        if bool(property_data["replayToken"]) != bool(property_data["failCount"]):
            raise ValueError(f"{where}.property: replayToken presence must match failures")
        if property_data["failCount"] and property_data["replayToken"] != property_data["replayTokens"][0]:
            raise ValueError(f"{where}.property: replayToken must identify the first failure")
        if any(not REPLAY_TOKEN.fullmatch(str(token)) for token in property_data["replayTokens"]):
            raise ValueError(f"{where}.property: invalid replay token")
        if property_data["generatorProtocol"] != "resq-generator-v1":
            raise ValueError(f"{where}.property: unsupported generator protocol")
        expected_rate = property_data["failCount"] / property_data["runs"] if property_data["runs"] else 0.0
        if abs(float(property_data["failRate"]) - expected_rate) > 1e-12:
            raise ValueError(f"{where}.property: failRate disagrees with failCount/runs")
        if property_data["shrinkSteps"] < 0 or property_data["shrinkCandidates"] < property_data["shrinkSteps"]:
            raise ValueError(f"{where}.property: invalid shrink work counters")
        if property_data["shrinkTermination"] not in {
            "notRun", "minimal", "stepLimit", "candidateLimit", "timeLimit"
        }:
            raise ValueError(f"{where}.property: invalid shrink termination")
        if bool(property_data["failCount"]) == (property_data["shrinkTermination"] == "notRun"):
            raise ValueError(f"{where}.property: shrink termination disagrees with failures")
        if bool(property_data["failCount"]) != bool(property_data["failureSignature"]):
            raise ValueError(f"{where}.property: failure signature presence must match failures")
    for snap_index, snapshot in enumerate(row["snapshots"]):
        require(snapshot, {"backend", "name", "status", "path", "timestamp"}, f"{where}.snapshots[{snap_index}]")
        iso8601(snapshot["timestamp"], f"{where}.snapshots[{snap_index}].timestamp")
    benchmark = row["benchmark"]
    if not isinstance(benchmark, dict):
        raise ValueError(f"{where}.benchmark: expected object")
    if benchmark and "benchmarkId" in benchmark:
        validate_benchmark_telemetry(benchmark, f"{where}.benchmark", row["testId"])
        if row["kind"] != "perf":
            raise ValueError(f"{where}: only perf rows may carry benchmark telemetry")
    if not isinstance(row["diagnostics"], list):
        raise ValueError(f"{where}.diagnostics: expected array")
    for diagnostic_index, diagnostic in enumerate(row["diagnostics"]):
        validate_diagnostic(diagnostic, f"{where}.diagnostics[{diagnostic_index}]")
    quarantine = row.get("quarantine", {})
    if not isinstance(quarantine, dict):
        raise ValueError(f"{where}.quarantine: expected object")
    if quarantine:
        require(
            quarantine,
            {
                "schemaVersion", "state", "active", "nonBlocking", "observations",
                "passes", "failures", "flakes", "owner", "reason", "evidence",
                "issue", "createdAt", "expiresAt",
            },
            f"{where}.quarantine",
        )
        if quarantine["schemaVersion"] != 1:
            raise ValueError(f"{where}.quarantine: unsupported schema")
        if quarantine["state"] not in {
            "insufficient", "healthy", "suspect", "quarantined", "expired"
        }:
            raise ValueError(f"{where}.quarantine.state: invalid")
        active = quarantine["state"] == "quarantined"
        if quarantine["active"] != active:
            raise ValueError(f"{where}.quarantine.active: disagrees with state")
        if quarantine["nonBlocking"] and not active:
            raise ValueError(f"{where}.quarantine: only active quarantine can be non-blocking")
        counts = [quarantine[name] for name in ("observations", "passes", "failures", "flakes")]
        if any(not isinstance(value, int) or value < 0 for value in counts):
            raise ValueError(f"{where}.quarantine: evidence counters must be non-negative integers")
        if quarantine["passes"] + quarantine["failures"] > quarantine["observations"]:
            raise ValueError(f"{where}.quarantine: pass/failure evidence exceeds observations")


def validate_telemetry_test(row: Any, index: int) -> None:
    where = f"tests[{index}]"
    if not isinstance(row, dict):
        raise ValueError(f"{where}: expected object")
    required = TELEMETRY_TEST_FIELDS - {"startedAt", "finishedAt"}
    require(row, required, where)
    unexpected = set(row) & set(TELEMETRY_OMITTED_TEST_FIELDS)
    if unexpected:
        raise ValueError(f"{where}: telemetry contains declared omitted fields {sorted(unexpected)!r}")
    if row["status"] not in STATUSES:
        raise ValueError(f"{where}.status: unknown value {row['status']!r}")
    require_non_negative_number(row["durationSeconds"], f"{where}.durationSeconds")
    validate_interval(row, where)
    if not isinstance(row["assertsRun"], int) or isinstance(row["assertsRun"], bool) or row["assertsRun"] < 0:
        raise ValueError(f"{where}.assertsRun: expected non-negative integer")
    if not isinstance(row["testId"], str) or not HEX_ID.fullmatch(row["testId"]):
        raise ValueError(f"{where}.testId: invalid stable identity")
    if not isinstance(row["caseId"], str) or (row["caseId"] and not HEX_ID.fullmatch(row["caseId"])):
        raise ValueError(f"{where}.caseId: invalid stable identity")
    if not isinstance(row["message"], str):
        raise ValueError(f"{where}.message: expected bounded string")
    if not isinstance(row["attempts"], int) or row["attempts"] < 1:
        raise ValueError(f"{where}.attempts: expected positive integer")
    if not isinstance(row["retried"], bool) or not isinstance(row["flaky"], bool):
        raise ValueError(f"{where}: retry flags must be boolean")
    if row["retried"] != (row["attempts"] > 1):
        raise ValueError(f"{where}: retried must agree with attempts")


def validate_profile(document: dict[str, Any]) -> str:
    profile = document.get("profile")
    if profile is None:
        return "legacy-full"
    if profile not in {"full", "results", "telemetry"}:
        raise ValueError("report.profile: expected full, results, or telemetry")
    completeness = document.get("completeness")
    if not isinstance(completeness, dict):
        raise ValueError("report.completeness: expected object")
    require(
        completeness,
        {"evidenceComplete", "omittedSections", "omittedTestFields", "boundedFields"},
        "report.completeness",
    )
    expected_sections = [] if profile == "full" else PROFILE_OMITTED_SECTIONS
    expected_fields = TELEMETRY_OMITTED_TEST_FIELDS if profile == "telemetry" else []
    expected_bounded = ["tests.message", "diagnostics.message"] if profile == "telemetry" else []
    if completeness["evidenceComplete"] is not (profile == "full"):
        raise ValueError("report.completeness.evidenceComplete disagrees with profile")
    if completeness["omittedSections"] != expected_sections:
        raise ValueError("report.completeness.omittedSections disagrees with profile")
    if completeness["omittedTestFields"] != expected_fields:
        raise ValueError("report.completeness.omittedTestFields disagrees with profile")
    if completeness["boundedFields"] != expected_bounded:
        raise ValueError("report.completeness.boundedFields disagrees with profile")
    omitted_present = sorted(set(expected_sections) & document.keys())
    if omitted_present:
        raise ValueError(f"report: declared omitted sections are present {omitted_present!r}")
    if profile == "full":
        require(
            document,
            {"performance", "coverage", "flake", "snapshotInventory", "benchmarkAnalysis", "manifest", "events"},
            "full report",
        )
    return profile


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
        raise ValueError(
            "run.shard.selectedExecutionIds: disagrees with manifest selection "
            f"(extra={sorted(set(selected_ids) - expected_selected)}, "
            f"missing={sorted(expected_selected - set(selected_ids))})"
        )
    selected_files = [entry["path"] for entry in manifest["files"] if entry["selected"]]
    if shard["allFileCount"] != len(manifest["files"]):
        raise ValueError("run.shard.allFileCount disagrees with manifest files")
    if shard["selectedFileCount"] != len(selected_files):
        raise ValueError("run.shard.selectedFileCount disagrees with manifest selection")
    reported_selected_files = shard["selectedFiles"]
    if (
        not isinstance(reported_selected_files, list)
        or len(reported_selected_files) != len(set(reported_selected_files))
        or set(reported_selected_files) != set(selected_files)
    ):
        raise ValueError("run.shard.selectedFiles disagrees with manifest selection")
    unit_keys = (
        file_paths
        if shard["unit"] == "file"
        else list(dict.fromkeys(entry["shardKey"] for entry in manifest["tests"] if entry["shardable"]))
    )
    selected_unit_keys = (
        selected_files
        if shard["unit"] == "file"
        else list(dict.fromkeys(
            entry["shardKey"] for entry in manifest["tests"]
            if entry["shardable"] and entry["selected"]
        ))
    )
    if shard["allUnitCount"] != len(unit_keys):
        raise ValueError("run.shard.allUnitCount disagrees with manifest topology")
    if shard["selectedUnitCount"] != len(selected_unit_keys):
        raise ValueError("run.shard.selectedUnitCount disagrees with manifest topology")
    selection = document["run"].get("selection", {})
    if selection.get("selectedTestCount") != len(selected_ids):
        raise ValueError("run.selection.selectedTestCount disagrees with selected execution IDs")


def validate_completion(document: dict[str, Any], execution_ids: list[str]) -> None:
    completion = document["run"].get("completion")
    if completion is None:
        return  # additive v2 extension: historical checked-in reports remain valid
    if not isinstance(completion, dict):
        raise ValueError("run.completion: expected object")
    require(
        completion,
        {
            "state", "complete", "truncated", "reason", "selectedTestCount",
            "resultCount", "missingExecutionIds",
        },
        "run.completion",
    )
    if completion["state"] not in {"complete", "incomplete"}:
        raise ValueError("run.completion.state: invalid")
    if not isinstance(completion["complete"], bool) or not isinstance(completion["truncated"], bool):
        raise ValueError("run.completion: complete/truncated must be boolean")
    if completion["complete"] == completion["truncated"]:
        raise ValueError("run.completion: complete and truncated must be opposites")
    if (completion["state"] == "complete") != completion["complete"]:
        raise ValueError("run.completion.state disagrees with complete")
    recognized = {
        "completed", "describeOnly", "emptyShard", "frameworkError", "loadError",
        "isolationError", "failFast", "missingResults",
    }
    if completion["reason"] not in recognized:
        raise ValueError("run.completion.reason: unsupported")
    selected = document["run"].get("shard", {}).get("selectedExecutionIds", [])
    result_set = set(execution_ids)
    selected_set = set(selected)
    missing = selected_set - result_set
    if completion["selectedTestCount"] != len(selected):
        raise ValueError("run.completion.selectedTestCount disagrees with run selection")
    if completion["resultCount"] != len(execution_ids):
        raise ValueError("run.completion.resultCount disagrees with report rows")
    if set(completion["missingExecutionIds"]) != missing:
        raise ValueError("run.completion.missingExecutionIds is not the exact selection gap")
    if not result_set.issubset(selected_set):
        raise ValueError("run.completion: result identity lies outside selected execution IDs")
    if completion["complete"] and result_set != selected_set:
        raise ValueError("run.completion: complete run must exactly cover its selection")
    if completion["truncated"] and completion["reason"] in {"completed", "describeOnly", "emptyShard"}:
        raise ValueError("run.completion: truncated run requires an incomplete reason")


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
        if event["schemaVersion"] not in {1, 2}:
            raise ValueError(f"{where}.schemaVersion: expected 1 or 2")
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
    versions = {event["schemaVersion"] for event in events}
    if len(versions) != 1:
        raise ValueError("events: mixed schema versions")
    if types[:2] != ["run.started", "manifest.published"] or types[-1] != "run.finished":
        raise ValueError("events: invalid run lifecycle boundary")
    if events[1]["entityId"] != document["manifest"]["digest"]:
        raise ValueError("events[1]: manifest identity differs from report manifest")
    if events[-1]["payload"] != document["summary"]:
        raise ValueError("events[-1]: run summary differs from report summary")
    if versions == {2}:
        manifest = document["manifest"]
        expected_notice = {
            "schemaVersion": manifest["schemaVersion"],
            "kind": manifest["kind"],
            "digest": manifest["digest"],
            "digestAlgorithm": manifest["digestAlgorithm"],
            "identityAlgorithm": manifest["identityAlgorithm"],
            "frameworkVersion": manifest["frameworkVersion"],
            "fileCount": len(manifest["files"]),
            "testCount": len(manifest["tests"]),
        }
        if events[1]["payload"] != expected_notice:
            raise ValueError("events[1]: manifest notice must contain digest/version/counts only")
        run_start = iso8601(document["run"]["startedAt"], "run.startedAt")
        run_finish = iso8601(document["run"]["finishedAt"], "run.finishedAt")
        for index, event in enumerate(events):
            occurred = iso8601(event["occurredAt"], f"events[{index}].occurredAt")
            if occurred < run_start or occurred > run_finish:
                raise ValueError(f"events[{index}].occurredAt lies outside run interval")
        by_key = {(event["type"], event["entityId"]): event for event in events}
        def linked(kind: str, entity: str) -> dict[str, Any]:
            event = by_key.get((kind, entity))
            if event is None:
                raise ValueError(f"events: missing {kind} for {entity}")
            return event
        for test_index, row in enumerate(document["tests"]):
            identity = row["caseId"] or row["testId"]
            started_event = linked("test.started", identity)
            finished_event = linked("test.finished", identity)
            if {"testId", "caseId"} & started_event["payload"].keys():
                raise ValueError(f"events: test.started repeats identity for tests[{test_index}]")
            if "caseId" in finished_event["payload"]:
                raise ValueError(f"events: test.finished repeats identity for tests[{test_index}]")
            if not row.get("quarantine") and "quarantine" in finished_event["payload"]:
                raise ValueError(f"events: test.finished carries empty quarantine for tests[{test_index}]")
            if row.get("startedAt") is not None:
                if started_event["occurredAt"] != row["startedAt"]:
                    raise ValueError(f"events: test.started timing differs for tests[{test_index}]")
                if finished_event["occurredAt"] != row["finishedAt"]:
                    raise ValueError(f"events: test.finished timing differs for tests[{test_index}]")
            for attempt_index, attempt in enumerate(row["attemptHistory"], start=1):
                if attempt.get("startedAt") is None:
                    continue
                attempt_id = f"{identity}/attempt/{attempt_index}"
                if linked("attempt.started", attempt_id)["occurredAt"] != attempt["startedAt"]:
                    raise ValueError(f"events: attempt.started timing differs for tests[{test_index}]")
                if linked("attempt.finished", attempt_id)["occurredAt"] != attempt["finishedAt"]:
                    raise ValueError(f"events: attempt.finished timing differs for tests[{test_index}]")
            for case_index, case in enumerate(row["parameterCases"]):
                if case.get("startedAt") is None:
                    continue
                case_id = case["caseId"]
                if linked("case.started", case_id)["occurredAt"] != case["startedAt"]:
                    raise ValueError(f"events: case.started timing differs for tests[{test_index}]")
                if linked("case.finished", case_id)["occurredAt"] != case["finishedAt"]:
                    raise ValueError(f"events: case.finished timing differs for tests[{test_index}]")


def validate(document: Any) -> None:
    if not isinstance(document, dict):
        raise ValueError("report: expected object")
    profile = validate_profile(document)
    required = {"schemaVersion", "framework", "frameworkVersion", "run", "summary", "tests", "diagnostics"}
    if profile == "legacy-full":
        required.update({"performance", "coverage"})
    require(document, required, "report")
    if document["schemaVersion"] != 2 or document["framework"] != "resQ":
        raise ValueError("report: expected resQ schemaVersion 2")
    run = document["run"]
    require(
        run,
        {
            "id", "startedAt", "finishedAt", "durationSeconds", "hostname", "cwd",
            "qVersion", "qRelease", "os", "resqVersion", "vcs", "ci", "config",
        },
        "run",
    )
    if not HEX_ID.fullmatch(run["id"]):
        raise ValueError("run.id: invalid")
    started_at = iso8601(run["startedAt"], "run.startedAt")
    finished_at = iso8601(run["finishedAt"], "run.finishedAt")
    require_non_negative_number(run["durationSeconds"], "run.durationSeconds")
    if finished_at < started_at:
        raise ValueError("run.finishedAt precedes run.startedAt")
    elapsed = (finished_at - started_at).total_seconds()
    if abs(float(run["durationSeconds"]) - elapsed) > 0.001:
        raise ValueError("run.durationSeconds disagrees with run timestamps")
    if "wallDurationSeconds" in run:
        require_non_negative_number(run["wallDurationSeconds"], "run.wallDurationSeconds")
        if abs(float(run["wallDurationSeconds"]) - elapsed) > 0.001:
            raise ValueError("run.wallDurationSeconds disagrees with run timestamps")
    summary = document["summary"]
    if run["resqVersion"] != document["frameworkVersion"]:
        raise ValueError("run.resqVersion does not match frameworkVersion")
    labels = run.get("labels", {})
    if not isinstance(labels, dict) or len(labels) > 32:
        raise ValueError("run.labels: expected object with at most 32 entries")
    if list(labels) != sorted(labels):
        raise ValueError("run.labels: keys must use deterministic lexical order")
    if sum(len(str(key)) + len(str(value)) for key, value in labels.items()) > 4096:
        raise ValueError("run.labels: total key/value content exceeds 4096 characters")
    for key, value in labels.items():
        if not isinstance(key, str) or not LABEL_KEY.fullmatch(key):
            raise ValueError(f"run.labels: invalid key {key!r}")
        if not isinstance(value, str) or len(value) > 256:
            raise ValueError(f"run.labels.{key}: expected string of at most 256 characters")
    vcs = run["vcs"]
    require(vcs, {"sha", "branch", "dirty"}, "run.vcs")
    if not isinstance(vcs["sha"], str) or not isinstance(vcs["branch"], str):
        raise ValueError("run.vcs: sha and branch must be strings")
    if not isinstance(vcs["dirty"], bool):
        raise ValueError("run.vcs.dirty: expected boolean")
    if "status" in vcs and vcs["status"] not in {"ok", "unavailable", "disabled"}:
        raise ValueError("run.vcs.status: invalid")
    require(summary, {"suiteCount", "testCount", "assertionCount", "passCount", "failCount", "errorCount", "skipCount", "duration", "durationSeconds"}, "summary")
    if summary["testCount"] != len(document["tests"]):
        raise ValueError("summary.testCount does not match tests length")
    if summary["testCount"] != sum(summary[k] for k in ("passCount", "failCount", "errorCount", "skipCount")):
        raise ValueError("summary status counts do not add up")
    for key in ("suiteCount", "testCount", "assertionCount", "passCount", "failCount", "errorCount", "skipCount"):
        if not isinstance(summary[key], int) or isinstance(summary[key], bool) or summary[key] < 0:
            raise ValueError(f"summary.{key}: expected non-negative integer")
    require_non_negative_number(summary["durationSeconds"], "summary.durationSeconds")
    if "testDurationSumSeconds" in summary:
        require_non_negative_number(summary["testDurationSumSeconds"], "summary.testDurationSumSeconds")
        if abs(float(summary["testDurationSumSeconds"]) - float(summary["durationSeconds"])) > 1e-12:
            raise ValueError("summary.testDurationSumSeconds disagrees with durationSeconds")
    actual_statuses = {
        "passCount": sum(row.get("status") == "pass" for row in document["tests"]),
        "failCount": sum(row.get("status") == "fail" for row in document["tests"]),
        "errorCount": sum(row.get("status") == "error" for row in document["tests"]),
        "skipCount": sum(row.get("status") in {"skip", "pending"} for row in document["tests"]),
    }
    for key, actual in actual_statuses.items():
        if summary[key] != actual:
            raise ValueError(f"summary.{key} disagrees with test rows")
    if summary["suiteCount"] != len({row.get("suite") for row in document["tests"]}):
        raise ValueError("summary.suiteCount disagrees with test rows")
    if summary["assertionCount"] != sum(row.get("assertsRun", 0) for row in document["tests"]):
        raise ValueError("summary.assertionCount disagrees with test rows")
    if "coverage" in document:
        validate_report_coverage(document["coverage"])
    if "flake" in document:
        flake = document["flake"]
        require(
            flake,
            {
                "schemaVersion", "historyPath", "historyStatus", "manifestPath",
                "manifestStatus", "nonBlockingEnabled", "evidenceMin", "failureMin",
                "window", "healthy", "suspect", "quarantined", "expired",
                "insufficient", "proposalCount",
            },
            "flake",
        )
        if flake["schemaVersion"] != 1:
            raise ValueError("flake: unsupported schema")
        if flake["historyStatus"] not in {"ok", "missing", "invalid", "unsupported"}:
            raise ValueError("flake.historyStatus: invalid")
        if flake["manifestStatus"] not in {"ok", "missing", "invalid", "unsupported"}:
            raise ValueError("flake.manifestStatus: invalid")
        if flake["evidenceMin"] < 2 or flake["failureMin"] < 1 or flake["window"] < flake["evidenceMin"]:
            raise ValueError("flake: invalid evidence thresholds")
    if "snapshotInventory" in document:
        snapshots = document["snapshotInventory"]
        require(
            snapshots,
            {"schemaVersion", "kind", "enabled", "generatedAt", "complete", "completenessReasons", "roots", "entries", "counts", "gate"},
            "snapshotInventory",
        )
        if snapshots["schemaVersion"] != 1 or snapshots["kind"] != "resq-snapshot-inventory":
            raise ValueError("snapshotInventory: unsupported schema")
        iso8601(snapshots["generatedAt"], "snapshotInventory.generatedAt")
        if not isinstance(snapshots["complete"], bool) or not isinstance(snapshots["enabled"], bool):
            raise ValueError("snapshotInventory: enabled/complete must be boolean")
        if not snapshots["complete"] and not snapshots["completenessReasons"]:
            raise ValueError("snapshotInventory: partial inventory requires reasons")
        require(snapshots["gate"], {"enabled", "passed", "reasons"}, "snapshotInventory.gate")
        for index, entry in enumerate(snapshots["entries"]):
            where = f"snapshotInventory.entries[{index}]"
            require(entry, {"backend", "name", "path", "root", "absoluteRoot", "absolutePath", "status", "referenced", "declared", "dynamic", "exists", "unsafe", "executionIds", "observedStatuses"}, where)
            if entry["status"] not in {"referenced", "missing", "obsolete", "unverified"}:
                raise ValueError(f"{where}.status: invalid")
            if entry["backend"] not in {"binary", "text"}:
                raise ValueError(f"{where}.backend: invalid")
    performance = rows_for_validation(document.get("performance", []))
    performance_ids: list[str] = []
    for index, measurement in enumerate(performance):
        where = f"performance[{index}]"
        if not isinstance(measurement, dict):
            raise ValueError(f"{where}: expected object")
        if "benchmarkId" not in measurement:
            continue
        require(
            measurement,
            {"benchmarkId", "testId", "file", "suite", "description", "metric", "unit", "runs", "avgTimeMs", "minTimeMs", "medTimeMs", "maxTimeMs", "devTimeMs", "avgSpaceBytes", "maxSpaceBytes", "timeLimitMs", "spaceLimitBytes", "workload", "samples", "measurement", "environment", "comparison"},
            where,
        )
        if not BENCHMARK_ID.fullmatch(str(measurement["benchmarkId"])):
            raise ValueError(f"{where}.benchmarkId: invalid")
        if not HEX_ID.fullmatch(str(measurement["testId"])):
            raise ValueError(f"{where}.testId: invalid")
        runs = measurement["runs"]
        validate_benchmark_workload(measurement["workload"], f"{where}.workload", runs)
        validate_benchmark_samples(measurement["samples"], f"{where}.samples", runs)
        validate_benchmark_environment(measurement["environment"], f"{where}.environment")
        if measurement["comparison"]:
            validate_benchmark_comparison(measurement["comparison"], f"{where}.comparison")
        performance_ids.append(measurement["benchmarkId"])
    if len(performance_ids) != len(set(performance_ids)):
        raise ValueError("performance: duplicate benchmark identity")
    if "benchmarkAnalysis" in document:
        analysis = document["benchmarkAnalysis"]
        require(
            analysis,
            {"schemaVersion", "kind", "enabled", "baselinePath", "baselineStatus", "method", "config", "environment", "counts", "comparisons", "gate"},
            "benchmarkAnalysis",
        )
        if analysis["schemaVersion"] != 1 or analysis["kind"] != "resq-benchmark-analysis":
            raise ValueError("benchmarkAnalysis: unsupported schema")
        if analysis["baselineStatus"] not in {"disabled", "notLoaded", "ok", "missing", "invalid", "unsupported"}:
            raise ValueError("benchmarkAnalysis.baselineStatus: invalid")
        validate_benchmark_environment(analysis["environment"], "benchmarkAnalysis.environment")
        comparison_ids: list[str] = []
        for index, comparison in enumerate(analysis["comparisons"]):
            validate_benchmark_comparison(comparison, f"benchmarkAnalysis.comparisons[{index}]")
            comparison_ids.append(comparison["benchmarkId"])
        if len(comparison_ids) != len(set(comparison_ids)):
            raise ValueError("benchmarkAnalysis: duplicate comparison identity")
        if analysis["enabled"] and set(comparison_ids) != set(performance_ids):
            raise ValueError("benchmarkAnalysis: comparisons must cover every performance record")
        benchmark_gate = analysis["gate"]
        require(
            benchmark_gate, {"enabled", "deferred", "passed", "reasons"},
            "benchmarkAnalysis.gate",
        )
        if not all(isinstance(benchmark_gate[name], bool) for name in ("enabled", "deferred", "passed")):
            raise ValueError("benchmarkAnalysis.gate: enabled/deferred/passed must be boolean")
        if benchmark_gate["deferred"]:
            if not benchmark_gate["enabled"] or not benchmark_gate["passed"] or benchmark_gate["reasons"]:
                raise ValueError("benchmarkAnalysis.gate: deferred shard gate must be enabled, non-blocking, and reason-free")
            shard = run.get("shard", {})
            if int(shard.get("count", 1)) <= 1 or shard.get("merged", False):
                raise ValueError("benchmarkAnalysis.gate: only an unmerged multi-shard run may defer")
    execution_ids: list[str] = []
    case_ids: list[str] = []
    for index, row in enumerate(document["tests"]):
        if profile == "telemetry":
            validate_telemetry_test(row, index)
        else:
            validate_test(row, index)
        execution_ids.append(row["caseId"] or row["testId"])
        case_ids.extend(case["caseId"] for case in row.get("parameterCases", []))
    if len(execution_ids) != len(set(execution_ids)):
        raise ValueError("tests: duplicate execution identity")
    if len(case_ids) != len(set(case_ids)):
        raise ValueError("tests: duplicate parameter caseId")
    validate_completion(document, execution_ids)
    diagnostics = document["diagnostics"]
    if not isinstance(diagnostics, list):
        raise ValueError("diagnostics: expected array")
    for diagnostic_index, diagnostic in enumerate(diagnostics):
        validate_diagnostic(diagnostic, f"diagnostics[{diagnostic_index}]")
    # A run can fail through a non-test gate while every test row remains green.
    # In that case the accompanying error diagnostic is verdict-bearing, not a
    # contradiction. "All green" means the aggregate run verdict, including
    # every enabled gate, rather than only the test-row subtotal.
    all_green = summary["failCount"] == 0 and summary["errorCount"] == 0
    coverage_verdict = document.get("coverage", {})
    if isinstance(coverage_verdict, dict) and coverage_verdict.get("enabled"):
        all_green = all_green and coverage_verdict.get("passed") is True
    snapshot_gate = document.get("snapshotInventory", {}).get("gate", {})
    if isinstance(snapshot_gate, dict) and snapshot_gate.get("enabled"):
        all_green = all_green and snapshot_gate.get("passed") is True
    benchmark_gate = document.get("benchmarkAnalysis", {}).get("gate", {})
    if isinstance(benchmark_gate, dict) and benchmark_gate.get("enabled"):
        all_green = all_green and benchmark_gate.get("passed") is True
    unexpected_errors = [
        diagnostic for diagnostic in diagnostics
        if diagnostic["severity"] == "error"
        and not diagnostic["data"].get("expected", False)
        and not diagnostic["data"].get("nonVerdict", False)
    ]
    if all_green and unexpected_errors:
        raise ValueError("diagnostics: all-green report contains verdict-bearing error diagnostics")
    row_benchmark_ids = [
        row["benchmark"]["benchmarkId"] for row in document["tests"]
        if row.get("benchmark") and "benchmarkId" in row["benchmark"]
    ]
    if "performance" in document and set(row_benchmark_ids) != set(performance_ids):
        raise ValueError("performance: identities differ from test benchmark telemetry")
    if "manifest" in document or "events" in document:
        require(document, {"manifest", "events"}, "report lifecycle extension")
        validate_manifest(document["manifest"], document)
        validate_events(document["events"], document)
        audited = [event for event in document["events"] if event["type"] == "snapshots.audited"]
        snapshot_inventory = document.get("snapshotInventory", {})
        expected_audits = 1 if snapshot_inventory.get("enabled") else 0
        if len(audited) != expected_audits:
            raise ValueError("events: snapshots.audited presence disagrees with snapshot inventory")
        if audited and audited[0]["payload"] != snapshot_inventory:
            raise ValueError("events: snapshots.audited payload differs from report")
        benchmark_events = [event for event in document["events"] if event["type"] == "benchmarks.compared"]
        benchmark_analysis = document.get("benchmarkAnalysis", {})
        expected_benchmark_events = 1 if benchmark_analysis.get("enabled") else 0
        if len(benchmark_events) != expected_benchmark_events:
            raise ValueError("events: benchmarks.compared presence disagrees with benchmark analysis")
        if benchmark_events and benchmark_events[0]["payload"] != benchmark_analysis:
            raise ValueError("events: benchmarks.compared payload differs from report")


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
