#!/usr/bin/env python3
"""Measure the deterministic review corpus without writing into the checkout."""

from __future__ import annotations

import argparse
import json
import os
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
        environment = dict(os.environ)
        environment["QBIN"] = q_executable
        for count in counts:
            source = root / f"loader-{count}.q"
            source.write_text(loader_source(count), encoding="utf-8")
            started = time.monotonic()
            completed = subprocess.run(
                [
                    str(ROOT / "bin/resq"), "test", str(source), "-pass",
                    "-state-file", str(root / f"state-{count}.json"),
                ],
                cwd=ROOT,
                env=environment,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                check=False,
                timeout=180,
            )
            elapsed = time.monotonic() - started
            if completed.returncode != 0:
                raise RuntimeError(
                    f"loader corpus {count} exited {completed.returncode}: "
                    f"{completed.stderr or completed.stdout}"
                )
            measurements.append({"expectations": count, "wallSeconds": round(elapsed, 6)})
    return measurements


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", help="also measure q loader corpora with this executable")
    parser.add_argument("--report-tests", type=int, default=10_000)
    parser.add_argument("--failure-every", type=int, default=0)
    parser.add_argument("--loader-counts", type=int, nargs="+", default=[50, 100, 200])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = {
        "schemaVersion": 1,
        "kind": "resq-review-benchmark",
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
        },
        "report": report_measurement(args.report_tests, args.failure_every),
        "loader": loader_measurements(args.q, args.loader_counts) if args.q else [],
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
