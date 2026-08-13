#!/usr/bin/env python3
"""Run the complete, evidence-producing resQ 1.x release gate."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


MIN_SELF_TESTS = 690
MIN_SELF_ASSERTIONS = 2100
REQUIRED_CONTRACT_TESTS = {
    "leave .q byte-for-byte equivalent while loading the framework",
    "load application functions using DSL-shaped locals while test DSL stays unqualified",
    "restore pollution after beforeAll throws, before the next suite",
    "run pollution restoration and spec cleanup after fail-hard halts",
    "finalize before re-signalling an unexpected runSpec exception",
    "have closed the leaked handle",
    "include unloaded modules from an explicit source manifest",
    "keep LCOV, JSON, HTML, state, and test JSON totals consistent",
    "refuse a line gate over partial instrumentation by default",
    "derive stable test identities from repository-relative paths",
    "replay property generation from a private seed without touching q random",
    "wrap conditions only and keep lazy branch values untouched",
    "instrument anonymous statements and branches without fake functions",
    "never classify a first failure as suspect",
    "match the reference Mann-Whitney asymptotic result",
}


class Audit:
    def __init__(self, q_executable: str) -> None:
        self.q_executable = q_executable
        self.steps: list[dict[str, Any]] = []

    def run(
        self, name: str, command: list[str], *, cwd: Path = ROOT,
        timeout: int = 1200,
    ) -> subprocess.CompletedProcess[str]:
        print(f"[release] {name} ...", flush=True)
        started = time.monotonic()
        environment = dict(os.environ)
        environment["QBIN"] = self.q_executable
        completed = subprocess.run(
            command, cwd=cwd, env=environment, text=True,
            stdin=subprocess.DEVNULL, capture_output=True, check=False, timeout=timeout,
        )
        elapsed = time.monotonic() - started
        self.steps.append({"name": name, "durationSeconds": round(elapsed, 6)})
        if completed.returncode != 0:
            raise RuntimeError(
                f"{name} exited {completed.returncode}\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
        print(f"[release] {name} passed in {elapsed:.2f}s", flush=True)
        return completed


def load_report(directory: Path) -> dict[str, Any]:
    report_path = directory / "test-results.json"
    document = json.loads(report_path.read_text(encoding="utf-8"))
    validate(document)
    if document.get("profile") != "full" or not document.get("completeness", {}).get("evidenceComplete"):
        raise RuntimeError(f"release qualification requires full evidence: {report_path}")
    ElementTree.parse(directory / "test-results.junit.xml")
    return document


def release_version() -> str:
    init = (ROOT / "lib/init.q").read_text(encoding="utf-8")
    match = re.search(r'^\.resq\.VERSION:\s*"([^"]+)";', init, re.MULTILINE)
    if not match:
        raise RuntimeError("lib/init.q does not declare .resq.VERSION")
    return match.group(1)


def require_version(document: dict[str, Any], expected: str, label: str) -> None:
    observed = {
        document.get("frameworkVersion"),
        document.get("run", {}).get("resqVersion"),
        document.get("manifest", {}).get("frameworkVersion"),
    }
    if observed != {expected}:
        raise RuntimeError(f"{label}: report version mismatch {sorted(str(value) for value in observed)!r}")


def require_green(document: dict[str, Any], label: str) -> None:
    summary = document["summary"]
    if summary["failCount"] or summary["errorCount"]:
        raise RuntimeError(f"{label}: non-green summary {summary!r}")


def verdict(document: dict[str, Any]) -> dict[str, str]:
    return {row["testId"]: row["status"] for row in document["tests"]}


def verify_self_contract(document: dict[str, Any]) -> None:
    require_green(document, "self suite")
    summary = document["summary"]
    if summary["testCount"] < MIN_SELF_TESTS:
        raise RuntimeError(f"self suite discovery shrank: {summary!r}")
    if summary["assertionCount"] < MIN_SELF_ASSERTIONS:
        raise RuntimeError(f"self suite assertion inventory shrank: {summary!r}")
    if summary["skipCount"] > 1:
        raise RuntimeError(f"self suite has unexpected skips: {summary!r}")

    rows = document["tests"]
    passed_descriptions = {
        row["description"] for row in rows if row["status"] == "pass"
    }
    missing = sorted(REQUIRED_CONTRACT_TESTS - passed_descriptions)
    if missing:
        raise RuntimeError("release contract tests absent/not passing: " + ", ".join(missing))
    if any(Path(row["file"]).is_absolute() for row in rows):
        raise RuntimeError("self suite emitted absolute test paths")
    if any("sandbox_" in row["namespace"] for row in rows):
        raise RuntimeError("self suite emitted sandbox namespaces")

    flaky = [row for row in rows if row["flaky"]]
    if not flaky or not all(row["attempts"] > 1 and row["attemptHistory"] for row in flaky):
        raise RuntimeError("self suite did not prove structured retry history")
    parameterized = [row for row in rows if row["parameterCases"]]
    if not parameterized:
        raise RuntimeError("self suite did not prove structured parameter cases")
    properties = [row for row in rows if row["property"]]
    if not properties or not all("seed" in row["property"] for row in properties):
        raise RuntimeError("self suite did not prove reproducible property seeds")


def lcov_totals(path: Path) -> dict[str, int]:
    totals = {"LF": 0, "LH": 0, "FNF": 0, "FNH": 0, "BRF": 0, "BRH": 0}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, raw = line.partition(":")
        if separator and key in totals:
            totals[key] += int(raw)
    return totals


def verify_coverage(output: Path, stdout: str) -> dict[str, Any]:
    report = load_report(output)
    require_green(report, "quickstart coverage")
    detail = json.loads((output / "coverage.json").read_text(encoding="utf-8"))
    summary = detail["summary"]
    coverage = report["coverage"]
    lcov = lcov_totals(output / "coverage.lcov")
    expected = {
        "functionsFound": 20, "functionsHit": 14,
        "linesFound": 59, "linesHit": 48,
        "statementSitesFound": 72, "statementSitesHit": 51,
        "branchesFound": 34, "branchesHit": 19,
    }
    for key, value in expected.items():
        if int(summary[key]) != value or int(coverage[key]) != value:
            raise RuntimeError(f"coverage {key} disagrees: {summary!r} / {coverage!r}")
    if lcov != {"FNF": 20, "FNH": 14, "LF": 59, "LH": 48, "BRF": 34, "BRH": 19}:
        raise RuntimeError(f"LCOV totals disagree: {lcov!r}")
    if len(detail["files"]) != 5:
        raise RuntimeError("quickstart source manifest must contain five files")
    html = (output / "coverage.html").read_text(encoding="utf-8")
    if not all(total in html for total in ("14 / 20", "48 / 59", "51 / 72", "19 / 34", "17 / 17")):
        raise RuntimeError("HTML does not render canonical coverage totals")
    state_rows = [
        line for line in (output / "coverage_state.txt").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    state_counts = {
        prefix: sum(row.startswith(prefix + " ") for row in state_rows)
        for prefix in ("F", "S", "B", "E")
    }
    if state_counts != {"F": 20, "S": 72, "B": 17, "E": 34}:
        raise RuntimeError(f"coverage state inventory disagrees: {state_counts!r}")
    if "Coverage:" not in stdout or "functions (14/20)" not in stdout:
        raise RuntimeError("console does not render canonical function coverage")
    if coverage["basis"] != "functions" or not coverage["passed"]:
        raise RuntimeError(f"coverage gate basis/verdict disagrees: {coverage!r}")
    if summary["statementInstrumentationPercent"] != 100 or summary["branchInstrumentationPercent"] != 100:
        raise RuntimeError(f"coverage instrumentation is incomplete: {summary!r}")
    if not coverage["branchMode"] or coverage["branchInstrumentationPercent"] != 100:
        raise RuntimeError(f"coverage branch contract disagrees: {coverage!r}")
    return {
        "functionsFound": 20, "functionsHit": 14,
        "linesFound": 59, "linesHit": 48,
        "statementSitesFound": 72, "statementSitesHit": 51,
        "branchesFound": 34, "branchesHit": 19,
        "statementInstrumentationPercent": summary["statementInstrumentationPercent"],
        "branchInstrumentationPercent": summary["branchInstrumentationPercent"],
    }


def prepare_output(requested: Path | None) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    if requested is None:
        temporary = tempfile.TemporaryDirectory(prefix="resq-release-audit-")
        return Path(temporary.name), temporary
    requested = requested.resolve()
    if requested.exists() and any(requested.iterdir()):
        raise RuntimeError(f"release output directory is not empty: {requested}")
    requested.mkdir(parents=True, exist_ok=True)
    return requested, None


def verify(q_executable: str, requested_output: Path | None) -> Path:
    status = subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True,
        capture_output=True, check=True,
    ).stdout.strip()
    if status:
        raise RuntimeError("release audit requires a clean worktree")
    output, temporary = prepare_output(requested_output)
    audit = Audit(q_executable)
    expected_version = release_version()
    started_at = datetime.now(timezone.utc)
    try:
        audit.run("licence-free contracts", [str(ROOT / "tools/verify_static.py")])
        audit.run(
            "Python contract tests",
            [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests", "-v"],
        )
        audit.run(
            "CLI terminal contract",
            [str(ROOT / "tools/verify_cli_terminal.py"), "--q", q_executable],
        )

        normal_dir = output / "normal"
        isolated_dir = output / "isolated"
        normal = audit.run(
            "full strict suite",
            [
                str(ROOT / "bin/resq"), "test", "tests", "-strict", "-json", "-junit",
                "-quiet", "-report-profile", "full", "-outDir", str(normal_dir),
                "-state-file", str(output / "normal-state.json"),
            ],
            timeout=1800,
        )
        normal_report = load_report(normal_dir)
        require_version(normal_report, expected_version, "normal self suite")
        verify_self_contract(normal_report)

        audit.run(
            "full strict isolated suite",
            [
                str(ROOT / "bin/resq"), "test", "tests", "-strict", "-isolate",
                "-isolateTimeout", "90", "-isolateWorkers", "4", "-json", "-junit",
                "-quiet", "-report-profile", "full", "-outDir", str(isolated_dir),
                "-state-file", str(output / "isolated-state.json"),
            ],
            timeout=1800,
        )
        isolated_report = load_report(isolated_dir)
        require_version(isolated_report, expected_version, "isolated self suite")
        verify_self_contract(isolated_report)
        if verdict(normal_report) != verdict(isolated_report):
            raise RuntimeError("full isolated verdicts differ from normal verdicts")

        audit.run("supported execution matrix", [str(ROOT / "tools/verify_execution_matrix.py"), "--q", q_executable])
        audit.run("distributed shard merge matrix", [str(ROOT / "tools/verify_shard_merge.py"), "--q", q_executable])
        audit.run("property generator and shrink protocol", [str(ROOT / "tools/verify_property_protocol.py"), "--q", q_executable])
        audit.run("flake evidence and quarantine policy", [str(ROOT / "tools/verify_quarantine.py"), "--q", q_executable])
        audit.run("snapshot inventory and recoverable pruning", [str(ROOT / "tools/verify_snapshot_inventory.py"), "--q", q_executable])
        audit.run("benchmark regression baselines and telemetry", [str(ROOT / "tools/verify_benchmark_regression.py")])
        audit.run("hostile environment audit", [str(ROOT / "tools/verify_hostile_env.py"), "--q", q_executable])
        audit.run("external adoption pilots", [str(ROOT / "tools/verify_external_pilots.py"), "--q", q_executable])

        coverage_dir = output / "coverage"
        coverage_run = audit.run(
            "canonical quickstart coverage",
            [
                str(ROOT / "bin/resq"), "cover", "examples/quickstart/test",
                "--source", "examples/quickstart/src", "-strict", "-cov-statements", "-cov-branches",
                "-cov-min", "70", "-cov-lines-min", "80", "-cov-completeness-min", "100",
                "-cov-branches-min", "50", "-cov-branch-completeness-min", "100",
                "-json", "-junit", "-quiet",
                "-outDir", str(coverage_dir), "-state-file", str(output / "coverage-state.json"),
            ],
            timeout=300,
        )
        coverage_summary = verify_coverage(coverage_dir, coverage_run.stdout + coverage_run.stderr)
        require_version(load_report(coverage_dir), expected_version, "quickstart coverage")

        finished_at = datetime.now(timezone.utc)
        commit = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
            capture_output=True, check=True,
        ).stdout.strip()
        result = {
            "schemaVersion": 1,
            "framework": "resQ",
            "status": "pass",
            "commit": commit,
            "startedAt": started_at.isoformat().replace("+00:00", "Z"),
            "finishedAt": finished_at.isoformat().replace("+00:00", "Z"),
            "durationSeconds": round((finished_at - started_at).total_seconds(), 6),
            "qVersion": normal_report["run"]["qVersion"],
            "resqVersion": normal_report["frameworkVersion"],
            "selfSuite": normal_report["summary"],
            "isolatedSuite": isolated_report["summary"],
            "coverage": coverage_summary,
            "steps": audit.steps,
        }
        result_path = output / "release-audit.json"
        result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(
            f"resQ release gate passed: {result['selfSuite']['testCount']} tests, "
            f"{result['selfSuite']['assertionCount']} assertions, normal/isolate parity; "
            f"evidence: {result_path}",
            flush=True,
        )
        if temporary is not None:
            print("release evidence used temporary storage; pass --out-dir to retain it")
        return result_path
    finally:
        # Keep the TemporaryDirectory object alive for the entire audit. Its
        # automatic cleanup occurs only after the final result has been printed.
        if temporary is not None:
            temporary.cleanup()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable (default: q)")
    parser.add_argument("--out-dir", type=Path, help="empty directory for retained evidence")
    args = parser.parse_args()
    try:
        verify(args.q, args.out_dir)
    except (
        OSError, subprocess.SubprocessError, json.JSONDecodeError,
        ElementTree.ParseError, RuntimeError, ValueError,
    ) as exc:
        print(f"resQ release gate failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
