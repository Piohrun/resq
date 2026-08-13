#!/usr/bin/env python3
"""Review or explicitly replace a resQ benchmark baseline from one complete report."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from validate_report import validate


def rows(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    return [value] if isinstance(value, dict) and value else []


def require_complete(document: dict[str, Any]) -> None:
    run = document["run"]
    selection = run.get("selection", {})
    shard = run.get("shard", {})
    if selection.get("mode", "all") != "all" or selection.get("applied", False):
        raise ValueError("refusing a filtered/rerun report; benchmark baselines require a complete run")
    if int(shard.get("selectedFileCount", 0)) != int(shard.get("allFileCount", 0)):
        raise ValueError("refusing a partial file selection")
    if int(shard.get("selectedUnitCount", 0)) != int(shard.get("allUnitCount", 0)):
        raise ValueError("refusing a partial shard selection; merge every shard first")
    if int(shard.get("count", 1)) > 1 and not shard.get("merged", False):
        raise ValueError("refusing one native shard; merge every shard first")
    blocking = [
        row for row in document["tests"]
        if row["status"] in {"fail", "error"}
        and not row.get("quarantine", {}).get("nonBlocking", False)
    ]
    if blocking:
        raise ValueError("refusing a report with blocking test failures")
    for section in ("coverage", "snapshotInventory", "benchmarkAnalysis"):
        payload = document.get(section) or {}
        gate = payload.get("gate", {}) if isinstance(payload, dict) else {}
        if gate.get("enabled") and not gate.get("passed"):
            raise ValueError(f"refusing a report whose {section} gate failed")


def baseline_entry(row: dict[str, Any]) -> dict[str, Any]:
    required = {"benchmarkId", "testId", "file", "suite", "description", "workload", "samples", "environment"}
    missing = sorted(required - row.keys())
    if missing:
        raise ValueError(f"benchmark record is missing {', '.join(missing)}")
    samples = row["samples"]
    if not isinstance(samples, dict) or not isinstance(samples.get("timeNs"), list):
        raise ValueError(f"{row['benchmarkId']}: raw timeNs samples are required")
    if len(samples["timeNs"]) < 2:
        raise ValueError(f"{row['benchmarkId']}: at least two raw samples are required")
    return {
        "benchmarkId": str(row["benchmarkId"]),
        "testId": str(row["testId"]),
        "file": str(row["file"]),
        "suite": str(row["suite"]),
        "description": str(row["description"]),
        "metric": "timeNs",
        "unit": "nanoseconds",
        "workload": row["workload"],
        "samples": samples,
        "summary": {
            "avgTimeMs": row.get("avgTimeMs"),
            "minTimeMs": row.get("minTimeMs"),
            "medTimeMs": row.get("medTimeMs"),
            "maxTimeMs": row.get("maxTimeMs"),
            "devTimeMs": row.get("devTimeMs"),
            "avgSpaceBytes": row.get("avgSpaceBytes"),
            "maxSpaceBytes": row.get("maxSpaceBytes"),
        },
        "environment": row["environment"],
    }


def build(document: dict[str, Any]) -> dict[str, Any]:
    validate(document)
    require_complete(document)
    entries = [baseline_entry(row) for row in rows(document.get("performance"))]
    if not entries:
        raise ValueError("report contains no benchmark measurements")
    ids = [entry["benchmarkId"] for entry in entries]
    if len(ids) != len(set(ids)):
        raise ValueError("report contains duplicate benchmark identities")
    entries.sort(key=lambda item: (item["file"], item["suite"], item["description"], item["benchmarkId"]))
    fingerprints = {entry["environment"].get("fingerprint") for entry in entries}
    if len(fingerprints) != 1 or None in fingerprints:
        raise ValueError("benchmark records do not share one environment fingerprint")
    run = document["run"]
    return {
        "schemaVersion": 1,
        "kind": "resq-benchmark-baseline",
        "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "frameworkVersion": document["frameworkVersion"],
        "source": {
            "runId": run["id"],
            "startedAt": run["startedAt"],
            "finishedAt": run["finishedAt"],
            "vcs": run.get("vcs", {}),
            "manifestDigest": document["manifest"]["digest"],
        },
        "environment": entries[0]["environment"],
        "benchmarks": entries,
    }


def atomic_write(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="complete or strictly merged test-results.json")
    parser.add_argument("--baseline", required=True, type=Path, help="baseline file to review/update")
    parser.add_argument("--write", action="store_true", help="atomically replace the baseline (default is dry-run)")
    args = parser.parse_args()
    try:
        document = json.loads(args.report.read_text(encoding="utf-8"))
        baseline = build(document)
        if args.write:
            atomic_write(args.baseline, baseline)
    except (OSError, json.JSONDecodeError, TypeError, KeyError, ValueError) as exc:
        print(f"resq benchmark baseline update failed: {exc}")
        return 2
    action = "updated" if args.write else "would update"
    print(
        f"{action} {args.baseline} with {len(baseline['benchmarks'])} benchmark(s) "
        f"for {baseline['environment']['fingerprint']}"
    )
    if not args.write:
        print("dry-run only; pass --write after reviewing the report and environment")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
