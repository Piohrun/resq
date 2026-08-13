#!/usr/bin/env python3
"""Normalize a resQ report and optional coverage artifact into joinable tables."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from validate_report import validate


SCHEMA_VERSION = 1


def execution_id(row: dict[str, Any]) -> str:
    return str(row.get("caseId") or row["testId"])


def table_contract(
    report: dict[str, Any], coverage: dict[str, Any] | None = None
) -> dict[str, Any]:
    validate(report)
    run = report["run"]
    run_id = str(run["id"])
    summary = report["summary"]
    labels = run.get("labels", {})

    runs = [
        {
            "runId": run_id,
            "startedAt": run["startedAt"],
            "finishedAt": run["finishedAt"],
            "durationSeconds": run["durationSeconds"],
            "frameworkVersion": report["frameworkVersion"],
            "testCount": summary["testCount"],
            "passCount": summary["passCount"],
            "failCount": summary["failCount"],
            "errorCount": summary["errorCount"],
            "skipCount": summary["skipCount"],
            "assertionCount": summary["assertionCount"],
            "labels": labels,
            "environment": labels.get("environment", ""),
            "service": labels.get("service", ""),
            "deploymentId": labels.get("deploymentId", ""),
            "artifactDigest": labels.get("artifactDigest", ""),
            "vcsSha": run.get("vcs", {}).get("sha", ""),
            "vcsBranch": run.get("vcs", {}).get("branch", ""),
            "ciProvider": run.get("ci", {}).get("provider", "none"),
            "ciPipelineId": run.get("ci", {}).get("pipelineId", ""),
        }
    ]

    tests: list[dict[str, Any]] = []
    attempts: list[dict[str, Any]] = []
    for row in report["tests"]:
        identity = execution_id(row)
        tests.append(
            {
                "runId": run_id,
                "executionId": identity,
                "testId": row["testId"],
                "caseId": row.get("caseId", ""),
                "suite": row["suite"],
                "description": row["description"],
                "kind": row.get("kind", "test"),
                "status": row["status"],
                "durationSeconds": row["durationSeconds"],
                "assertsRun": row["assertsRun"],
                "attempts": row.get("attempts", 1),
                "retried": row.get("retried", False),
                "flaky": row.get("flaky", False),
                "file": row.get("file", ""),
                "line": row.get("line"),
                "message": row.get("message", ""),
            }
        )
        for attempt in row.get("attemptHistory", []):
            number = int(attempt["attempt"])
            attempts.append(
                {
                    "runId": run_id,
                    "executionId": identity,
                    "attemptKey": f"{run_id}/{identity}/{number}",
                    "attempt": number,
                    "status": attempt["status"],
                    "durationSeconds": attempt["durationSeconds"],
                    "startedAt": attempt.get("startedAt"),
                    "finishedAt": attempt.get("finishedAt"),
                    "assertsRun": attempt.get("assertsRun", 0),
                    "message": attempt.get("message", ""),
                }
            )

    benchmarks: list[dict[str, Any]] = []
    raw_performance = report.get("performance", [])
    if isinstance(raw_performance, dict):
        raw_performance = [raw_performance]
    for row in raw_performance:
        if not isinstance(row, dict) or not row.get("benchmarkId"):
            continue
        benchmarks.append(
            {
                "runId": run_id,
                "benchmarkId": row["benchmarkId"],
                "testId": row.get("testId", ""),
                "suite": row.get("suite", ""),
                "description": row.get("description", ""),
                "metric": row.get("metric", ""),
                "unit": row.get("unit", ""),
                "runs": row.get("runs", 0),
                "avgTimeMs": row.get("avgTimeMs"),
                "medTimeMs": row.get("medTimeMs"),
                "maxTimeMs": row.get("maxTimeMs"),
                "avgSpaceBytes": row.get("avgSpaceBytes"),
                "comparisonClass": row.get("comparison", {}).get("classification", ""),
            }
        )

    diagnostics = [
        {
            "runId": run_id,
            "diagnosticKey": f"{run_id}/diagnostic/{index}",
            "type": row.get("type", ""),
            "severity": row.get("severity", ""),
            "phase": row.get("phase", ""),
            "message": row.get("message", ""),
            "data": row.get("data", {}),
        }
        for index, row in enumerate(report.get("diagnostics", []))
    ]

    detail = coverage or {}
    coverage_runs: list[dict[str, Any]] = []
    coverage_files: list[dict[str, Any]] = []
    coverage_functions: list[dict[str, Any]] = []
    coverage_sites: list[dict[str, Any]] = []
    coverage_edges: list[dict[str, Any]] = []
    coverage_contexts: list[dict[str, Any]] = []
    coverage_context_metrics: list[dict[str, Any]] = []
    if detail:
        coverage_runs.append({"runId": run_id, **detail.get("summary", {})})
    for file_row in detail.get("files", []):
        path = str(file_row["path"])
        file_key = f"{run_id}/{path}"
        coverage_files.append(
            {
                "runId": run_id,
                "coverageFileKey": file_key,
                "path": path,
                "loaded": file_row.get("loaded", False),
                "functionFound": file_row.get("functionFound", 0),
                "functionHit": file_row.get("functionHit", 0),
                "lineFound": file_row.get("lineFound", 0),
                "lineHit": file_row.get("lineHit", 0),
            }
        )
        functions_by_name: dict[str, str] = {}
        for function in file_row.get("functions", []):
            name = str(function["name"])
            line = int(function.get("line", 0))
            function_key = f"{file_key}/{name}/{line}"
            functions_by_name.setdefault(name, function_key)
            coverage_functions.append(
                {
                    "runId": run_id,
                    "coverageFileKey": file_key,
                    "coverageFunctionKey": function_key,
                    "path": path,
                    "name": name,
                    "line": line,
                    "hits": function.get("hits", 0),
                    "covered": function.get("covered", False),
                }
            )
        for kind, source in (
            ("statement", file_row.get("statementSites", [])),
            ("branch", file_row.get("branches", [])),
        ):
            for site in source:
                site_id = str(site["siteId"])
                site_key = f"{file_key}/{site_id}"
                function_name = str(site.get("function", ""))
                coverage_sites.append(
                    {
                        "runId": run_id,
                        "coverageFileKey": file_key,
                        "coverageFunctionKey": functions_by_name.get(function_name, ""),
                        "coverageSiteKey": site_key,
                        "siteId": site_id,
                        "kind": kind,
                        "path": path,
                        "function": function_name,
                        "line": site.get("line"),
                        "column": site.get("column"),
                        "eligible": site.get("eligible", False),
                        "instrumented": site.get("instrumented", False),
                        "hits": site.get("hits", site.get("edgesHit", 0)),
                    }
                )
                for edge in site.get("edges", []):
                    edge_id = str(edge.get("edgeId", edge.get("index", "")))
                    coverage_edges.append(
                        {
                            "runId": run_id,
                            "coverageSiteKey": site_key,
                            "coverageEdgeKey": f"{site_key}/{edge_id}",
                            "edgeId": edge_id,
                            "label": edge.get("label", edge.get("edgeLabel", "")),
                            "hits": edge.get("hits", 0),
                            "covered": edge.get("covered", False),
                        }
                    )

    measurement = detail.get("contextMeasurement", {})
    for context in measurement.get("contexts", []):
        context_id = str(context["contextId"])
        context_key = f"{run_id}/{context_id}"
        coverage_contexts.append(
            {
                "runId": run_id,
                "coverageContextKey": context_key,
                "contextId": context_id,
                "kind": context.get("kind", ""),
                "testId": context.get("testId", ""),
                "attempt": context.get("attempt", 0),
                "suite": context.get("suite", ""),
                "description": context.get("description", ""),
                "file": context.get("file", ""),
            }
        )
        for metric in context.get("metrics", []):
            path = str(metric.get("file", ""))
            site_id = str(metric.get("siteId", ""))
            coverage_context_metrics.append(
                {
                    "runId": run_id,
                    "coverageContextKey": context_key,
                    "metricId": metric.get("metricId", ""),
                    "kind": metric.get("kind", ""),
                    "coverageFileKey": f"{run_id}/{path}" if path else "",
                    "coverageSiteKey": f"{run_id}/{path}/{site_id}" if path and site_id else "",
                    "function": metric.get("function", ""),
                    "edgeIndex": metric.get("edgeIndex"),
                    "edgeLabel": metric.get("edgeLabel", ""),
                    "hits": metric.get("hits", 0),
                }
            )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "resq-ingestion-tables",
        "source": {
            "reportSchemaVersion": report["schemaVersion"],
            "frameworkVersion": report["frameworkVersion"],
            "runId": run_id,
            "coverageIncluded": bool(coverage),
        },
        "tables": {
            "runs": runs,
            "tests": tests,
            "attempts": attempts,
            "benchmarks": benchmarks,
            "diagnostics": diagnostics,
            "coverageRuns": coverage_runs,
            "coverageFiles": coverage_files,
            "coverageFunctions": coverage_functions,
            "coverageSites": coverage_sites,
            "coverageEdges": coverage_edges,
            "coverageContexts": coverage_contexts,
            "coverageContextMetrics": coverage_context_metrics,
        },
    }


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected JSON object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="resQ report-v2 JSON")
    parser.add_argument("--coverage", type=Path, help="optional detailed coverage.json")
    parser.add_argument("--out", type=Path, help="destination (stdout when omitted)")
    args = parser.parse_args()
    try:
        report = read_json(args.report)
        coverage = read_json(args.coverage) if args.coverage else None
        payload = table_contract(report, coverage)
    except (OSError, json.JSONDecodeError, ValueError, KeyError) as error:
        print(f"ingestion conversion failed: {error}", file=sys.stderr)
        return 1
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if args.out:
        args.out.write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
