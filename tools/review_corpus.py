#!/usr/bin/env python3
"""Generate deterministic loader and report corpora for review regressions."""

from __future__ import annotations

import argparse
import hashlib
import json
from copy import deepcopy
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "tests/contracts/report-v2.json"


def stable_id(prefix: str, value: str) -> str:
    return f"{prefix}_{hashlib.md5(value.encode('utf-8')).hexdigest()}"


def loader_source(expectation_count: int) -> str:
    """Return one assertion-dense desc block with deterministic source lines."""
    if expectation_count < 1:
        raise ValueError("expectation_count must be positive")
    lines = [f'.tst.desc["generated loader corpus {expectation_count}"]{{']
    for index in range(expectation_count):
        lines.extend(
            (
                f'  should["generated case {index:05d}"]{{',
                f"    {index} musteq {index};",
                "  };",
            )
        )
    lines.extend(("};", "", "::", ""))
    return "\n".join(lines)


def _event(
    sequence: int,
    event_type: str,
    run_id: str,
    entity_id: str,
    parent_id: str,
    occurred_at: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "sequence": sequence,
        "type": event_type,
        "runId": run_id,
        "entityId": entity_id,
        "parentId": parent_id,
        "occurredAt": occurred_at,
        "payload": payload or {},
    }


def _property_evidence() -> dict[str, Any]:
    return {
        "seed": 4242,
        "runs": 3,
        "maxFailRate": 0,
        "failRate": 0,
        "passCount": 3,
        "failCount": 0,
        "failedInputs": [],
        "shrunkInput": None,
        "generatorProtocol": "resq-generator-v1",
        "replayToken": "",
        "replayTokens": [],
        "originalInput": None,
        "minimalInput": None,
        "shrinkSteps": 0,
        "shrinkCandidates": 0,
        "shrinkTermination": "notRun",
        "failureSignature": "",
        "shrinkDurationMs": 0.0,
    }


def _coverage_evidence() -> dict[str, Any]:
    summary = {
        "linesFound": 1, "linesHit": 1, "linePercent": 100.0,
        "functionsFound": 1, "functionsHit": 1, "functionPercent": 100.0,
        "statementSitesFound": 1, "statementSitesHit": 1,
        "statementSitePercent": 100.0, "statementSitesInstrumented": 1,
        "statementSiteInstrumentationPercent": 100.0,
        "statementSiteInstrumentationComplete": True,
        "branchesFound": 2, "branchesHit": 1, "branchPercent": 50.0,
        "branchSitesEligible": 1, "branchSitesInstrumented": 1,
        "branchInstrumentationPercent": 100.0,
        "branchMode": True, "branchInstrumentationComplete": True,
        "filesFound": 1, "filesLoaded": 1, "filesWithStatements": 1,
        "functionsEligible": 1, "functionsInstrumented": 1,
        "functionInstrumentationPercent": 100.0,
        "statementFunctionsEligible": 1, "statementFunctionsInstrumented": 1,
        "statementInstrumentationPercent": 100.0,
        "statementMode": True, "statementInstrumentationComplete": True,
        "fallbackCounts": {},
    }
    gates = {}
    for name, basis, hit, found in (
        ("functions", "functions", 1, 1),
        ("lines", "measured_lines", 1, 1),
        ("completeness", "statement_instrumentation", 1, 1),
        ("branches", "branches", 1, 2),
        ("branchCompleteness", "branch_instrumentation", 1, 1),
    ):
        gates[name] = {
            "measurable": True, "basis": basis, "percent": 100.0 * hit / found,
            "hit": hit, "found": found, "minimum": 0, "passed": True,
        }
    return {
        "schemaVersion": 2, "enabled": True, "detailArtifact": "coverage.json",
        **summary, "gates": gates, "allowPartialLines": False,
        "partialLines": False, "partialBranches": False,
        "basis": "functions", "minimum": 0, "passed": True,
    }


def scale_report(
    test_count: int,
    *,
    failure_every: int = 0,
    failure_bytes: int = 1024,
    include_events: bool = True,
    include_manifest: bool = True,
    include_coverage: bool = False,
    include_property: bool = False,
    include_benchmark: bool = False,
) -> dict[str, Any]:
    """Build a stable report corpus; the default full variant validates as v2."""
    if test_count < 1:
        raise ValueError("test_count must be positive")
    if failure_every < 0 or failure_bytes < 0:
        raise ValueError("failure controls must be non-negative")

    document = json.loads(CONTRACT.read_text(encoding="utf-8"))
    row_template = document["tests"][0]
    manifest_template = document["manifest"]["tests"][0]
    run = document["run"]
    run_id = stable_id("run", f"review-corpus-{test_count}-{failure_every}")
    file_id = stable_id("file", "tests/generated/review_scale.q")
    suite_id = stable_id("suite", "review scale corpus")
    test_rows: list[dict[str, Any]] = []
    manifest_rows: list[dict[str, Any]] = []
    selected_ids: list[str] = []
    failure_text = "review-diff:" + "x" * max(0, failure_bytes - len("review-diff:"))

    for index in range(test_count):
        test_id = stable_id("test", f"review-scale-{index}")
        failed = bool(failure_every and (index + 1) % failure_every == 0)
        status = "fail" if failed else "pass"
        row = deepcopy(row_template)
        row.update(
            suite="review scale corpus",
            description=f"generated case {index:05d}",
            status=status,
            message=failure_text if failed else "",
            failures=[failure_text] if failed else [],
            file="tests/generated/review_scale.q",
            line=index + 1,
            testId=test_id,
            attemptHistory=[
                {
                    "attempt": 1,
                    "status": status,
                    "duration": "0D00:00:00.001000000",
                    "durationSeconds": 0.001,
                    "message": failure_text if failed else "",
                    "failures": [failure_text] if failed else [],
                    "assertsRun": 1,
                }
            ],
            property=_property_evidence() if include_property and index == 0 else {},
        )
        manifest_row = deepcopy(manifest_template)
        manifest_row.update(
            executionId=test_id,
            testId=test_id,
            suiteId=suite_id,
            fileId=file_id,
            file="tests/generated/review_scale.q",
            suite="review scale corpus",
            description=row["description"],
            line=row["line"],
            shardKey=file_id,
        )
        test_rows.append(row)
        manifest_rows.append(manifest_row)
        selected_ids.append(test_id)

    fail_count = sum(row["status"] == "fail" for row in test_rows)
    summary = document["summary"]
    summary.update(
        suiteCount=1,
        testCount=test_count,
        assertionCount=test_count,
        passCount=test_count - fail_count,
        failCount=fail_count,
        errorCount=0,
        skipCount=0,
        duration=f"0D00:00:{test_count / 1000:012.9f}",
        durationSeconds=round(test_count / 1000, 6),
    )
    run["id"] = run_id
    run["selection"]["selectedTestCount"] = test_count
    run["shard"].update(
        allFileCount=1,
        selectedFileCount=1,
        allUnitCount=1,
        selectedUnitCount=1,
        selectedFiles=["tests/generated/review_scale.q"],
        selectedExecutionIds=selected_ids,
    )
    document["tests"] = test_rows
    document["flake"]["insufficient"] = test_count
    document["snapshotInventory"]["generatedAt"] = run["finishedAt"]
    document["performance"] = (
        [{"description": "review benchmark samples", "samples": [1, 2, 3]}]
        if include_benchmark
        else []
    )
    document["coverage"] = _coverage_evidence() if include_coverage else {}

    digest = stable_id("manifest", "|".join(selected_ids))
    document["manifest"].update(digest=digest, tests=manifest_rows)
    document["manifest"]["files"] = [
        {
            "fileId": file_id,
            "path": "tests/generated/review_scale.q",
            "sourceDigest": hashlib.md5(loader_source(test_count).encode("utf-8")).hexdigest(),
            "assignedShard": 0,
            "selected": True,
            "shardable": True,
        }
    ]

    if include_events:
        start, finish = run["startedAt"], run["finishedAt"]
        events: list[dict[str, Any]] = []

        def emit(
            event_type: str,
            entity_id: str,
            parent_id: str,
            occurred_at: str,
            payload: dict[str, Any] | None = None,
        ) -> None:
            events.append(
                _event(
                    len(events) + 1,
                    event_type,
                    run_id,
                    entity_id,
                    parent_id,
                    occurred_at,
                    payload,
                )
            )

        emit("run.started", run_id, "", start)
        manifest = document["manifest"]
        emit("manifest.published", digest, run_id, start, {
            "schemaVersion": manifest["schemaVersion"],
            "kind": manifest["kind"],
            "digest": manifest["digest"],
            "digestAlgorithm": manifest["digestAlgorithm"],
            "identityAlgorithm": manifest["identityAlgorithm"],
            "frameworkVersion": manifest["frameworkVersion"],
            "fileCount": len(manifest["files"]),
            "testCount": len(manifest["tests"]),
        })
        emit("file.started", file_id, run_id, start)
        emit("suite.started", suite_id, file_id, start, {"testCount": test_count})
        for row in test_rows:
            test_id = row["testId"]
            attempt_id = f"{test_id}/attempt/1"
            emit("test.started", test_id, suite_id, start)
            emit("attempt.started", attempt_id, test_id, start, {"attempt": 1})
            emit(
                "attempt.finished",
                attempt_id,
                test_id,
                finish,
                {"attempt": 1, "status": row["status"], "assertsRun": 1},
            )
            emit(
                "test.finished",
                test_id,
                suite_id,
                finish,
                {"status": row["status"], "assertsRun": 1},
            )
        counts = {"testCount": test_count, "passCount": test_count - fail_count}
        emit("suite.finished", suite_id, file_id, finish, counts)
        emit("file.finished", file_id, run_id, finish, counts)
        emit("run.finished", run_id, "", finish, summary)
        document["events"] = events
    else:
        document.pop("events", None)
    if not include_manifest:
        document.pop("manifest", None)
        document.pop("events", None)
    return document


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)
    loader = subparsers.add_parser("loader", help="write an assertion-dense q source")
    loader.add_argument("count", type=int)
    loader.add_argument("output", type=Path)
    report = subparsers.add_parser("report", help="write a deterministic report corpus")
    report.add_argument("count", type=int)
    report.add_argument("output", type=Path)
    report.add_argument("--failure-every", type=int, default=0)
    report.add_argument("--failure-bytes", type=int, default=1024)
    report.add_argument("--without-events", action="store_true")
    report.add_argument("--without-manifest", action="store_true")
    report.add_argument("--coverage", action="store_true")
    report.add_argument("--property", action="store_true")
    report.add_argument("--benchmark", action="store_true")
    report.add_argument("--profile", choices=("full", "results", "telemetry"))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.mode == "loader":
        args.output.write_text(loader_source(args.count), encoding="utf-8")
    else:
        document = scale_report(
            args.count,
            failure_every=args.failure_every,
            failure_bytes=args.failure_bytes,
            include_events=not args.without_events,
            include_manifest=not args.without_manifest,
            include_coverage=args.coverage,
            include_property=args.property,
            include_benchmark=args.benchmark,
        )
        if args.profile:
            from report_profiles import project
            document = project(document, args.profile)
        args.output.write_text(json.dumps(document, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
