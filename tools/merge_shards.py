#!/usr/bin/env python3
"""Strictly validate and merge a complete resQ shard topology.

The merger is deliberately fail-closed: it will not create an artifact from a
partial shard set, mixed revisions/manifests, duplicate results, or a shard that
did not emit every execution identity assigned to it. This makes a merged green
verdict evidence of a complete distributed run rather than a concatenation.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from validate_report import validate


class MergeError(ValueError):
    """An artifact set violates the distributed execution contract."""


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def stable_hash(value: str) -> str:
    return hashlib.md5(value.encode()).hexdigest()


def execution_id(row: dict[str, Any]) -> str:
    return str(row.get("caseId") or row.get("testId") or row.get("executionId") or "")


def load_report(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MergeError(f"{path}: cannot read report: {exc}") from exc
    try:
        validate(document)
    except (TypeError, ValueError) as exc:
        raise MergeError(f"{path}: invalid report: {exc}") from exc
    if document.get("profile", "full") != "full":
        raise MergeError(f"{path}: shard merge requires report profile full")
    return document


def same(documents: list[dict[str, Any]], getter, label: str) -> Any:
    values = [getter(document) for document in documents]
    if any(canonical(value) != canonical(values[0]) for value in values[1:]):
        raise MergeError(f"mixed {label} across shards")
    return copy.deepcopy(values[0])


def normalize_file(entry: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(entry)
    out.pop("selected", None)
    return out


def normalize_inventory(entry: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(entry)
    out.pop("selected", None)
    return out


def topology(documents: list[dict[str, Any]]) -> tuple[str, int, list[int]]:
    shards = [document["run"]["shard"] for document in documents]
    unit = same(documents, lambda d: d["run"]["shard"].get("unit", "file"), "shard unit")
    count = same(documents, lambda d: d["run"]["shard"]["count"], "shard count")
    same(documents, lambda d: d["run"]["shard"]["algorithm"], "shard algorithm")
    indices = [shard["index"] for shard in shards]
    if len(indices) != len(set(indices)):
        raise MergeError(f"duplicate shard index: {indices}")
    expected = list(range(count))
    if sorted(indices) != expected:
        raise MergeError(f"incomplete shard union: expected {expected}, got {sorted(indices)}")
    return unit, count, indices


def validate_sources(documents: list[dict[str, Any]]) -> list[dict[str, Any]]:
    inventories: list[dict[str, dict[str, Any]]] = []
    for document in documents:
        by_id = {entry["fileId"]: normalize_file(entry) for entry in document["manifest"]["files"]}
        if len(by_id) != len(document["manifest"]["files"]):
            raise MergeError("duplicate source file identity within a manifest")
        inventories.append(by_id)
    reference = inventories[0]
    for inventory in inventories[1:]:
        if canonical(inventory) != canonical(reference):
            raise MergeError("source inventory or source digest differs across shards")
    files = [copy.deepcopy(reference[key]) for key in sorted(reference, key=lambda item: reference[item]["path"])]
    for entry in files:
        entry["selected"] = True
    return files


def validate_inventory(
    documents: list[dict[str, Any]], unit: str, shard_count: int
) -> tuple[list[dict[str, Any]], list[set[str]]]:
    union: dict[str, dict[str, Any]] = {}
    expected_by_shard: list[set[str]] = []
    for document in documents:
        index = document["run"]["shard"]["index"]
        local: dict[str, dict[str, Any]] = {}
        for entry in document["manifest"]["tests"]:
            identity = execution_id(entry)
            if not identity or entry.get("executionId") != identity:
                raise MergeError(f"shard {index}: malformed execution identity")
            if identity in local:
                raise MergeError(f"shard {index}: duplicate manifest identity {identity}")
            if entry.get("assignedShard") not in range(shard_count):
                raise MergeError(f"shard {index}: invalid assignment for {identity}")
            local[identity] = entry
            normalized = normalize_inventory(entry)
            if identity in union and canonical(normalize_inventory(union[identity])) != canonical(normalized):
                raise MergeError(f"manifest identity {identity} differs across shards")
            union.setdefault(identity, copy.deepcopy(entry))
        for identity, entry in local.items():
            assigned_here = entry["assignedShard"] == index
            if entry.get("shardable", True) and bool(entry.get("selected")) != assigned_here:
                raise MergeError(f"shard {index}: selection disagrees with assignment for {identity}")
            if not entry.get("shardable", True) and not entry.get("selected"):
                raise MergeError(f"shard {index}: run-level execution {identity} must be selected")
        expected = {identity for identity, entry in local.items() if entry.get("selected")}
        declared = set(document["run"]["shard"].get("selectedExecutionIds", []))
        if declared != expected:
            missing = sorted(expected - declared)
            extra = sorted(declared - expected)
            raise MergeError(
                f"shard {index}: selectedExecutionIds disagrees with manifest assignment "
                f"(missing={missing}, extra={extra})"
            )
        expected_by_shard.append(expected)
    if not union and any(document["tests"] for document in documents):
        raise MergeError("result rows exist without manifest inventory")
    ordered = sorted(
        union.values(),
        key=lambda entry: (
            entry.get("file", ""), entry.get("suite", ""),
            entry.get("line") if isinstance(entry.get("line"), int) else -1,
            entry.get("description", ""), entry["executionId"],
        ),
    )
    for entry in ordered:
        entry["selected"] = True
    return ordered, expected_by_shard


def validate_results(
    documents: list[dict[str, Any]], expected_by_shard: list[set[str]],
    unshardable: set[str] | None = None,
) -> list[dict[str, Any]]:
    unshardable = unshardable or set()
    union: dict[str, dict[str, Any]] = {}
    for document, expected in zip(documents, expected_by_shard):
        index = document["run"]["shard"]["index"]
        local: dict[str, dict[str, Any]] = {}
        for row in document["tests"]:
            identity = execution_id(row)
            if identity in local:
                raise MergeError(f"shard {index}: duplicate result {identity}")
            local[identity] = row
            if identity in union:
                if identity not in unshardable:
                    raise MergeError(f"result {identity} appears in more than one shard")
                fields = (
                    "suite", "description", "status", "message", "failures", "assertsRun",
                    "file", "line", "testId", "caseId", "kind", "parameters",
                )
                if canonical({field: union[identity].get(field) for field in fields}) != canonical(
                    {field: row.get(field) for field in fields}
                ):
                    raise MergeError(f"run-level result {identity} differs across shards")
                continue
            union[identity] = copy.deepcopy(row)
        actual = set(local)
        if actual != expected:
            missing = sorted(expected - actual)
            extra = sorted(actual - expected)
            raise MergeError(
                f"shard {index}: incomplete result set (missing={missing}, extra={extra}); "
                "fail-fast/aborted shards cannot produce a complete merged artifact"
            )
    return list(union.values())


def validate_snapshot_ownership(rows: Iterable[dict[str, Any]]) -> None:
    owners: dict[tuple[str, str], str] = {}
    for row in rows:
        identity = execution_id(row)
        for snapshot in row.get("snapshots", []):
            key = (str(snapshot.get("backend", "")), str(snapshot.get("path", "")))
            if key in owners and owners[key] != identity:
                raise MergeError(f"snapshot {key!r} was written by multiple executions")
            owners[key] = identity


def merge_performance(documents: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for document in documents:
        performance = document.get("performance") or []
        if isinstance(performance, dict):
            performance = [performance] if performance else []
        for row in performance:
            key = str(row.get("benchmarkId", ""))
            if not key:
                raise MergeError("benchmark result has no stable benchmarkId")
            if key in merged:
                raise MergeError(f"benchmark result {key!r} appears in more than one shard")
            merged[key] = copy.deepcopy(row)
    return [merged[key] for key in sorted(merged)]


def holm_adjust(p_values: list[float]) -> list[float]:
    order = sorted(range(len(p_values)), key=p_values.__getitem__)
    adjusted = [0.0] * len(p_values)
    running = 0.0
    for rank, index in enumerate(order):
        running = max(running, (len(p_values) - rank) * p_values[index])
        adjusted[index] = min(1.0, running)
    return adjusted


def merge_benchmark_analysis(
    documents: list[dict[str, Any]], performance: list[dict[str, Any]],
    result_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    first = copy.deepcopy(documents[0]["benchmarkAnalysis"])
    enabled = any(bool(document["benchmarkAnalysis"]["enabled"]) for document in documents)
    first["enabled"] = enabled
    first["environment"] = same(
        documents, lambda document: document["benchmarkAnalysis"]["environment"],
        "benchmark environment",
    )
    if not enabled:
        first["counts"]["total"] = len(performance)
        first["comparisons"] = []
        first["gate"] = {
            "enabled": bool(first["gate"]["enabled"]), "deferred": False,
            "passed": True, "reasons": [],
        }
        return first
    for label, getter in (
        ("benchmark baseline path", lambda d: d["benchmarkAnalysis"]["baselinePath"]),
        ("benchmark baseline status", lambda d: d["benchmarkAnalysis"]["baselineStatus"]),
        ("benchmark method", lambda d: d["benchmarkAnalysis"]["method"]),
        ("benchmark configuration", lambda d: d["benchmarkAnalysis"]["config"]),
        ("benchmark gate policy", lambda d: d["benchmarkAnalysis"]["gate"]["enabled"]),
    ):
        same(documents, getter, label)
    comparisons = [
        copy.deepcopy(row["comparison"]) for row in performance if row.get("comparison")
    ]
    comparable = [index for index, item in enumerate(comparisons) if item["comparable"]]
    adjusted = holm_adjust([float(comparisons[index]["pValue"]) for index in comparable])
    for position, index in enumerate(comparable):
        comparison = comparisons[index]
        comparison["adjustedPValue"] = adjusted[position]
        significant = adjusted[position] <= float(comparison["alpha"])
        effect = comparison.get("relativeChangePercent")
        practical = effect is not None and abs(float(effect)) >= float(comparison["practicalEffectPercent"])
        comparison["classification"] = (
            "regressed" if significant and practical and float(effect) > 0 else
            "improved" if significant and practical else "stable"
        )
    by_id = {item["benchmarkId"]: item for item in comparisons}
    for measurement in performance:
        if measurement["benchmarkId"] in by_id:
            measurement["comparison"] = copy.deepcopy(by_id[measurement["benchmarkId"]])
    for row in result_rows:
        benchmark = row.get("benchmark") or {}
        identity = benchmark.get("benchmarkId")
        if identity in by_id:
            benchmark["comparison"] = copy.deepcopy(by_id[identity])
    classes = [item["classification"] for item in comparisons]
    first["comparisons"] = comparisons
    first["counts"] = {
        "total": len(comparisons),
        "baselineFound": sum(bool(item["baselineFound"]) for item in comparisons),
        "comparable": sum(bool(item["comparable"]) for item in comparisons),
        "improved": classes.count("improved"),
        "stable": classes.count("stable"),
        "inconclusive": classes.count("inconclusive"),
        "regressed": classes.count("regressed"),
        "environmentMismatches": sum(
            bool(item["baselineFound"]) and not bool(item["environmentMatch"])
            for item in comparisons
        ),
    }
    gate_enabled = bool(first["gate"]["enabled"])
    reasons: list[str] = []
    if gate_enabled and first["baselineStatus"] != "ok":
        reasons.append(f"baseline-{first['baselineStatus']}")
    if gate_enabled and not comparisons:
        reasons.append("no-benchmarks-executed")
    if gate_enabled and any(not item["baselineFound"] for item in comparisons):
        reasons.append("benchmark-missing-from-baseline")
    if gate_enabled and "regressed" in classes:
        reasons.append("statistically-significant-practical-regression")
    first["gate"] = {
        "enabled": gate_enabled, "deferred": False,
        "passed": not reasons, "reasons": reasons,
    }
    return first


def merge_diagnostics(documents: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    for document in documents:
        index = document["run"]["shard"]["index"]
        for diagnostic in document.get("diagnostics", []):
            item = copy.deepcopy(diagnostic)
            data = item.get("data")
            item["data"] = {**data, "shardIndex": index} if isinstance(data, dict) else {
                "value": data, "shardIndex": index
            }
            merged.append(item)
    return merged


DERIVED_FIELDS = {
    "covered", "functionFound", "functionHit", "statementFunctionsInstrumented",
    "lineFound", "lineHit", "statementSitesEligible", "statementSitesInstrumented",
    "statementSitesHit", "branchSitesEligible", "branchSitesInstrumented",
    "branchFound", "branchHit", "statementFound", "statementHit",
    "statementSitesFound", "edgesFound", "edgesHit",
}


def merge_records(
    records: Iterable[dict[str, Any]], key_fields: tuple[str, ...],
    children: dict[str, tuple[tuple[str, ...], dict[str, Any]]],
) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        groups[tuple(record.get(field) for field in key_fields)].append(record)
    merged: list[dict[str, Any]] = []
    for key in sorted(groups, key=lambda value: canonical(value)):
        items = groups[key]
        out = copy.deepcopy(items[0])
        ignored = {"hits", *DERIVED_FIELDS, *children.keys()}
        baseline = {name: value for name, value in items[0].items() if name not in ignored}
        for item in items[1:]:
            metadata = {name: value for name, value in item.items() if name not in ignored}
            if canonical(metadata) != canonical(baseline):
                raise MergeError(f"coverage metadata differs for {key!r}")
        if any("hits" in item for item in items):
            out["hits"] = sum(int(item.get("hits", 0)) for item in items)
            out["covered"] = out["hits"] > 0
        for name, (child_key, grandchildren) in children.items():
            out[name] = merge_records(
                (child for item in items for child in item.get(name, [])),
                child_key, grandchildren,
            )
        merged.append(out)
    return merged


EDGE_SPEC: dict[str, Any] = {}
BRANCH_SPEC = {"edges": (("edgeId",), EDGE_SPEC)}
FUNCTION_SPEC = {
    "statements": (("line",), {}),
    "statementSites": (("siteId",), {}),
    "branches": (("siteId",), BRANCH_SPEC),
}
FILE_SPEC = {
    "functions": (("name", "line"), FUNCTION_SPEC),
    "lines": (("line",), {}),
    "statementSites": (("siteId",), {}),
    "branches": (("siteId",), BRANCH_SPEC),
}


def pct(hit: int, found: int) -> float:
    return 0.0 if found == 0 else 100.0 * hit / found


def recompute_coverage(files: list[dict[str, Any]], template: dict[str, Any]) -> dict[str, Any]:
    for file in files:
        functions = file.get("functions", [])
        lines = file.get("lines", [])
        sites = file.get("statementSites", [])
        branches = file.get("branches", [])
        for function in functions:
            function["covered"] = int(function.get("hits", 0)) > 0
            function["statementFound"] = len(function.get("statements", []))
            function["statementHit"] = sum(int(row.get("hits", 0)) > 0 for row in function.get("statements", []))
            function["statementSitesFound"] = sum(bool(row.get("eligible")) for row in function.get("statementSites", []))
            function["statementSitesInstrumented"] = sum(bool(row.get("instrumented")) for row in function.get("statementSites", []))
            function["statementSitesHit"] = sum(int(row.get("hits", 0)) > 0 for row in function.get("statementSites", []) if row.get("eligible"))
            function["branchSitesEligible"] = sum(bool(row.get("eligible")) for row in function.get("branches", []))
            function["branchSitesInstrumented"] = sum(bool(row.get("instrumented")) for row in function.get("branches", []))
            function["branchFound"] = sum(len(row.get("edges", [])) for row in function.get("branches", []) if row.get("eligible"))
            function["branchHit"] = sum(int(edge.get("hits", 0)) > 0 for row in function.get("branches", []) for edge in row.get("edges", []) if row.get("eligible"))
        for branch in branches:
            branch["edgesFound"] = len(branch.get("edges", [])) if branch.get("eligible") else 0
            branch["edgesHit"] = sum(int(edge.get("hits", 0)) > 0 for edge in branch.get("edges", []))
        file["functionFound"] = len(functions)
        file["functionHit"] = sum(int(row.get("hits", 0)) > 0 for row in functions)
        file["statementFunctionsInstrumented"] = sum(bool(row.get("statementInstrumented")) for row in functions)
        file["lineFound"] = len(lines)
        file["lineHit"] = sum(int(row.get("hits", 0)) > 0 for row in lines)
        file["statementSitesEligible"] = sum(bool(row.get("eligible")) for row in sites)
        file["statementSitesInstrumented"] = sum(bool(row.get("instrumented")) for row in sites)
        file["statementSitesHit"] = sum(int(row.get("hits", 0)) > 0 for row in sites if row.get("eligible"))
        file["branchSitesEligible"] = sum(bool(row.get("eligible")) for row in branches)
        file["branchSitesInstrumented"] = sum(bool(row.get("instrumented")) for row in branches)
        file["branchFound"] = sum(len(row.get("edges", [])) for row in branches if row.get("eligible"))
        file["branchHit"] = sum(int(edge.get("hits", 0)) > 0 for row in branches for edge in row.get("edges", []) if row.get("eligible"))
    functions = [function for file in files for function in file.get("functions", [])]
    summary = copy.deepcopy(template.get("summary", {}))
    summary.update(
        filesFound=len(files), filesLoaded=sum(bool(file.get("loaded")) for file in files),
        filesWithStatements=sum(bool(file.get("lineFound")) for file in files),
        functionsFound=sum(file["functionFound"] for file in files),
        functionsHit=sum(file["functionHit"] for file in files),
        linesFound=sum(file["lineFound"] for file in files),
        linesHit=sum(file["lineHit"] for file in files),
        statementSitesFound=sum(file["statementSitesEligible"] for file in files),
        statementSitesHit=sum(file["statementSitesHit"] for file in files),
        statementSitesInstrumented=sum(file["statementSitesInstrumented"] for file in files),
        branchesFound=sum(file["branchFound"] for file in files),
        branchesHit=sum(file["branchHit"] for file in files),
        branchSitesEligible=sum(file["branchSitesEligible"] for file in files),
        branchSitesInstrumented=sum(file["branchSitesInstrumented"] for file in files),
        functionsEligible=sum(bool(function.get("functionEligible")) for function in functions),
        functionsInstrumented=sum(bool(function.get("functionInstrumented")) for function in functions),
        statementFunctionsEligible=sum(bool(function.get("statementEligible")) for function in functions),
        statementFunctionsInstrumented=sum(bool(function.get("statementInstrumented")) for function in functions),
    )
    for prefix in ("function", "line", "statementSite", "branch"):
        found_key = {"function": "functionsFound", "line": "linesFound", "statementSite": "statementSitesFound", "branch": "branchesFound"}[prefix]
        hit_key = {"function": "functionsHit", "line": "linesHit", "statementSite": "statementSitesHit", "branch": "branchesHit"}[prefix]
        summary[prefix + "Percent"] = pct(summary[hit_key], summary[found_key])
    for prefix, eligible, instrumented in (
        ("function", "functionsEligible", "functionsInstrumented"),
        ("statement", "statementFunctionsEligible", "statementFunctionsInstrumented"),
        ("statementSite", "statementSitesFound", "statementSitesInstrumented"),
        ("branch", "branchSitesEligible", "branchSitesInstrumented"),
    ):
        summary[prefix + "InstrumentationPercent"] = pct(summary[instrumented], summary[eligible])
        summary[prefix + "InstrumentationComplete"] = summary[eligible] == summary[instrumented]
    reasons = sorted(set(summary.get("fallbackCounts", {})) | {str(function.get("fallbackReason", "none")) for function in functions if function.get("fallbackReason") != "none"})
    summary["fallbackCounts"] = {reason: sum(function.get("fallbackReason") == reason for function in functions) for reason in reasons}
    return {
        "schemaVersion": template["schemaVersion"], "framework": template["framework"],
        "frameworkVersion": template["frameworkVersion"], "summary": summary,
        "files": files,
    }


def merge_contexts(measurements: list[dict[str, Any]]) -> dict[str, Any]:
    first = copy.deepcopy(measurements[0])
    for measurement in measurements[1:]:
        for field in ("schemaVersion", "enabled", "detail", "contextLimit", "entryLimit"):
            if measurement.get(field) != first.get(field):
                raise MergeError(f"coverage context {field} differs across shards")
    contexts: dict[str, dict[str, Any]] = {}
    for measurement in measurements:
        for context in measurement.get("contexts", []):
            identity = context["contextId"]
            metadata = {key: value for key, value in context.items() if key != "metrics"}
            if identity in contexts:
                old_metadata = {key: value for key, value in contexts[identity].items() if key != "metrics"}
                if canonical(metadata) != canonical(old_metadata):
                    raise MergeError(f"coverage context metadata differs for {identity}")
                metrics = contexts[identity]["metrics"] + context.get("metrics", [])
            else:
                contexts[identity] = copy.deepcopy(context)
                metrics = contexts[identity].get("metrics", [])
            contexts[identity]["metrics"] = merge_records(metrics, ("metricId",), {})
    rows = [contexts[key] for key in sorted(contexts)]
    metrics = [metric for context in rows for metric in context.get("metrics", [])]
    summary = {
        "contextsStored": len(rows), "metricEntriesStored": len(metrics),
        "functionHits": sum(int(row.get("hits", 0)) for row in metrics if row.get("kind") == "function"),
        "statementHits": sum(int(row.get("hits", 0)) for row in metrics if row.get("kind") == "statement"),
        "branchHits": sum(int(row.get("hits", 0)) for row in metrics if row.get("kind") == "branch"),
        "unattributedHits": sum(int(row.get("hits", 0)) for row in metrics if row.get("contextId") == "unattributed"),
        "overflowActivations": sum(int(item.get("summary", {}).get("overflowActivations", 0)) for item in measurements),
        "droppedMetricHits": sum(int(item.get("summary", {}).get("droppedMetricHits", 0)) for item in measurements),
        "truncated": any(bool(item.get("summary", {}).get("truncated")) for item in measurements),
    }
    first["summary"] = summary
    first["contexts"] = rows
    return first


def merge_coverage(report_paths: list[Path], destination: Path) -> dict[str, Any] | None:
    paths = [path.with_name("coverage.json") for path in report_paths]
    present = [path.is_file() for path in paths]
    if any(present) and not all(present):
        raise MergeError("coverage.json is present for only part of the shard set")
    if not any(present):
        return None
    documents = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
    same(documents, lambda d: (d.get("schemaVersion"), d.get("framework"), d.get("frameworkVersion")), "coverage schema/framework")
    files = merge_records(
        (file for document in documents for file in document.get("files", [])),
        ("path",), FILE_SPEC,
    )
    merged = recompute_coverage(files, documents[0])
    measurements = [document.get("contextMeasurement", {}) for document in documents]
    if any(measurements):
        merged["contextMeasurement"] = merge_contexts(measurements)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "coverage.json").write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_lcov(merged, destination / "coverage.lcov")
    return merged


def write_lcov(coverage: dict[str, Any], path: Path) -> None:
    lines: list[str] = []
    for file in coverage.get("files", []):
        lines.append(f"SF:{file['path']}")
        for function in file.get("functions", []):
            lines.append(f"FN:{function.get('line', 0)},{function.get('name', '')}")
            lines.append(f"FNDA:{function.get('hits', 0)},{function.get('name', '')}")
        lines.append(f"FNF:{file.get('functionFound', 0)}")
        lines.append(f"FNH:{file.get('functionHit', 0)}")
        for statement in file.get("lines", []):
            lines.append(f"DA:{statement['line']},{statement.get('hits', 0)}")
        lines.append(f"LF:{file.get('lineFound', 0)}")
        lines.append(f"LH:{file.get('lineHit', 0)}")
        for branch in file.get("branches", []):
            for edge in branch.get("edges", []):
                hits = edge.get("hits", 0)
                lines.append(f"BRDA:{branch.get('line', 0)},{branch.get('block', 0)},{edge.get('index', 0)},{hits if hits else '-'}")
        lines.append(f"BRF:{file.get('branchFound', 0)}")
        lines.append(f"BRH:{file.get('branchHit', 0)}")
        lines.append("end_of_record")
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def iso(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    statuses = [row["status"] for row in rows]
    seconds = sum(float(row.get("durationSeconds", 0)) for row in rows)
    return {
        "suiteCount": len({row["suite"] for row in rows}), "testCount": len(rows),
        "assertionCount": sum(int(row.get("assertsRun", 0)) for row in rows),
        "passCount": statuses.count("pass"), "failCount": statuses.count("fail"),
        "errorCount": statuses.count("error"),
        "skipCount": sum(status in {"skip", "pending"} for status in statuses),
        "duration": f"{seconds:.9f}s", "durationSeconds": seconds,
        "testDurationSumSeconds": seconds,
    }


def status_summary(rows: list[dict[str, Any]]) -> dict[str, int]:
    statuses = [row["status"] for row in rows]
    return {
        "testCount": len(rows), "passCount": statuses.count("pass"),
        "failCount": statuses.count("fail"), "errorCount": statuses.count("error"),
        "skipCount": sum(status in {"skip", "pending"} for status in statuses),
    }


def lifecycle(
    run: dict[str, Any], manifest: dict[str, Any], rows: list[dict[str, Any]],
    stats: dict[str, Any], coverage: dict[str, Any], diagnostics: list[dict[str, Any]],
    snapshot_inventory: dict[str, Any], benchmark_analysis: dict[str, Any],
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    def observed(record: dict[str, Any], field: str, fallback: str) -> str:
        value = record.get(field)
        return value if isinstance(value, str) and value else fallback
    def interval(records: list[dict[str, Any]], start: str, finish: str) -> tuple[str, str]:
        if not records:
            return start, finish
        return (
            min(observed(record, "startedAt", start) for record in records),
            max(observed(record, "finishedAt", finish) for record in records),
        )
    def emit(kind: str, entity: str, parent: str, occurred: str, payload: dict[str, Any]) -> None:
        events.append({
            "schemaVersion": 2, "sequence": len(events) + 1, "type": kind,
            "runId": run["id"], "entityId": entity, "parentId": parent,
            "occurredAt": occurred, "payload": payload,
        })
    emit("run.started", run["id"], "", run["startedAt"], {
        "frameworkVersion": manifest["frameworkVersion"],
        "ordering": run["ordering"], "selection": run["selection"], "shard": run["shard"],
    })
    emit("manifest.published", manifest["digest"], run["id"], run["startedAt"], {
        "schemaVersion": manifest["schemaVersion"],
        "kind": manifest["kind"],
        "digest": manifest["digest"],
        "digestAlgorithm": manifest["digestAlgorithm"],
        "identityAlgorithm": manifest["identityAlgorithm"],
        "frameworkVersion": manifest["frameworkVersion"],
        "fileCount": len(manifest["files"]),
        "testCount": len(manifest["tests"]),
    })
    files = {entry["path"]: entry for entry in manifest["files"]}
    inventory = {entry["executionId"]: entry for entry in manifest["tests"]}
    for file_path in dict.fromkeys(row["file"] for row in rows):
        file_rows = [row for row in rows if row["file"] == file_path]
        file_entry = files.get(file_path, {
            "fileId": "file_" + stable_hash(file_path), "path": file_path,
            "sourceDigest": "", "assignedShard": -1, "selected": True, "shardable": False,
        })
        file_id = file_entry["fileId"]
        file_started, file_finished = interval(file_rows, run["startedAt"], run["finishedAt"])
        emit("file.started", file_id, run["id"], file_started, file_entry)
        for suite in dict.fromkeys(row["suite"] for row in file_rows):
            suite_rows = [row for row in file_rows if row["suite"] == suite]
            first_entry = inventory[execution_id(suite_rows[0])]
            suite_id = first_entry["suiteId"]
            suite_started, suite_finished = interval(suite_rows, file_started, file_finished)
            emit("suite.started", suite_id, file_id, suite_started, {
                "file": file_path, "suite": suite, "testCount": len(suite_rows),
            })
            for row in suite_rows:
                identity = execution_id(row)
                test_started = observed(row, "startedAt", suite_started)
                test_finished = observed(row, "finishedAt", suite_finished)
                emit("test.started", identity, suite_id, test_started, {
                    "file": file_path, "suite": suite, "description": row["description"],
                    "line": row["line"], "kind": row["kind"], "tags": row["tags"],
                    "parameters": row.get("parameters", {}),
                })
                attempts = row.get("attemptHistory") or [{
                    "attempt": 1, "status": row["status"], "duration": row["time"],
                    "durationSeconds": row.get("durationSeconds", 0),
                    "startedAt": row.get("startedAt"), "finishedAt": row.get("finishedAt"),
                    "message": row.get("message", ""), "failures": row.get("failures", []),
                    "assertsRun": row.get("assertsRun", 0),
                }]
                for index, attempt in enumerate(attempts, start=1):
                    attempt_number = int(attempt.get("attempt", index))
                    attempt_id = f"{identity}/attempt/{attempt_number}"
                    attempt_started = observed(attempt, "startedAt", test_started)
                    attempt_finished = observed(attempt, "finishedAt", test_finished)
                    emit("attempt.started", attempt_id, identity, attempt_started, {
                        "attempt": attempt_number,
                    })
                    emit("attempt.finished", attempt_id, identity, attempt_finished, attempt)
                for index, case in enumerate(row.get("parameterCases", [])):
                    case_id = str(case.get("caseId") or (
                        "case_" + stable_hash(
                            f"{row['testId']}\n{index}\n{canonical(case.get('parameters', {}))}"
                        )
                    ))
                    case_started = observed(case, "startedAt", test_started)
                    case_finished = observed(case, "finishedAt", test_finished)
                    emit("case.started", case_id, row["testId"], case_started, {
                        "index": index, "parameters": case.get("parameters", {}),
                    })
                    emit("case.finished", case_id, row["testId"], case_finished, case)
                benchmark = row.get("benchmark") or {}
                if benchmark:
                    emit(
                        "benchmark.finished", str(benchmark["benchmarkId"]),
                        row["testId"], run["finishedAt"], benchmark,
                    )
                for index, diagnostic in enumerate(row.get("diagnostics", [])):
                    diagnostic_id = "diagnostic_" + stable_hash(
                        f"{identity}\n{index}\n{canonical(diagnostic)}"
                    )
                    emit("diagnostic.recorded", diagnostic_id, identity, run["finishedAt"], diagnostic)
                finished_payload = {
                    "status": row["status"], "duration": row["time"],
                    "durationSeconds": row.get("durationSeconds", 0),
                    "assertsRun": row["assertsRun"], "attempts": row["attempts"],
                    "retried": row["retried"], "flaky": row["flaky"],
                }
                if row.get("quarantine"):
                    finished_payload["quarantine"] = row["quarantine"]
                emit("test.finished", identity, suite_id, test_finished, finished_payload)
            emit("suite.finished", suite_id, file_id, suite_finished, status_summary(suite_rows))
        emit("file.finished", file_id, run["id"], file_finished, status_summary(file_rows))
    if coverage:
        emit("coverage.finished", "coverage", run["id"], run["finishedAt"], coverage)
    if snapshot_inventory.get("enabled"):
        emit("snapshots.audited", "snapshots", run["id"], run["finishedAt"], snapshot_inventory)
    if benchmark_analysis.get("enabled"):
        emit("benchmarks.compared", "benchmarks", run["id"], run["finishedAt"], benchmark_analysis)
    for index, diagnostic in enumerate(diagnostics):
        diagnostic_id = "diagnostic_" + stable_hash(
            f"{run['id']}\n{index}\n{canonical(diagnostic)}"
        )
        emit("diagnostic.recorded", diagnostic_id, run["id"], run["finishedAt"], diagnostic)
    emit("run.finished", run["id"], "", run["finishedAt"], stats)
    return events


def merge(report_paths: list[Path], destination: Path) -> tuple[dict[str, Any], bool]:
    if not report_paths:
        raise MergeError("no shard reports supplied")
    documents = [load_report(path) for path in report_paths]
    unit, shard_count, _ = topology(documents)
    framework_version = same(documents, lambda d: d["frameworkVersion"], "framework version")
    digest = same(documents, lambda d: d["manifest"]["digest"], "manifest digest")
    revision = same(documents, lambda d: d["manifest"]["revision"], "revision")
    same(documents, lambda d: d["run"]["qVersion"], "q version")
    same(documents, lambda d: d["run"]["ordering"], "execution ordering")
    same(
        documents,
        lambda d: {
            key: value for key, value in d["run"]["config"].items()
            if key not in {"shardIndex", "outDir", "stateFile"}
        },
        "effective configuration",
    )
    files = validate_sources(documents)
    inventory, expected = validate_inventory(documents, unit, shard_count)
    unshardable = {
        entry["executionId"] for entry in inventory if not entry.get("shardable", True)
    }
    rows = validate_results(documents, expected, unshardable)
    order = {entry["executionId"]: index for index, entry in enumerate(inventory)}
    rows.sort(key=lambda row: order[execution_id(row)])
    validate_snapshot_ownership(rows)
    performance = merge_performance(documents)
    diagnostics = merge_diagnostics(documents)
    destination.mkdir(parents=True, exist_ok=True)
    coverage = merge_coverage(report_paths, destination)
    started = min(iso(document["run"]["startedAt"]) for document in documents)
    finished = max(iso(document["run"]["finishedAt"]) for document in documents)
    run_ids = [document["run"]["id"] for document in sorted(documents, key=lambda d: d["run"]["shard"]["index"])]
    run_id = "run_" + stable_hash(digest + "\n" + "\n".join(run_ids))
    first_run = copy.deepcopy(documents[0]["run"])
    merged_shard = copy.deepcopy(first_run["shard"])
    merged_shard.update(
        index=-1, count=shard_count, unit=unit, merged=True,
        indices=list(range(shard_count)), selectedFileCount=len(files),
        selectedFiles=[entry["path"] for entry in files],
        selectedUnitCount=merged_shard.get("allUnitCount", len(inventory)),
        selectedExecutionIds=[entry["executionId"] for entry in inventory],
    )
    run = first_run
    run.update(
        id=run_id, startedAt=timestamp(started), finishedAt=timestamp(finished),
        durationSeconds=(finished - started).total_seconds(),
        wallDurationSeconds=(finished - started).total_seconds(), hostname="merged",
        shard=merged_shard,
        merge={"strict": True, "shardCount": shard_count, "unit": unit, "childRunIds": run_ids},
    )
    if isinstance(run.get("config"), dict):
        run["config"].update(shardIndex=-1, shardCount=shard_count, shardUnit=unit)
    if isinstance(run.get("selection"), dict):
        run["selection"]["selectedTestCount"] = len(inventory)
    run["completion"] = {
        "state": "complete", "complete": True, "truncated": False,
        "reason": "completed", "selectedTestCount": len(inventory),
        "resultCount": len(rows), "missingExecutionIds": [],
    }
    manifest = copy.deepcopy(documents[0]["manifest"])
    manifest.update(revision=revision, shard=merged_shard, files=files, tests=inventory)
    stats = summary(rows)
    report_coverage: dict[str, Any] = {}
    coverage_passed = all(
        bool(document.get("coverage", {}).get("passed", True)) for document in documents
    )
    if coverage is not None:
        report_coverage = copy.deepcopy(coverage["summary"])
        bases = {str(document.get("coverage", {}).get("basis", "functions")) for document in documents}
        minimum = max(int(document.get("coverage", {}).get("minimum", 0)) for document in documents)
        report_coverage.update(
            basis=next(iter(bases)) if len(bases) == 1 else "mixed",
            minimum=minimum, passed=coverage_passed,
        )
    flake = copy.deepcopy(documents[0]["flake"])
    states = [row.get("quarantine", {}).get("state", "insufficient") for row in rows]
    flake.update(
        historyPath="<merged shard histories>",
        historyStatus="ok" if all(document["flake"]["historyStatus"] == "ok" for document in documents) else "missing",
        healthy=states.count("healthy"), suspect=states.count("suspect"),
        quarantined=states.count("quarantined"), expired=states.count("expired"),
        insufficient=states.count("insufficient"),
        proposalCount=sum(int(document["flake"].get("proposalCount", 0)) for document in documents),
    )
    snapshot_inventories = [document["snapshotInventory"] for document in documents]
    inventory_enabled = any(bool(item.get("enabled")) for item in snapshot_inventories)
    inventory_entries: dict[tuple[str, str], dict[str, Any]] = {}
    inventory_roots: dict[tuple[str, str], dict[str, Any]] = {}
    for inventory in snapshot_inventories:
        for root_entry in inventory.get("roots", []):
            inventory_roots[(str(root_entry.get("backend", "")), str(root_entry.get("absolutePath", "")))] = copy.deepcopy(root_entry)
        for entry in inventory.get("entries", []):
            key = (str(entry.get("backend", "")), str(entry.get("absolutePath", "")))
            prior = inventory_entries.get(key)
            if prior is None:
                inventory_entries[key] = copy.deepcopy(entry)
                continue
            prior["referenced"] = bool(prior.get("referenced")) or bool(entry.get("referenced"))
            prior["declared"] = bool(prior.get("declared")) or bool(entry.get("declared"))
            prior["dynamic"] = bool(prior.get("dynamic")) or bool(entry.get("dynamic"))
            prior["exists"] = bool(prior.get("exists")) or bool(entry.get("exists"))
            prior["unsafe"] = bool(prior.get("unsafe")) or bool(entry.get("unsafe"))
            prior["executionIds"] = sorted(set(prior.get("executionIds", [])) | set(entry.get("executionIds", [])))
            prior["observedStatuses"] = sorted(set(prior.get("observedStatuses", [])) | set(entry.get("observedStatuses", [])))
    merged_entries = list(inventory_entries.values())
    for entry in merged_entries:
        referenced = bool(entry.get("referenced")) or bool(entry.get("declared"))
        entry["status"] = (
            "referenced" if referenced and entry.get("exists") else
            "missing" if referenced else "obsolete"
        )
    snapshot_counts = {
        "referenced": sum(entry["status"] == "referenced" for entry in merged_entries),
        "missing": sum(entry["status"] == "missing" for entry in merged_entries),
        "obsolete": sum(entry["status"] == "obsolete" for entry in merged_entries),
        "unverified": 0,
        "unsafe": sum(bool(entry.get("unsafe")) for entry in merged_entries) +
                  sum(bool(root.get("symlink")) for root in inventory_roots.values()),
        "stored": sum(bool(entry.get("exists")) for entry in merged_entries),
        "declared": sum(bool(entry.get("declared")) for entry in merged_entries),
    }
    snapshot_gate_enabled = any(bool(item.get("gate", {}).get("enabled")) for item in snapshot_inventories)
    snapshot_gate_reasons = []
    if snapshot_gate_enabled and snapshot_counts["missing"]:
        snapshot_gate_reasons.append("missing-snapshots")
    if snapshot_gate_enabled and snapshot_counts["obsolete"]:
        snapshot_gate_reasons.append("obsolete-snapshots")
    if snapshot_gate_enabled and snapshot_counts["unsafe"]:
        snapshot_gate_reasons.append("unsafe-snapshot-paths")
    snapshot_inventory = {
        "schemaVersion": 1, "kind": "resq-snapshot-inventory",
        "enabled": inventory_enabled, "generatedAt": run["finishedAt"],
        "complete": inventory_enabled, "completenessReasons": [] if inventory_enabled else ["disabled"],
        "roots": list(inventory_roots.values()), "entries": merged_entries,
        "counts": snapshot_counts,
        "gate": {"enabled": snapshot_gate_enabled, "passed": not snapshot_gate_reasons,
                 "reasons": snapshot_gate_reasons},
    }
    benchmark_analysis = merge_benchmark_analysis(documents, performance, rows)
    report = {
        "schemaVersion": 2, "framework": "resQ", "frameworkVersion": framework_version,
        "profile": "full",
        "completeness": {
            "evidenceComplete": True, "omittedSections": [],
            "omittedTestFields": [], "boundedFields": [],
        },
        "run": run, "summary": stats, "tests": rows, "performance": performance,
        "coverage": report_coverage, "diagnostics": diagnostics, "flake": flake,
        "snapshotInventory": snapshot_inventory,
        "benchmarkAnalysis": benchmark_analysis,
        "manifest": manifest,
    }
    report["events"] = lifecycle(
        run, manifest, rows, stats, report_coverage, diagnostics, snapshot_inventory,
        benchmark_analysis,
    )
    validate(report)
    (destination / "test-results.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    blocking = [
        row for row in rows
        if row["status"] in {"fail", "error"}
        and not bool(row.get("quarantine", {}).get("nonBlocking"))
    ]
    passed = (
        not blocking and coverage_passed and snapshot_inventory["gate"]["passed"]
        and benchmark_analysis["gate"]["passed"]
    )
    return report, passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="shard test-results.json files")
    parser.add_argument("--out-dir", required=True, type=Path, help="merged artifact directory")
    args = parser.parse_args()
    try:
        report, passed = merge(args.reports, args.out_dir)
    except (MergeError, OSError, json.JSONDecodeError, TypeError, KeyError) as exc:
        print(f"resq shard merge failed: {exc}", file=sys.stderr)
        return 2
    print(
        f"merged {len(args.reports)} shards: {report['summary']['testCount']} tests, "
        f"{report['summary']['assertionCount']} assertions -> {args.out_dir / 'test-results.json'}"
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
