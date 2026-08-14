#!/usr/bin/env python3
"""Verify warm coverage-accounting costs against calibrated ratio ceilings."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "coverage_performance_probe.q"
BASELINE = ROOT / "tests" / "contracts" / "coverage-performance-baseline.json"
PREFIX = "RESQ_COVERAGE_PERF="


def run_probe(q_bin: str) -> dict[str, Any]:
    env = dict(__import__("os").environ)
    env["QBIN"] = q_bin
    completed = subprocess.run(
        [str(ROOT / "bin" / "resq"), "test", str(PROBE), "-quiet"],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
        check=False,
    )
    lines = [line for line in completed.stdout.splitlines() if line.startswith(PREFIX)]
    if completed.returncode or len(lines) != 1:
        raise RuntimeError(
            "coverage performance probe failed "
            f"(exit={completed.returncode}, payloads={len(lines)}):\n{completed.stdout}"
        )
    payload = json.loads(lines[0][len(PREFIX):])
    if payload.get("schemaVersion") != 1 or payload.get("kind") != "resq-coverage-performance-probe":
        raise ValueError("coverage performance probe returned the wrong contract")
    return payload


def summarize(payload: dict[str, Any]) -> dict[str, float]:
    samples = payload.get("samples")
    if not isinstance(samples, dict):
        raise ValueError("coverage performance probe omitted samples")
    medians: dict[str, float] = {}
    for name in (
        "controlNsPerHit",
        "statementNsPerHit",
        "contextNsPerHit",
        "reportNsPerEntry",
    ):
        values = samples.get(name)
        if not isinstance(values, list) or len(values) != 7:
            raise ValueError(f"coverage performance sample {name} must contain seven values")
        numeric = [float(value) for value in values]
        if any(value <= 0 for value in numeric):
            raise ValueError(f"coverage performance sample {name} contains a non-positive value")
        medians[name] = statistics.median(numeric)
    control = medians["controlNsPerHit"]
    medians["statementOverheadRatio"] = medians["statementNsPerHit"] / control
    medians["contextOverheadRatio"] = medians["contextNsPerHit"] / control
    return medians


def verify(result: dict[str, float], baseline: dict[str, Any]) -> list[str]:
    budgets = baseline.get("budgets", {})
    failures: list[str] = []
    checks = {
        "statementOverheadRatio": "maxStatementOverheadRatio",
        "contextOverheadRatio": "maxContextOverheadRatio",
        "reportNsPerEntry": "maxReportNsPerEntry",
    }
    for metric, budget_name in checks.items():
        ceiling = budgets.get(budget_name)
        if not isinstance(ceiling, (int, float)) or ceiling <= 0:
            failures.append(f"missing positive coverage performance budget {budget_name}")
            continue
        if result[metric] > float(ceiling):
            failures.append(
                f"{metric} {result[metric]:.2f} exceeds calibrated ceiling {float(ceiling):.2f}"
            )
    before = baseline.get("preFix", {}).get("medians", {})
    required = baseline.get("requiredSpeedup", {})
    for metric in checks:
        previous = before.get(metric)
        speedup = required.get(metric)
        if not isinstance(previous, (int, float)) or previous <= 0:
            failures.append(f"missing positive pre-fix median {metric}")
            continue
        if not isinstance(speedup, (int, float)) or speedup <= 1:
            failures.append(f"missing required speedup for {metric}")
            continue
        observed = float(previous) / result[metric]
        if observed < float(speedup):
            failures.append(
                f"{metric} speedup {observed:.2f}x is below required {float(speedup):.2f}x"
            )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable (default: q)")
    parser.add_argument(
        "--print-payload", action="store_true",
        help="print raw samples and medians as JSON (used to calibrate the checked-in baseline)",
    )
    args = parser.parse_args()
    try:
        payload = run_probe(args.q)
        medians = summarize(payload)
        if args.print_payload:
            print(json.dumps({"probe": payload, "medians": medians}, indent=2, sort_keys=True))
            return 0
        baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
        if baseline.get("schemaVersion") != 1 or baseline.get("kind") != "resq-coverage-performance-baseline":
            raise ValueError("coverage performance baseline has the wrong contract")
        workload = baseline.get("workload", {})
        for name in ("iterations", "reportContexts", "metricsPerContext"):
            if payload.get(name) != workload.get(name):
                raise ValueError(
                    f"coverage performance workload drift for {name}: "
                    f"probe={payload.get(name)!r}, baseline={workload.get(name)!r}"
                )
        failures = verify(medians, baseline)
    except (
        OSError, RuntimeError, ValueError, json.JSONDecodeError,
        subprocess.SubprocessError,
    ) as exc:
        print(f"coverage performance verification failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"medians": medians, "budgets": baseline["budgets"]}, sort_keys=True))
    if failures:
        for failure in failures:
            print(f"coverage performance verification failed: {failure}", file=sys.stderr)
        return 1
    print("coverage performance verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
