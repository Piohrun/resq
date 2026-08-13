#!/usr/bin/env python3
"""Measure the deterministic review corpus without writing into the checkout."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import tempfile
import time
import tracemalloc
from pathlib import Path

from review_corpus import ROOT, loader_source, scale_report


def report_measurement(test_count: int, failure_every: int) -> dict[str, float | int]:
    tracemalloc.start()
    started = time.monotonic()
    document = scale_report(test_count, failure_every=failure_every)
    encoded = json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8")
    elapsed = time.monotonic() - started
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return {
        "tests": test_count,
        "failureEvery": failure_every,
        "bytes": len(encoded),
        "bytesPerTest": round(len(encoded) / test_count, 6),
        "peakBytes": peak,
        "wallSeconds": round(elapsed, 6),
    }


def loader_measurements(q_executable: str, counts: list[int]) -> list[dict[str, float | int]]:
    measurements: list[dict[str, float | int]] = []
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
            measurements.append(
                {"expectations": count, "preprocessSeconds": round(float(lines[-1]), 6)}
            )
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
    parser.add_argument(
        "--max-loader-growth-ratio",
        type=float,
        default=0,
        help="fail when any adjacent preprocessing ratio exceeds this value",
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    loader = loader_measurements(args.q, args.loader_counts) if args.q else []
    ratios = growth_ratios(loader)
    if args.max_loader_growth_ratio and any(
        ratio > args.max_loader_growth_ratio for ratio in ratios
    ):
        raise RuntimeError(
            f"loader growth ratio exceeded {args.max_loader_growth_ratio}: {ratios!r}"
        )
    result = {
        "schemaVersion": 1,
        "kind": "resq-review-benchmark",
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
        },
        "report": report_measurement(args.report_tests, args.failure_every),
        "loader": loader,
        "loaderGrowthRatios": ratios,
    }
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
