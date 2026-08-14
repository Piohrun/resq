#!/usr/bin/env python3
"""Verify the pinned qspec surface and separate native/compatibility lanes."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from validate_report import validate


ROOT = Path(__file__).resolve().parents[1]
PINNED_QSPEC_COMMIT = "9b846b68a8d808e472ba504d18c325b14b468087"


def run(command: list[str], output: Path, q_executable: str, state_root: Path) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    completed = subprocess.run(
        [*command, "-strict", "-json", "-quiet", "-report-profile", "full",
         "-outDir", str(output), "-state-file", str(state_root / f"{output.name}-state.json"),
         "-flake-history", str(state_root / "flake.json"),
         "-quarantine-file", str(state_root / "quarantine.json"),
         "-flake-proposal-file", str(state_root / "proposals.json")],
        cwd=ROOT, env=environment, stdin=subprocess.DEVNULL, text=True,
        capture_output=True, check=False, timeout=180,
    )
    (output / "console.txt").write_text(completed.stdout + completed.stderr, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(
            f"compatibility command exited {completed.returncode}: {command!r}\n"
            f"{completed.stdout}\n{completed.stderr}"
        )
    report = json.loads((output / "test-results.json").read_text(encoding="utf-8"))
    validate(report)
    return report


def verdict(report: dict[str, Any]) -> dict[str, str]:
    return {row["testId"]: row["status"] for row in report["tests"]}


def verify(q_executable: str, destination: Path) -> Path:
    if destination.exists() and any(destination.iterdir()):
        raise RuntimeError(f"compatibility output must be empty: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    state_root = destination / "state"
    upstream = run(
        [str(ROOT / "bin/qspec"), "tests/upstream_qspec", "-plugin",
         str(ROOT / "tests/fixtures/plugins/qspec_compat_seed.q")],
        destination / "upstream", q_executable, state_root,
    )
    native = run(
        [str(ROOT / "bin/resq"), "test", "tests/compat"],
        destination / "native", q_executable, state_root,
    )
    compatible = run(
        [str(ROOT / "bin/qspec"), "tests/compat"],
        destination / "compat", q_executable, state_root,
    )
    upstream_summary = upstream["summary"]
    if upstream_summary["testCount"] != 33 or upstream_summary["assertionCount"] != 2080:
        raise RuntimeError(f"pinned upstream inventory drifted: {upstream_summary!r}")
    if verdict(native) != verdict(compatible):
        raise RuntimeError("native and compatibility public-surface verdicts differ")
    result = {
        "schemaVersion": 1,
        "kind": "resq-qspec-compatibility-evidence",
        "status": "pass",
        "pinnedQspecCommit": PINNED_QSPEC_COMMIT,
        "upstream": upstream_summary,
        "native": native["summary"],
        "compatible": compatible["summary"],
        "verdictParity": True,
    }
    receipt = destination / "compatibility-evidence.json"
    receipt.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"))
    parser.add_argument("--out-dir", type=Path)
    args = parser.parse_args()
    temporary: tempfile.TemporaryDirectory[str] | None = None
    try:
        if args.out_dir is None:
            temporary = tempfile.TemporaryDirectory(prefix="resq-qspec-compat-")
            destination = Path(temporary.name)
        else:
            destination = args.out_dir.resolve()
        receipt = verify(args.q, destination)
        print(f"qspec compatibility contract passed: {receipt}")
        return 0
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError, ValueError) as exc:
        print(f"qspec compatibility contract failed: {exc}", file=os.sys.stderr)
        return 1
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
