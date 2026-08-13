#!/usr/bin/env python3
"""Verify source-coverage semantics and correctness-lane reconciliation."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from coverage_contract import validate_coverage_artifact  # noqa: E402
from reconcile_coverage import reconcile_reports  # noqa: E402
from validate_report import validate  # noqa: E402


def run(command: list[str], q_executable: str) -> None:
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    completed = subprocess.run(
        command, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
        text=True, capture_output=True, check=False, timeout=180,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command exited {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )


def load(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    validate(document)
    return document


def verify(q_executable: str) -> None:
    with tempfile.TemporaryDirectory(prefix="resq-coverage-contract-") as directory:
        root = Path(directory)
        correctness_dir = root / "correctness"
        coverage_dir = root / "coverage"
        common_state = [
            "-flake-history", str(root / "flake-history.json"),
            "-quarantine-file", str(root / "quarantine.json"),
            "-flake-proposal-file", str(root / "proposals.json"),
        ]
        run(
            [
                str(ROOT / "bin/resq"), "test", "examples/quickstart/test",
                "-strict", "-isolate", "-isolateWorkers", "2", "-json", "-quiet",
                "-report-profile", "full", "-outDir", str(correctness_dir),
                "-state-file", str(root / "correctness-state.json"), *common_state,
            ],
            q_executable,
        )
        run(
            [
                str(ROOT / "bin/resq"), "cover", "examples/quickstart/test",
                "--source", "examples/quickstart/src", "-strict", "-cov-statements",
                "-cov-branches", "-cov-contexts", "-json", "-quiet",
                "-report-profile", "full", "-outDir", str(coverage_dir),
                "-state-file", str(root / "coverage-state.json"), *common_state,
            ],
            q_executable,
        )
        correctness = load(correctness_dir / "test-results.json")
        coverage = load(coverage_dir / "test-results.json")
        detail = json.loads((coverage_dir / "coverage.json").read_text(encoding="utf-8"))
        validate_coverage_artifact(detail, coverage)
        evidence = reconcile_reports(correctness, coverage)
        (root / "coverage-reconciliation.json").write_text(
            json.dumps(evidence, indent=2) + "\n", encoding="utf-8"
        )
        if not evidence["matched"] or evidence["inventory"]["tests"] != 30:
            raise RuntimeError(f"unexpected reconciliation evidence: {evidence!r}")
        metrics = [
            metric
            for context in detail["contextMeasurement"]["contexts"]
            for metric in context["metrics"]
        ]
        if not metrics or any(not metric["file"] for metric in metrics):
            raise RuntimeError("coverage context metrics lack stable file joins")
    print("coverage contract passed: detailed aggregates, contexts, and 30-test lane parity")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"), help="q executable")
    args = parser.parse_args()
    try:
        verify(args.q)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError, ValueError) as exc:
        print(f"coverage contract failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
