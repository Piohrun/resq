#!/usr/bin/env python3
"""Measure the deterministic review corpus without writing into the checkout."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import subprocess
import tempfile
import time
import tracemalloc
from pathlib import Path
from typing import Any, Callable

from review_corpus import ROOT, loader_source, scale_report
from validate_report import validate


def robust_samples(
    measure: Callable[[], dict[str, float | int]], *, warmups: int, samples: int,
) -> tuple[list[dict[str, float | int]], dict[str, float]]:
    """Warm a workload, collect repeated samples, and median every metric."""
    if warmups < 0 or samples < 3:
        raise ValueError("review benchmarks require >=0 warmups and >=3 samples")
    for _ in range(warmups):
        measure()
    observed = [measure() for _ in range(samples)]
    numeric_keys = set.intersection(
        *(set(row) for row in observed),
    )
    medians = {
        key: float(statistics.median(float(row[key]) for row in observed))
        for key in sorted(numeric_keys)
        if all(isinstance(row[key], (int, float)) for row in observed)
    }
    return observed, medians


def _report_sample(test_count: int, failure_every: int) -> dict[str, float | int]:
    tracemalloc.start()
    started = time.monotonic()
    document = scale_report(test_count, failure_every=failure_every)
    encoded = json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8")
    elapsed = time.monotonic() - started
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    measurement = {
        "tests": test_count,
        "failureEvery": failure_every,
        "bytes": len(encoded),
        "bytesPerTest": round(len(encoded) / test_count, 6),
        "peakBytes": peak,
        "wallSeconds": round(elapsed, 6),
    }
    # Correctness is a separate verdict, outside the timed interval. A faster
    # malformed report must never be accepted as a performance improvement.
    validate(document)
    return measurement


def report_measurement(
    test_count: int, failure_every: int, *, warmups: int = 2, samples: int = 7,
) -> dict[str, Any]:
    observed, medians = robust_samples(
        lambda: _report_sample(test_count, failure_every),
        warmups=warmups,
        samples=samples,
    )
    stable = {
        key: int(medians[key]) if key in {"tests", "failureEvery", "bytes", "peakBytes"}
        else round(medians[key], 6)
        for key in medians
    }
    stable.update(
        aggregation="median",
        warmups=warmups,
        sampleCount=samples,
        samples=observed,
    )
    return stable


def loader_measurements(
    q_executable: str, counts: list[int], *, warmups: int = 2, samples: int = 7,
) -> list[dict[str, Any]]:
    measurements: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="resq-review-loader-") as directory:
        root = Path(directory)
        repo = json.dumps(str(ROOT))
        driver = root / "measure-preprocess.q"
        driver.write_text(
            "\n".join(
                (
                    f".resq.HOME:{repo};",
                    f'system "l {ROOT}/lib/bootstrap.q";',
                    f'.utl.require "{ROOT}/lib/init.q";',
                    "source:first .z.x;",
                    "started:.z.p;",
                    "rewritten:.tst.preprocessScript read0 hsym `$source;",
                    'elapsed:("f"$.z.p-started)%1000000000;',
                    "-1 string elapsed;",
                    "exit 0;",
                    "",
                )
            ),
            encoding="utf-8",
        )
        for count in counts:
            source = root / f"loader-{count}.q"
            source.write_text(loader_source(count), encoding="utf-8")
            def measure() -> dict[str, float | int]:
                completed = subprocess.run(
                    [q_executable, str(driver), str(source), "-q"],
                    cwd=ROOT,
                    stdin=subprocess.DEVNULL,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=180,
                )
                if completed.returncode != 0:
                    raise RuntimeError(
                        f"loader corpus {count} exited {completed.returncode}: "
                        f"{completed.stderr or completed.stdout}"
                    )
                lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
                if not lines:
                    raise RuntimeError(f"loader corpus {count} produced no timing")
                elapsed = float(lines[-1])
                if elapsed <= 0:
                    raise RuntimeError(f"loader corpus {count} produced invalid timing {elapsed}")
                return {"preprocessSeconds": round(elapsed, 6)}

            observed, medians = robust_samples(measure, warmups=warmups, samples=samples)
            measurements.append({
                "expectations": count,
                "preprocessSeconds": round(medians["preprocessSeconds"], 6),
                "aggregation": "median",
                "warmups": warmups,
                "sampleCount": samples,
                "samples": [row["preprocessSeconds"] for row in observed],
            })
    return measurements


def growth_ratios(measurements: list[dict[str, float | int]]) -> list[float]:
    """Return adjacent timing ratios for an increasing loader corpus."""
    ratios: list[float] = []
    for previous, current in zip(measurements, measurements[1:]):
        before = float(previous["preprocessSeconds"])
        after = float(current["preprocessSeconds"])
        ratios.append(round(after / before, 6) if before else float("inf"))
    return ratios


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", help="also measure q loader corpora with this executable")
    parser.add_argument("--report-tests", type=int, default=10_000)
    parser.add_argument("--failure-every", type=int, default=0)
    parser.add_argument("--loader-counts", type=int, nargs="+", default=[50, 100, 200])
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument(
        "--max-loader-growth-ratio",
        type=float,
        default=0,
        help="fail when any adjacent preprocessing ratio exceeds this value",
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    loader = loader_measurements(
        args.q, args.loader_counts, warmups=args.warmups, samples=args.samples,
    ) if args.q else []
    ratios = growth_ratios(loader)
    performance_failures = []
    if args.max_loader_growth_ratio and any(
        ratio > args.max_loader_growth_ratio for ratio in ratios
    ):
        performance_failures.append(
            f"loader growth ratio exceeded {args.max_loader_growth_ratio}: {ratios!r}"
        )
    result = {
        "schemaVersion": 1,
        "kind": "resq-review-benchmark",
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
        },
        "report": report_measurement(
            args.report_tests, args.failure_every,
            warmups=args.warmups, samples=args.samples,
        ),
        "loader": loader,
        "loaderGrowthRatios": ratios,
        "verdicts": {
            "correctness": {"passed": True, "reason": "every generated report validated"},
            "performance": {"passed": not performance_failures, "failures": performance_failures},
        },
    }
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    if performance_failures:
        raise RuntimeError("; ".join(performance_failures))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
