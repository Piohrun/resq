#!/usr/bin/env python3
"""Measure repeated in-process watch/no-exit runs against checked budgets."""

from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUDGETS = ROOT / "tests/contracts/soak-budgets.json"
PREFIX = "RESQ_SOAK_SAMPLE="


def q_driver(cycles: int) -> str:
    return "\n".join((
        ".tst.captureResourceState[];",
        ".soak.timerFingerprint:.tst.canonicalValueDigest .tst.canonicalValueBytes @[get;`.z.ts;{::}];",
        '.soak.sample:{[cycle] w:.Q.w[];resources:.tst.captureResourceState[];`cycle`usedBytes`heapBytes`symbolCount`symbolBytes`namespaceCount`ipcHandleCount`osHandleCount`timerFingerprint!(cycle;"j"$w`used;"j"$w`heap;"j"$w`syms;"j"$w`symw;"j"$count key `;"j"$count resources`ipcHandles;"j"$count resources`osHandles;.soak.timerFingerprint)};',
        '-1 "RESQ_SOAK_SAMPLE=",.j.j .soak.sample 1j;',
        "i:1j;",
        f'while[i<{cycles}j;.tst.app.exit:0b;.tst.runAll[];i+:1;-1 "RESQ_SOAK_SAMPLE=",.j.j .soak.sample i];',
        "exit 0;",
        "",
    ))


def q_version(q_executable: str) -> str:
    completed = subprocess.run(
        [q_executable, "-q"], input="-1 string .z.K; exit 0\n", text=True,
        capture_output=True, check=False, timeout=15,
    )
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if completed.returncode != 0 or not lines:
        raise RuntimeError(f"cannot query q version: {completed.stderr}")
    return lines[-1]


def growth(samples: list[dict[str, Any]], field: str, warmup: int) -> int:
    measured = samples[warmup:]
    baseline = int(measured[0][field])
    return max(int(sample[field]) for sample in measured) - baseline


def watch_probe(q_executable: str, work: Path, cycles: int = 3) -> int:
    watch_root = work / "watch"
    watch_root.mkdir()
    fixture = watch_root / "test_watch_soak.q"
    fixture.write_text(
        '.tst.desc["watch soak"]{should["passes"]{1 musteq 1}};\n',
        encoding="utf-8",
    )
    process = subprocess.Popen(
        [q_executable, str(ROOT / "resq.q"), "-q", "watch", str(watch_root), "-quiet"],
        cwd=work, env=os.environ.copy(), stdin=subprocess.DEVNULL,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    try:
        time.sleep(2.0)
        for index in range(cycles):
            with fixture.open("a", encoding="utf-8") as stream:
                stream.write(f"/ soak touch {index}\n")
            time.sleep(1.4)
        time.sleep(1.5)
    finally:
        process.terminate()
        try:
            stdout, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, _ = process.communicate(timeout=2)
    reruns = stdout.count(">> Running tests internally...")
    passes = stdout.count("1 total (1 passed")
    if reruns < cycles or passes < cycles or "Error during test run" in stdout or "'nyi" in stdout:
        raise RuntimeError(
            f"watch probe observed {reruns}/{cycles} reruns and {passes}/{cycles} passes\n{stdout}"
        )
    return reruns


def verify(q_executable: str, budgets_path: Path, output: Path | None) -> dict[str, Any]:
    budgets = json.loads(budgets_path.read_text(encoding="utf-8"))
    if budgets.get("schemaVersion") != 1 or budgets.get("kind") != "resq-soak-budgets":
        raise RuntimeError("unsupported soak budget contract")
    cycles = int(budgets["cycles"])
    warmup = int(budgets["warmupCycles"])
    if cycles < warmup + 2:
        raise RuntimeError("soak budget needs at least two measured post-warmup cycles")
    with tempfile.TemporaryDirectory(prefix="resq-soak-") as raw:
        work = Path(raw)
        fixture = ROOT / "tests/fixtures/distributed/coverage_suite.q"
        coverage_source = ROOT / "tests/fixtures/distributed/coverage_source.q"
        completed = subprocess.run(
            [q_executable, str(ROOT / "resq.q"), "-q", "test", str(fixture),
             "-noquit", "-pass", "-state-file", str(work / "state.json"),
             "-flake-history", str(work / "flake.json"),
             "-quarantine-file", str(work / "quarantine.json"),
             "-flake-proposal-file", str(work / "proposals.json"),
             "-coverage", "-source", str(coverage_source),
             "-cov-statements", "-cov-branches", "-cov-contexts"],
            cwd=work, env=os.environ.copy(), input=q_driver(cycles),
            text=True, capture_output=True, check=False, timeout=600,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"soak driver exited {completed.returncode}\n{completed.stdout}\n{completed.stderr}"
            )
        samples = [
            json.loads(line[len(PREFIX):])
            for line in completed.stdout.splitlines() if line.startswith(PREFIX)
        ]
        if len(samples) != cycles or [sample["cycle"] for sample in samples] != list(range(1, cycles + 1)):
            raise RuntimeError(
                "soak driver emitted an incomplete/non-contiguous sample series\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
        limits = budgets["limits"]
        observed = {
            "usedGrowthBytes": growth(samples, "usedBytes", warmup),
            "heapGrowthBytes": growth(samples, "heapBytes", warmup),
            "symbolGrowth": growth(samples, "symbolCount", warmup),
            "symbolBytesGrowth": growth(samples, "symbolBytes", warmup),
            "namespaceGrowth": growth(samples, "namespaceCount", warmup),
            "ipcHandleGrowth": growth(samples, "ipcHandleCount", warmup),
            "osHandleGrowth": growth(samples, "osHandleCount", warmup),
        }
        mapping = {
            "usedGrowthBytes": "maxUsedGrowthBytes",
            "heapGrowthBytes": "maxHeapGrowthBytes",
            "symbolGrowth": "maxSymbolGrowth",
            "symbolBytesGrowth": "maxSymbolBytesGrowth",
            "namespaceGrowth": "maxNamespaceGrowth",
            "ipcHandleGrowth": "maxIpcHandleGrowth",
            "osHandleGrowth": "maxOsHandleGrowth",
        }
        violations = [
            f"{field}={observed[field]} exceeds {limits[limit]}"
            for field, limit in mapping.items() if observed[field] > limits[limit]
        ]
        timers = {sample["timerFingerprint"] for sample in samples}
        if len(timers) != 1:
            violations.append("timer handler changed across cycles")
        watch_cycles = watch_probe(q_executable, work)
        result = {
            "schemaVersion": 1,
            "kind": "resq-soak-evidence",
            "status": "pass" if not violations else "fail",
            "qVersion": q_version(q_executable),
            "platform": platform.platform(),
            "cycles": cycles,
            "warmupCycles": warmup,
            "watchCycles": watch_cycles,
            "fixture": "tests/fixtures/distributed/coverage_suite.q",
            "coverageSource": "tests/fixtures/distributed/coverage_source.q",
            "limits": limits,
            "observed": observed,
            "samples": samples,
            "violations": violations,
            "note": "q symbols and empty namespace names are interned; this gate exercises bounded coverage identity/context caches across re-initialization, bounds post-warmup growth, and never claims reclamation",
        }
        if output:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        if violations:
            raise RuntimeError("; ".join(violations))
        return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"))
    parser.add_argument("--budgets", type=Path, default=DEFAULT_BUDGETS)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.q, args.budgets, args.output)
        print(f"soak contract passed: {result['cycles']} cycles; {result['observed']}")
        return 0
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError, ValueError) as exc:
        print(f"soak contract failed: {exc}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
