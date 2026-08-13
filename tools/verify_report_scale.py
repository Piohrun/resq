#!/usr/bin/env python3
"""Enforce measured 10k resQ artifact and adapter budgets."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import time
import tracemalloc
from pathlib import Path
from typing import Any, Callable

from report_profiles import project
from resq_to_allure import allure_result
from resq_to_ndjson import records
from review_corpus import ROOT, scale_report
from validate_report import validate


DEFAULT_BUDGETS = ROOT / "tests/contracts/report-scale-budgets.json"


def measured(operation: Callable[[], tuple[int, int]]) -> dict[str, float | int]:
    tracemalloc.start()
    started = time.monotonic()
    total_bytes, max_record_bytes = operation()
    wall = time.monotonic() - started
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return {
        "bytes": total_bytes,
        "peakBytes": peak,
        "wallSeconds": round(wall, 6),
        "maxRecordBytes": max_record_bytes,
    }


def json_measurement(document: dict[str, Any]) -> dict[str, float | int]:
    return measured(lambda: (
        len(json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()),
        0,
    ))


def record_measurement(document: dict[str, Any]) -> dict[str, float | int]:
    def encode() -> tuple[int, int]:
        sizes = [
            len(json.dumps(item, ensure_ascii=False, separators=(",", ":")).encode()) + 1
            for item in records(document)
        ]
        return sum(sizes), max(sizes, default=0)
    return measured(encode)


def allure_measurement(document: dict[str, Any]) -> dict[str, float | int]:
    def encode() -> tuple[int, int]:
        sizes = [
            len(json.dumps(allure_result(document, row), ensure_ascii=False, separators=(",", ":")).encode()) + 1
            for row in document["tests"]
        ]
        return sum(sizes), max(sizes, default=0)
    return measured(encode)


def junit_measurement(
    q_executable: str, document: dict[str, Any], directory: Path,
) -> dict[str, float | int]:
    source = directory / "report-results.json"
    output = directory / "junit.xml"
    driver = directory / "measure-junit.q"
    source.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
    driver.write_text(
        "\n".join((
            "repo:first .z.x;",
            "source:.z.x 1;",
            "output:.z.x 2;",
            ".resq.HOME:repo;",
            'system "l ",repo,"/lib/bootstrap.q";',
            ".utl.require repo,\"/lib/init.q\";",
            ".tst.loadOutputModule `junit;",
            'doc:.j.k "\\n" sv read0 hsym `$source;',
            "rawRows:doc`tests;",
            "started:.z.p;",
            'parts:enlist "";',
            "i:0;",
            "while[i<count rawRows;",
            "  rec:.tst.completeResultRow rawRows i;",
            '  rec[`time]:"N"$rec`time;',
            "  parts,:enlist .tst.output.buildJUnitCase rec;",
            "  i+:1];",
            'xml:"<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?><testsuites><testsuite>",',
            '  raze 1 _ parts,"</testsuite></testsuites>";',
            "(hsym `$output) 0:enlist xml;",
            'elapsed:("f"$.z.p-started)%1000000000;',
            "memory:.Q.w[];",
            '-1 .j.j `wallSeconds`peakBytes!(elapsed;"j"$memory`peak);',
            "exit 0;",
            "",
        )),
        encoding="utf-8",
    )
    completed = subprocess.run(
        [q_executable, str(driver), "-q", str(ROOT), str(source), str(output)],
        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        check=False, timeout=600,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"JUnit scale projection failed: {completed.stderr or completed.stdout}")
    lines = [line for line in completed.stdout.splitlines() if line.startswith("{")]
    if not lines:
        raise RuntimeError(f"JUnit scale projection emitted no measurement: {completed.stdout!r}")
    result = json.loads(lines[-1])
    result.update(bytes=output.stat().st_size, maxRecordBytes=0)
    return result


def add_rates(measurement: dict[str, float | int], test_count: int) -> dict[str, float | int]:
    return {
        **measurement,
        "bytesPerTest": round(int(measurement["bytes"]) / test_count, 6),
    }


def verify_budget(
    observed: dict[str, Any], budgets: dict[str, Any], corpus: str,
) -> None:
    limits = budgets["limits"]
    for artifact, measurement in observed[corpus]["artifacts"].items():
        budget = limits[artifact]
        for field, maximum in budget.items():
            observed_field = {
                "maxBytesPerTest": "bytesPerTest",
                "maxPeakBytes": "peakBytes",
                "maxWallSeconds": "wallSeconds",
                "maxRecordBytes": "maxRecordBytes",
            }[field]
            if float(measurement[observed_field]) > float(maximum):
                raise RuntimeError(
                    f"{corpus}/{artifact} {observed_field}={measurement[observed_field]} exceeds {maximum}"
                )


def corpus_measurement(
    name: str, test_count: int, failure_every: int, failure_bytes: int,
    q_executable: str,
) -> dict[str, Any]:
    tracemalloc.start()
    model_started = time.monotonic()
    base = scale_report(
        test_count, failure_every=failure_every, failure_bytes=failure_bytes,
    )
    model_wall = time.monotonic() - model_started
    _, model_peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    profile_peaks: dict[str, int] = {}
    profiles: dict[str, dict[str, Any]] = {}
    for profile in ("full", "results", "telemetry"):
        tracemalloc.start()
        profiles[profile] = project(base, profile)
        _, profile_peaks[profile] = tracemalloc.get_traced_memory()
        tracemalloc.stop()
    for document in profiles.values():
        validate(document)
    failures = [row for row in base["tests"] if row["status"] == "fail"]
    transcript = {
        "failureCount": len(failures),
        "expectedBytes": failure_bytes if failures else 0,
        "complete": all(len(row["message"].encode()) == failure_bytes for row in failures),
        "profileMessagesEqual": all(
            profiles["results"]["tests"][index]["message"] == row["message"]
            and profiles["telemetry"]["tests"][index]["message"] == row["message"]
            for index, row in enumerate(base["tests"])
        ),
    }
    if not transcript["complete"] or not transcript["profileMessagesEqual"]:
        raise RuntimeError(f"{name}: bounded transcript evidence was silently changed")
    artifacts = {
        profile: add_rates(json_measurement(document), test_count)
        for profile, document in profiles.items()
    }
    for profile, peak in profile_peaks.items():
        artifacts[profile]["peakBytes"] = max(int(artifacts[profile]["peakBytes"]), peak)
    artifacts["model"] = add_rates({
        "bytes": 0, "peakBytes": model_peak, "wallSeconds": round(model_wall, 6),
        "maxRecordBytes": 0,
    }, test_count)
    artifacts["ndjson"] = add_rates(record_measurement(profiles["telemetry"]), test_count)
    artifacts["allure"] = add_rates(allure_measurement(profiles["results"]), test_count)
    with tempfile.TemporaryDirectory(prefix=f"resq-{name}-junit-") as directory:
        artifacts["junit"] = add_rates(
            junit_measurement(q_executable, profiles["results"], Path(directory)), test_count
        )
    return {"tests": test_count, "artifacts": artifacts, "transcript": transcript}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q")
    parser.add_argument("--tests", type=int, default=10_000)
    parser.add_argument("--failure-every", type=int, default=2)
    parser.add_argument("--failure-bytes", type=int, default=1024)
    parser.add_argument("--budgets", type=Path, default=DEFAULT_BUDGETS)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    budgets = json.loads(args.budgets.read_text(encoding="utf-8"))
    observed = {
        "schemaVersion": 1,
        "kind": "resq-report-scale-measurement",
        "green": corpus_measurement("green", args.tests, 0, args.failure_bytes, args.q),
        "failureHeavy": corpus_measurement(
            "failure-heavy", args.tests, args.failure_every, args.failure_bytes, args.q
        ),
    }
    verify_budget(observed, budgets, "green")
    verify_budget(observed, budgets, "failureHeavy")
    encoded = json.dumps(observed, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
