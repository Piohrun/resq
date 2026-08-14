#!/usr/bin/env python3
"""Enforce measured report, adapter, and lifecycle construction budgets."""

from __future__ import annotations

import argparse
import copy
import gc
import json
import statistics
import subprocess
import tempfile
import time
import tracemalloc
from pathlib import Path
from typing import Any, Callable

from report_profiles import project
from merge_shards import lifecycle, stable_hash_text
from resq_to_allure import allure_result
from resq_to_ndjson import records
from review_corpus import ROOT, scale_report
from validate_report import validate


DEFAULT_BUDGETS = ROOT / "tests/contracts/report-scale-budgets.json"
LIFECYCLE_SCALE_SELECTOR = "lifecycle 100k near-linear"


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


def lifecycle_document(
    test_count: int, file_count: int, suites_per_file: int,
) -> dict[str, Any]:
    """Build a valid, many-file lifecycle corpus with deterministic row order."""
    if file_count < 1 or suites_per_file < 1:
        raise ValueError("lifecycle topology dimensions must be positive")
    document = scale_report(test_count, include_events=False)
    actual_files = min(file_count, test_count)
    files: dict[str, dict[str, Any]] = {}
    suites: set[tuple[str, str]] = set()
    for index, (row, entry) in enumerate(
        zip(document["tests"], document["manifest"]["tests"], strict=True)
    ):
        file_index = index % actual_files
        suite_index = (index // actual_files) % suites_per_file
        path = f"tests/generated/lifecycle_{file_index:04d}.q"
        suite = f"lifecycle file {file_index:04d} suite {suite_index:03d}"
        file_id = "file_" + stable_hash_text(path)
        suite_id = "suite_" + stable_hash_text(path + "\n" + suite)
        row.update(
            file=path, suite=suite, line=index + 1,
            startedAt="2026-08-12T12:00:00.100000Z",
            finishedAt="2026-08-12T12:00:00.101000Z",
        )
        row["attemptHistory"][0].update(
            startedAt=row["startedAt"], finishedAt=row["finishedAt"],
        )
        entry.update(
            file=path, fileId=file_id, suite=suite, suiteId=suite_id,
            line=index + 1, shardKey=file_id,
        )
        suites.add((path, suite))
        files.setdefault(path, {
            "fileId": file_id,
            "path": path,
            "sourceDigest": stable_hash_text(f"lifecycle-source-{file_index}"),
            "assignedShard": 0,
            "selected": True,
            "shardable": True,
        })
    # Exercise and retain the benchmark timestamp contract in both builders.
    benchmark_row = document["tests"][0]
    benchmark_row["kind"] = "perf"
    benchmark_row["benchmark"] = {
        "benchmarkId": "benchmark_" + "a" * 32,
        "testId": benchmark_row["testId"],
        "file": benchmark_row["file"],
        "suite": benchmark_row["suite"],
        "description": benchmark_row["description"],
        "status": "pass",
        "runs": 3,
        "metric": "duration",
        "unit": "ns",
        "measurement": {"median": 2},
        "limits": {},
        "avgTimeMs": 0.000002,
        "minTimeMs": 0.000001,
        "medTimeMs": 0.000002,
        "maxTimeMs": 0.000003,
        "devTimeMs": 0.000001,
        "avgSpaceBytes": 0,
        "maxSpaceBytes": 0,
        "timeLimitMs": 0,
        "spaceLimitBytes": 0,
        "environment": {
            "qVersion": "4.1", "qRelease": "2024.07.08",
            "os": "linux", "architecture": "x86_64",
            "cpuModel": "synthetic", "logicalCores": 1,
            "fingerprint": "environment_" + "b" * 32,
        },
        "workload": {
            "runs": 3, "warmup": 0, "gcBefore": False,
            "gcEach": False, "space": True,
        },
        "samples": {
            "timeNs": [1, 2, 3],
            "retainedBytes": [0, 0, 0],
            "heapGrowthBytes": [0, 0, 0],
        },
        "comparison": {},
    }
    document["performance"] = [copy.deepcopy(benchmark_row["benchmark"])]
    document["manifest"]["files"] = list(files.values())
    document["summary"]["suiteCount"] = len(suites)
    shard = document["run"]["shard"]
    shard.update(
        allFileCount=len(files), selectedFileCount=len(files),
        allUnitCount=len(files), selectedUnitCount=len(files),
        selectedFiles=list(files),
    )
    document["manifest"]["shard"] = copy.deepcopy(shard)
    return document


def _lifecycle_metrics(
    events: list[dict[str, Any]], expected_benchmark_time: str,
) -> dict[str, Any]:
    event_types = [str(event["type"]) for event in events]
    encoded_sizes = [
        len(json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode())
        for event in events
    ]
    benchmark_events = [event for event in events if event["type"] == "benchmark.finished"]
    return {
        "eventCount": len(events),
        "sequenceComplete": [event["sequence"] for event in events]
        == list(range(1, len(events) + 1)),
        "typeOrderDigest": stable_hash_text("\n".join(event_types)),
        "benchmarkTimeCorrect": len(benchmark_events) == 1
        and benchmark_events[0]["occurredAt"] == expected_benchmark_time,
        "bytes": 2 + sum(encoded_sizes) + max(0, len(encoded_sizes) - 1),
        "maxRecordBytes": max(encoded_sizes, default=0),
    }


def python_lifecycle_measurement(document: dict[str, Any]) -> dict[str, Any]:
    gc.collect()
    tracemalloc.start()
    started = time.monotonic()
    events = lifecycle(
        document["run"], document["manifest"], document["tests"],
        document["summary"], document.get("coverage", {}),
        document.get("diagnostics", []), document.get("snapshotInventory", {}),
        document.get("benchmarkAnalysis", {}),
    )
    result = _lifecycle_metrics(events, document["tests"][0]["finishedAt"])
    result["wallSeconds"] = round(time.monotonic() - started, 6)
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    result["peakBytes"] = peak
    result["bytesPerTest"] = round(result["bytes"] / len(document["tests"]), 6)
    return result


def q_lifecycle_measurement(
    q_executable: str, document: dict[str, Any], directory: Path,
) -> dict[str, Any]:
    directory.mkdir(parents=True, exist_ok=True)
    source = directory / "lifecycle-report.json"
    driver = directory / "measure-lifecycle.q"
    source.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
    driver.write_text(
        "\n".join((
            "repo:first .z.x;",
            "source:.z.x 1;",
            ".resq.HOME:repo;",
            'system "l ",repo,"/lib/bootstrap.q";',
            ".utl.require repo,\"/lib/init.q\";",
            'doc:.j.k "\\n" sv read0 hsym `$source;',
            "doc[`tests]:{[raw] row:.tst.completeResultRow raw;",
            '  row[`time]:"N"$raw`time;row} each .tst.eventRows doc`tests;',
            "started:.z.p;",
            "events:.tst.lifecycleEvents[doc;doc`manifest];",
            "eventTypes:{x`type} each events;",
            "sequenceComplete:(1j+til count events)~\"j\"${x`sequence} each events;",
            'benchmarkEvents:events where {"benchmark.finished"~x`type} each events;',
            "benchmarkTimeCorrect:(1=count benchmarkEvents) and",
            "  (first[benchmarkEvents]`occurredAt)~first[doc`tests]`finishedAt;",
            "outputBytes:2j;maxRecordBytes:0j;i:0;",
            "while[i<count events;",
            "  encodedBytes:count .j.j events i;",
            "  outputBytes+:encodedBytes+$[i;1;0];",
            "  maxRecordBytes:maxRecordBytes|encodedBytes;",
            "  i+:1];",
            "elapsed:(\"f\"$.z.p-started)%1000000000;",
            "memory:.Q.w[];",
            "result:`eventCount`sequenceComplete`typeOrderDigest`benchmarkTimeCorrect`bytes`maxRecordBytes`wallSeconds`peakBytes!",
            "  (\"j\"$count events;sequenceComplete;.tst.stableHashText \"\\n\" sv eventTypes;",
            "   benchmarkTimeCorrect;outputBytes;maxRecordBytes;elapsed;\"j\"$memory`peak);",
            '-1 "RESQ_LIFECYCLE_SCALE=",.j.j result;',
            "exit 0;",
            "",
        )),
        encoding="utf-8",
    )
    completed = subprocess.run(
        [q_executable, str(driver), "-q", str(ROOT), str(source)],
        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        check=False, timeout=900,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "q lifecycle scale projection failed:\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    lines = [
        line.removeprefix("RESQ_LIFECYCLE_SCALE=")
        for line in completed.stdout.splitlines()
        if line.startswith("RESQ_LIFECYCLE_SCALE=")
    ]
    if not lines:
        raise RuntimeError(f"q lifecycle scale projection emitted no measurement: {completed.stdout!r}")
    result = json.loads(lines[-1])
    result["bytesPerTest"] = round(result["bytes"] / len(document["tests"]), 6)
    return result


def lifecycle_scale_measurement(
    q_executable: str, baseline_tests: int, qualification_tests: int,
    baseline_samples: int, file_count: int, suites_per_file: int,
) -> dict[str, Any]:
    measured_sizes: dict[str, Any] = {}
    with tempfile.TemporaryDirectory(prefix="resq-lifecycle-scale-") as raw:
        root = Path(raw)
        for label, test_count, samples in (
            ("baseline", baseline_tests, baseline_samples),
            ("qualification", qualification_tests, 1),
        ):
            document = lifecycle_document(test_count, file_count, suites_per_file)
            python_samples = [python_lifecycle_measurement(document) for _ in range(samples)]
            q_samples = [
                q_lifecycle_measurement(q_executable, document, root / f"{label}-{index}")
                for index in range(samples)
            ]
            measured_sizes[label] = {
                "tests": test_count,
                "files": len(document["manifest"]["files"]),
                "suites": document["summary"]["suiteCount"],
                "expectedEvents": (
                    4 * test_count
                    + 2 * len(document["manifest"]["files"])
                    + 2 * document["summary"]["suiteCount"]
                    + 4
                ),
                "pythonSamples": python_samples,
                "qSamples": q_samples,
            }
            del document
            gc.collect()
    return {"selector": LIFECYCLE_SCALE_SELECTOR, **measured_sizes}


def _median(samples: list[dict[str, Any]], field: str) -> float:
    return float(statistics.median(float(sample[field]) for sample in samples))


def verify_lifecycle_budget(observed: dict[str, Any], budget: dict[str, Any]) -> None:
    for label in ("baseline", "qualification"):
        measurement = observed[label]
        expected_events = measurement["expectedEvents"]
        for runtime, budget_name in (("pythonSamples", "python"), ("qSamples", "q")):
            samples = measurement[runtime]
            for sample in samples:
                if sample["eventCount"] != expected_events:
                    raise RuntimeError(
                        f"lifecycle {label}/{budget_name} emitted {sample['eventCount']} "
                        f"events; expected {expected_events}"
                    )
                if not sample["sequenceComplete"] or not sample["benchmarkTimeCorrect"]:
                    raise RuntimeError(
                        f"lifecycle {label}/{budget_name} changed event order or benchmark time"
                    )
                if sample["bytesPerTest"] > budget["maxOutputBytesPerTest"]:
                    raise RuntimeError(
                        f"lifecycle {label}/{budget_name} output is "
                        f"{sample['bytesPerTest']} bytes/test"
                    )
            limits = budget[budget_name][label]
            if _median(samples, "wallSeconds") > limits["maxWallSeconds"]:
                raise RuntimeError(f"lifecycle {label}/{budget_name} exceeded wall budget")
            if max(int(sample["peakBytes"]) for sample in samples) > limits["maxPeakBytes"]:
                raise RuntimeError(f"lifecycle {label}/{budget_name} exceeded peak-memory budget")
        python_digest = measurement["pythonSamples"][0]["typeOrderDigest"]
        q_digest = measurement["qSamples"][0]["typeOrderDigest"]
        if python_digest != q_digest:
            raise RuntimeError(f"lifecycle {label} q/Python event order differs")

    for runtime, runtime_name in (("pythonSamples", "python"), ("qSamples", "q")):
        baseline = observed["baseline"][runtime]
        qualification = observed["qualification"][runtime]
        wall_growth = _median(qualification, "wallSeconds") / max(
            _median(baseline, "wallSeconds"), 0.000001
        )
        peak_growth = max(float(sample["peakBytes"]) for sample in qualification) / max(
            max(float(sample["peakBytes"]) for sample in baseline), 1.0
        )
        if wall_growth > budget["maxWallGrowthRatio"]:
            raise RuntimeError(
                f"lifecycle {runtime_name} wall growth {wall_growth:.3f} is not near-linear"
            )
        if peak_growth > budget["maxPeakGrowthRatio"]:
            raise RuntimeError(
                f"lifecycle {runtime_name} peak growth {peak_growth:.3f} is not near-linear"
            )


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
    parser.add_argument("--lifecycle-baseline-tests", type=int, default=10_000)
    parser.add_argument("--lifecycle-tests", type=int, default=100_000)
    parser.add_argument("--lifecycle-samples", type=int, default=3)
    parser.add_argument("--budgets", type=Path, default=DEFAULT_BUDGETS)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    budgets = json.loads(args.budgets.read_text(encoding="utf-8"))
    lifecycle_budget = budgets["lifecycle"]
    for label, actual, required in (
        ("baseline tests", args.lifecycle_baseline_tests, lifecycle_budget["baselineTests"]),
        ("qualification tests", args.lifecycle_tests, lifecycle_budget["qualificationTests"]),
        ("baseline samples", args.lifecycle_samples, lifecycle_budget["baselineSamples"]),
    ):
        if actual < required:
            raise RuntimeError(
                f"lifecycle {label}={actual} is below the checked minimum {required}"
            )
    observed = {
        "schemaVersion": 2,
        "kind": "resq-report-scale-measurement",
        "green": corpus_measurement("green", args.tests, 0, args.failure_bytes, args.q),
        "failureHeavy": corpus_measurement(
            "failure-heavy", args.tests, args.failure_every, args.failure_bytes, args.q
        ),
        "lifecycle": lifecycle_scale_measurement(
            args.q, args.lifecycle_baseline_tests, args.lifecycle_tests,
            args.lifecycle_samples, lifecycle_budget["files"],
            lifecycle_budget["suitesPerFile"],
        ),
    }
    verify_budget(observed, budgets, "green")
    verify_budget(observed, budgets, "failureHeavy")
    verify_lifecycle_budget(observed["lifecycle"], lifecycle_budget)
    encoded = json.dumps(observed, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
