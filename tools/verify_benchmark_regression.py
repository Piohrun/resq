#!/usr/bin/env python3
"""End-to-end proof for benchmark baselines, gates, isolation, shards and adapters."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from merge_shards import merge  # noqa: E402
from update_benchmark_baseline import build  # noqa: E402
from validate_report import validate  # noqa: E402


def run_q(q_executable: str, fixture: Path, output: Path, extra: list[str], expected: int = 0) -> tuple[dict[str, Any], subprocess.CompletedProcess[str]]:
    command = [
        q_executable, str(ROOT / "resq.q"), "test", str(fixture), "-perf", "-json",
        "-quiet", "-outDir", str(output), "-state-file", str(output / "state.json"),
        *extra, "-exit",
    ]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False, timeout=180)
    if completed.returncode != expected:
        report_path = output / "test-results.json"
        report_detail = ""
        if report_path.is_file():
            observed = json.loads(report_path.read_text(encoding="utf-8"))
            report_detail = (
                f"\nreport summary: {observed.get('summary')}"
                f"\nbenchmark gate: {observed.get('benchmarkAnalysis', {}).get('gate')}"
                f"\ndiagnostics: {observed.get('diagnostics')}"
            )
        raise AssertionError(
            f"command exited {completed.returncode}, expected {expected}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}{report_detail}"
        )
    document = json.loads((output / "test-results.json").read_text(encoding="utf-8"))
    validate(document)
    return document, completed


def write_fixture(path: Path, name: str, delay: str = "0.001") -> None:
    path.write_text(
        f'.tst.desc["benchmark {name}"]{{\n'
        f'  perf["controlled {name}"; `runs`gc!(12;0b)]{{system "sleep {delay}"}};\n'
        '};\n',
        encoding="utf-8",
    )


def rewritten_baseline(source: Path, destination: Path, *, samples: int | None = None, environment: str | None = None, warmup: int | None = None) -> None:
    document = json.loads(source.read_text(encoding="utf-8"))
    for entry in document["benchmarks"]:
        if samples is not None:
            count = len(entry["samples"]["timeNs"])
            entry["samples"]["timeNs"] = [samples] * count
        if environment is not None:
            entry["environment"]["fingerprint"] = environment
        if warmup is not None:
            entry["workload"]["warmup"] = warmup
    if environment is not None:
        document["environment"]["fingerprint"] = environment
    destination.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def only_comparison(document: dict[str, Any], label: str = "comparison") -> dict[str, Any]:
    comparisons = document["benchmarkAnalysis"]["comparisons"]
    if len(comparisons) != 1:
        raise AssertionError(
            f"{label}: expected one comparison, got {len(comparisons)} "
            f"(enabled={document['benchmarkAnalysis']['enabled']}, "
            f"status={document['benchmarkAnalysis']['baselineStatus']}, "
            f"performance={len(document['performance'])})"
        )
    return comparisons[0]


def verify(q_executable: str) -> None:
    with tempfile.TemporaryDirectory(prefix="resq-benchmark-") as directory:
        work = Path(directory)
        fixture = work / "test_benchmark.q"
        write_fixture(fixture, "one")

        reference, _ = run_q(q_executable, fixture, work / "reference", [])
        performance = reference["performance"]
        if len(performance) != 1 or len(performance[0]["samples"]["timeNs"]) != 12:
            raise AssertionError("raw benchmark sample contract is incomplete")
        if reference["benchmarkAnalysis"]["enabled"] or reference["benchmarkAnalysis"]["counts"]["total"] != 1:
            raise AssertionError("disabled comparison must still inventory measured benchmarks")
        benchmark_id = performance[0]["benchmarkId"]
        if not benchmark_id.startswith("benchmark_") or len(benchmark_id) != 42:
            raise AssertionError("stable benchmark identity is malformed")
        benchmark_events = [
            event for event in reference["events"]
            if event["type"] == "benchmark.finished"
        ]
        if len(benchmark_events) != 1 or benchmark_events[0]["entityId"] != benchmark_id:
            raise AssertionError("benchmark lifecycle event is not keyed by stable benchmark identity")
        if benchmark_events[0]["parentId"] != performance[0]["testId"]:
            raise AssertionError("benchmark lifecycle event lost its owning test identity")

        baseline = work / "baseline.json"
        command = [
            sys.executable, str(ROOT / "tools" / "update_benchmark_baseline.py"),
            str(work / "reference" / "test-results.json"), "--baseline", str(baseline),
        ]
        dry = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
        if dry.returncode != 0 or baseline.exists() or "dry-run only" not in dry.stdout:
            raise AssertionError("baseline update is not dry-run-first")
        written = subprocess.run([*command, "--write"], cwd=ROOT, text=True, capture_output=True, check=False)
        if written.returncode != 0 or not baseline.exists():
            raise AssertionError(f"explicit baseline update failed: {written.stdout}\n{written.stderr}")
        built = json.loads(baseline.read_text(encoding="utf-8"))
        if built["schemaVersion"] != 1 or built["kind"] != "resq-benchmark-baseline":
            raise AssertionError("versioned baseline envelope is invalid")

        compared, _ = run_q(
            q_executable, fixture, work / "compared",
            ["-benchmark-baseline", str(baseline), "-benchmark-min-samples", "5"],
        )
        comparison = only_comparison(compared, "same baseline")
        if not comparison["comparable"] or comparison["classification"] not in {"improved", "stable", "regressed"}:
            raise AssertionError("same-environment baseline was not statistically compared")

        invalid_baseline = work / "invalid-baseline.json"
        invalid_document = json.loads(baseline.read_text(encoding="utf-8"))
        invalid_document["benchmarks"][0]["samples"]["timeNs"] = "not-a-sample-vector"
        invalid_baseline.write_text(json.dumps(invalid_document, indent=2) + "\n", encoding="utf-8")
        invalid, invalid_console = run_q(
            q_executable, fixture, work / "invalid",
            ["-benchmark-baseline", str(invalid_baseline), "-benchmark-gate"], expected=1,
        )
        if invalid["benchmarkAnalysis"]["baselineStatus"] != "invalid":
            raise AssertionError(
                "malformed baseline was not rejected as invalid: "
                f"{invalid['benchmarkAnalysis']['baselineStatus']}\n{invalid_console.stdout}"
            )
        if "Framework phase 'benchmarkRegression' failed" in invalid_console.stdout:
            raise AssertionError("malformed baseline escaped into the regression engine")

        slow_baseline = work / "slow-baseline.json"
        rewritten_baseline(baseline, slow_baseline, samples=1)
        regressed, console = run_q(
            q_executable, fixture, work / "regressed",
            ["-benchmark-baseline", str(slow_baseline), "-benchmark-gate"], expected=1,
        )
        regression = only_comparison(regressed, "regression")
        if regression["classification"] != "regressed" or regressed["benchmarkAnalysis"]["gate"]["passed"]:
            raise AssertionError("known regression did not fail the gate")
        if "BENCHMARK REGRESSION" not in console.stdout or "gate: FAIL" not in console.stdout:
            raise AssertionError("console did not explain the benchmark gate failure")

        fast_baseline = work / "fast-baseline.json"
        rewritten_baseline(baseline, fast_baseline, samples=10**12)
        improved, _ = run_q(
            q_executable, fixture, work / "improved",
            ["-benchmark-baseline", str(fast_baseline), "-benchmark-gate"],
        )
        if only_comparison(improved, "improvement")["classification"] != "improved":
            raise AssertionError("known improvement was not classified")

        mismatch_baseline = work / "mismatch-baseline.json"
        rewritten_baseline(
            slow_baseline, mismatch_baseline,
            environment="environment_ffffffffffffffffffffffffffffffff",
        )
        mismatch, _ = run_q(
            q_executable, fixture, work / "mismatch",
            ["-benchmark-baseline", str(mismatch_baseline), "-benchmark-gate"],
        )
        mismatch_comparison = only_comparison(mismatch, "environment mismatch")
        if mismatch_comparison["classification"] != "inconclusive" or mismatch_comparison["reason"] != "environment-mismatch":
            raise AssertionError("environment mismatch must remain non-gating and inconclusive")
        accepted, _ = run_q(
            q_executable, fixture, work / "accepted",
            ["-benchmark-baseline", str(mismatch_baseline), "-benchmark-gate", "-benchmark-accept-environment"],
            expected=1,
        )
        if only_comparison(accepted, "accepted environment")["classification"] != "regressed":
            raise AssertionError("explicitly accepted environment did not enable comparison")

        workload_baseline = work / "workload-baseline.json"
        rewritten_baseline(baseline, workload_baseline, warmup=99)
        workload, _ = run_q(
            q_executable, fixture, work / "workload",
            ["-benchmark-baseline", str(workload_baseline), "-benchmark-gate"],
        )
        if only_comparison(workload, "workload mismatch")["reason"] != "workload-mismatch":
            raise AssertionError("changed workload must be inconclusive")

        isolated, _ = run_q(
            q_executable, fixture, work / "isolated",
            ["-isolate", "-isolateWorkers", "2", "-benchmark-baseline", str(baseline)],
        )
        if [row["benchmarkId"] for row in isolated["performance"]] != [benchmark_id]:
            raise AssertionError("isolation lost or changed benchmark identity")
        if len(isolated["performance"][0]["samples"]["timeNs"]) != 12:
            raise AssertionError("isolation lost raw samples")

        shard_dir = work / "shards"
        shard_dir.mkdir()
        write_fixture(shard_dir / "test_one.q", "one")
        write_fixture(shard_dir / "test_two.q", "two", "0.002")
        full, _ = run_q(q_executable, shard_dir, work / "full", [])
        full_baseline = work / "full-baseline.json"
        full_baseline.write_text(json.dumps(build(full), indent=2) + "\n", encoding="utf-8")
        shard_reports: list[Path] = []
        for index in range(2):
            output = work / f"shard-{index}"
            run_q(
                q_executable, shard_dir, output,
                ["-shard-index", str(index), "-shard-count", "2", "-benchmark-baseline", str(full_baseline)],
            )
            shard_reports.append(output / "test-results.json")
        merged, passed = merge(shard_reports, work / "merged")
        if not passed:
            raise AssertionError("green benchmark shards merged to a failing verdict")
        if {row["benchmarkId"] for row in merged["performance"]} != {
            row["benchmarkId"] for row in full["performance"]
        }:
            raise AssertionError("shard merge lost benchmark identity")
        if merged["benchmarkAnalysis"]["counts"]["total"] != 2:
            raise AssertionError("merged benchmark analysis did not recompute the global union")
        merged_baseline = build(merged)
        if len(merged_baseline["benchmarks"]) != 2:
            raise AssertionError("strict shard union cannot be promoted to one complete baseline")

        regression_baseline = work / "shard-regression-baseline.json"
        rewritten_baseline(full_baseline, regression_baseline, samples=1)
        regression_reports: list[Path] = []
        for index in range(2):
            output = work / f"regression-shard-{index}"
            shard, _ = run_q(
                q_executable, shard_dir, output,
                ["-shard-index", str(index), "-shard-count", "2",
                 "-benchmark-baseline", str(regression_baseline), "-benchmark-gate"],
            )
            gate = shard["benchmarkAnalysis"]["gate"]
            if not gate["deferred"] or not gate["passed"] or gate["reasons"]:
                raise AssertionError("individual shard did not defer its partial benchmark gate")
            regression_reports.append(output / "test-results.json")
        regression_merged, regression_passed = merge(
            regression_reports, work / "regression-merged"
        )
        if regression_passed or regression_merged["benchmarkAnalysis"]["gate"]["passed"]:
            raise AssertionError("strict shard union did not enforce its global benchmark gate")
        if regression_merged["benchmarkAnalysis"]["gate"]["deferred"]:
            raise AssertionError("strict shard union retained a deferred gate")
        if regression_merged["benchmarkAnalysis"]["counts"]["regressed"] != 2:
            raise AssertionError("strict shard union did not recompute global regressions")

        ndjson = work / "benchmarks.ndjson"
        subprocess.run(
            [sys.executable, str(ROOT / "tools" / "resq_to_ndjson.py"),
             str(work / "regressed" / "test-results.json"), "-o", str(ndjson)],
            cwd=ROOT, check=True,
        )
        ndjson_rows = [json.loads(line) for line in ndjson.read_text(encoding="utf-8").splitlines()]
        if not any(row.get("eventType") == "resq.benchmark" and row["benchmark"].get("comparison") for row in ndjson_rows):
            raise AssertionError("NDJSON adapter omitted benchmark comparison telemetry")
        allure = work / "allure"
        subprocess.run(
            [sys.executable, str(ROOT / "tools" / "resq_to_allure.py"),
             str(work / "regressed" / "test-results.json"), str(allure)],
            cwd=ROOT, check=True,
        )
        properties = (allure / "environment.properties").read_text(encoding="utf-8")
        if "benchmarkRegressed=1" not in properties or "benchmarkGatePassed=False" not in properties:
            raise AssertionError("Allure adapter omitted benchmark gate dimensions")

        partial = json.loads(json.dumps(reference))
        partial["run"]["selection"]["mode"] = "lastFailed"
        partial["run"]["selection"]["applied"] = True
        try:
            build(partial)
        except ValueError as exc:
            if "complete run" not in str(exc):
                raise
        else:
            raise AssertionError("baseline updater accepted a partial rerun")

    print(
        "benchmark regression verification passed: raw samples, stable IDs, reference statistics, "
        "explicit and malformed baselines, regression/improvement/environment/workload policy, "
        "lifecycle identity, isolation, deferred/global shard gates, adapters"
    )


def main() -> int:
    q_executable = os.environ.get("QBIN") or shutil.which("q")
    if not q_executable:
        print("q executable not found", file=sys.stderr)
        return 2
    try:
        verify(q_executable)
    except (AssertionError, OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        print(f"benchmark regression verification failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
