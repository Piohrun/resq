#!/usr/bin/env python3
"""Verify the supported q runtime and resQ execution-mode equivalence matrix."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


SUPPORTED_Q = {"4.1"}
FIXTURES = [
    ROOT / "tests/fixtures/sharding/shard_a.q",
    ROOT / "tests/fixtures/sharding/shard_b.q",
    ROOT / "tests/fixtures/sharding/shard_c.q",
    ROOT / "tests/fixtures/sharding/shard_d.q",
    ROOT / "tests/fixtures/sharding/shard_e.q",
]


def q_version(q_executable: str) -> str:
    completed = subprocess.run(
        [q_executable, "-q"], input="-1 string .z.K; exit 0\n", text=True,
        capture_output=True, check=False, timeout=15,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"cannot query {q_executable}: {completed.stderr.strip()}")
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not lines:
        raise RuntimeError(f"{q_executable} did not report .z.K")
    return lines[-1]


def run_mode(root: Path, q_executable: str, name: str, flags: list[str]) -> dict[str, Any]:
    output = root / name
    state = root / "state" / f"{name}.json"
    command = [
        str(ROOT / "bin/resq"), "test", *(str(path) for path in FIXTURES),
        "-strict", "-json", "-quiet", "-outDir", str(output),
        "-state-file", str(state), *flags,
    ]
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    completed = subprocess.run(
        command, cwd=ROOT, env=environment, text=True, capture_output=True,
        check=False, timeout=120,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"mode {name} exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report_path = output / "test-results.json"
    document = json.loads(report_path.read_text(encoding="utf-8"))
    validate(document)
    return document


def verdict(document: dict[str, Any]) -> dict[str, str]:
    return {row["testId"]: row["status"] for row in document["tests"]}


def verify(q_executable: str, allow_unsupported: bool) -> None:
    version = q_version(q_executable)
    if version not in SUPPORTED_Q and not allow_unsupported:
        expected = ", ".join(sorted(SUPPORTED_Q))
        raise RuntimeError(f"unsupported q {version}; supported/tested: {expected}")
    with tempfile.TemporaryDirectory(prefix="resq-mode-matrix-") as directory:
        root = Path(directory)
        modes = {
            "normal": [],
            "isolated-sequential": ["-isolate", "-isolateTimeout", "30"],
            "isolated-concurrent": ["-isolate", "-isolateTimeout", "30", "-isolateWorkers", "3"],
            "random-normal": ["-random-order", "-seed", "4242"],
            "random-isolated": ["-isolate", "-isolateTimeout", "30", "-random-order", "-seed", "4242"],
        }
        reports = {name: run_mode(root, q_executable, name, flags) for name, flags in modes.items()}
        baseline = verdict(reports["normal"])
        if len(baseline) != 5 or set(baseline.values()) != {"pass"}:
            raise RuntimeError(f"unexpected baseline verdict: {baseline!r}")
        for name, document in reports.items():
            if verdict(document) != baseline:
                raise RuntimeError(f"{name} verdict differs from normal")
            if document["run"]["qVersion"] != version:
                raise RuntimeError(f"{name} report qVersion drifted")

        shard0 = run_mode(root, q_executable, "shard-0", ["-shard-index", "0", "-shard-count", "2"])
        shard1 = run_mode(root, q_executable, "shard-1", ["-shard-index", "1", "-shard-count", "2"])
        left, right = verdict(shard0), verdict(shard1)
        if set(left) & set(right):
            raise RuntimeError("native shards overlap")
        if {**left, **right} != baseline:
            raise RuntimeError("native shard union differs from normal")
        for index, document in enumerate((shard0, shard1)):
            shard = document["run"]["shard"]
            if shard["index"] != index or shard["count"] != 2:
                raise RuntimeError(f"shard metadata mismatch: {shard!r}")
    print(
        f"resQ execution matrix passed on q {version}: normal, isolated "
        "sequential/concurrent, seeded normal/isolated, and 2-way native shards"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable (default: q)")
    parser.add_argument(
        "--allow-unsupported", action="store_true",
        help="exercise the matrix without treating an unlisted q version as failure",
    )
    args = parser.parse_args()
    try:
        verify(args.q, args.allow_unsupported)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError, ValueError) as exc:
        print(f"execution matrix failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
