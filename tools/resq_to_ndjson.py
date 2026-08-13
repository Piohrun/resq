#!/usr/bin/env python3
"""Flatten a resQ report-v2 document into stateless NDJSON event records."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable

from validate_report import validate


def records(document: dict[str, Any]) -> Iterable[dict[str, Any]]:
    run = document["run"]
    context = {
        "framework": document["framework"],
        "frameworkVersion": document["frameworkVersion"],
        "schemaVersion": document["schemaVersion"],
        "runId": run["id"],
        "startedAt": run["startedAt"],
        "vcs": run["vcs"],
        "ci": run["ci"],
    }
    yield {
        **context,
        "eventType": "resq.run",
        "run": run,
        "summary": document["summary"],
        "coverage": document["coverage"],
        "diagnostics": document["diagnostics"],
        "snapshotInventory": document["snapshotInventory"],
    }
    for row in document["tests"]:
        yield {**context, "eventType": "resq.test", "test": row}
    performance = document["performance"]
    if isinstance(performance, list):
        for measurement in performance:
            yield {**context, "eventType": "resq.benchmark", "benchmark": measurement}
    elif performance:
        yield {**context, "eventType": "resq.benchmark", "benchmark": performance}


def convert(source: Path, destination: Path | None) -> int:
    document = json.loads(source.read_text(encoding="utf-8"))
    validate(document)
    body = "".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
        for record in records(document)
    )
    if destination is None:
        sys.stdout.write(body)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(body, encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="resQ test-results.json")
    parser.add_argument("-o", "--output", type=Path, help="output file (default: stdout)")
    args = parser.parse_args()
    try:
        return convert(args.report, args.output)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        print(f"resq-to-ndjson: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
