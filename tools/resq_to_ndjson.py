#!/usr/bin/env python3
"""Flatten a resQ report-v2 document into stateless NDJSON event records."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable

from validate_report import validate

DEFAULT_MAX_INPUT_BYTES = 256 * 1024 * 1024


def records(document: dict[str, Any]) -> Iterable[dict[str, Any]]:
    run = document["run"]
    context = {
        "framework": document["framework"],
        "frameworkVersion": document["frameworkVersion"],
        "schemaVersion": document["schemaVersion"],
        "runId": run["id"],
        "startedAt": run["startedAt"],
        "hostname": run.get("hostname", ""),
        "labels": run.get("labels", {}),
        "vcs": run["vcs"],
        "ci": run["ci"],
        "profile": document.get("profile", "legacy-full"),
        "completeness": document.get("completeness", {}),
    }
    normalized_run = {
        name: run[name]
        for name in (
            "id", "startedAt", "finishedAt", "durationSeconds",
            "wallDurationSeconds", "hostname", "cwd", "qVersion", "qRelease",
            "os", "resqVersion", "vcs", "ci", "config", "ordering",
            "selection", "completion", "labels",
        )
        if name in run
    }
    shard = run.get("shard")
    if isinstance(shard, dict):
        normalized_shard = {
            name: value for name, value in shard.items()
            if name not in {"selectedFiles", "selectedExecutionIds"}
        }
        normalized_shard["selectedFilePathCount"] = len(shard.get("selectedFiles", []))
        normalized_shard["selectedExecutionIdCount"] = len(
            shard.get("selectedExecutionIds", [])
        )
        normalized_run["shard"] = normalized_shard
    run_record = {
        **context,
        "eventType": "resq.run",
        "recordSchema": "resq-ndjson-v1",
        "recordOmissions": ["run.shard.selectedFiles", "run.shard.selectedExecutionIds"],
        "run": normalized_run,
        "summary": document["summary"],
        "diagnostics": document["diagnostics"],
    }
    for name in ("coverage", "snapshotInventory", "benchmarkAnalysis"):
        if name in document:
            run_record[name] = document[name]
    yield run_record
    for row in document["tests"]:
        yield {**context, "eventType": "resq.test", "test": row}
    performance = document.get("performance", [])
    if isinstance(performance, list):
        for measurement in performance:
            yield {**context, "eventType": "resq.benchmark", "benchmark": measurement}
    elif performance:
        yield {**context, "eventType": "resq.benchmark", "benchmark": performance}


def convert(
    source: Path, destination: Path | None,
    max_input_bytes: int = DEFAULT_MAX_INPUT_BYTES,
) -> int:
    if max_input_bytes < 1:
        raise ValueError("max input bytes must be positive")
    size = source.stat().st_size
    if size > max_input_bytes:
        raise ValueError(
            f"input is {size} bytes; dependency-free converter ceiling is {max_input_bytes} bytes"
        )
    with source.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    validate(document)
    if destination is not None:
        destination.parent.mkdir(parents=True, exist_ok=True)
    handle = sys.stdout if destination is None else destination.open("w", encoding="utf-8")
    try:
        for record in records(document):
            handle.write(json.dumps(
                record, ensure_ascii=False, separators=(",", ":"), allow_nan=False,
            ))
            handle.write("\n")
    finally:
        if destination is not None:
            handle.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="resQ test-results.json")
    parser.add_argument("-o", "--output", type=Path, help="output file (default: stdout)")
    parser.add_argument(
        "--max-input-bytes", type=int, default=DEFAULT_MAX_INPUT_BYTES,
        help=f"refuse larger input before JSON decoding (default: {DEFAULT_MAX_INPUT_BYTES})",
    )
    args = parser.parse_args()
    try:
        return convert(args.report, args.output, args.max_input_bytes)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        print(f"resq-to-ndjson: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
