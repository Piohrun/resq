#!/usr/bin/env python3
"""Run the complete, evidence-producing resQ 1.x release gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from xml.etree import ElementTree

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402
from coverage_contract import validate_coverage_artifact  # noqa: E402
from reconcile_coverage import reconcile_reports  # noqa: E402


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
    def __init__(self, q_executable: str, output: Path) -> None:
        self.q_executable = q_executable
        self.output = output
        self.log_root = output / "logs"
        self.log_root.mkdir(parents=True, exist_ok=True)
        self.steps: list[dict[str, Any]] = []

    @staticmethod
    def slug(name: str) -> str:
        return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")

    @staticmethod
    def sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def run(
        self, name: str, command: list[str], *, cwd: Path = ROOT,
        timeout: int = 1200, extra_environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        print(f"[release] {name} ...", flush=True)
        started = time.monotonic()
        environment = dict(os.environ)
        environment["QBIN"] = self.q_executable
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment.update(extra_environment or {})
        try:
            completed = subprocess.run(
                command, cwd=cwd, env=environment, text=True,
                stdin=subprocess.DEVNULL, capture_output=True, check=False, timeout=timeout,
            )
        except subprocess.TimeoutExpired as exc:
            elapsed = time.monotonic() - started
            index = len(self.steps) + 1
            log_path = self.log_root / f"{index:02d}-{self.slug(name)}.log"
            stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            stderr = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
            log_path.write_text(
                f"name: {name}\nstatus: timeout\ncwd: {cwd}\n"
                f"command: {shlex.join(command)}\ntimeoutSeconds: {timeout}\n"
                f"\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}",
                encoding="utf-8",
            )
            self.steps.append({
                "name": name, "status": "timeout", "command": command,
                "durationSeconds": round(elapsed, 6),
                "log": str(log_path.relative_to(self.output)),
                "logSha256": self.sha256(log_path),
            })
            raise
        elapsed = time.monotonic() - started
        index = len(self.steps) + 1
        log_path = self.log_root / f"{index:02d}-{self.slug(name)}.log"
        status = "pass" if completed.returncode == 0 else "fail"
        log_path.write_text(
            f"name: {name}\nstatus: {status}\ncwd: {cwd}\n"
            f"command: {shlex.join(command)}\nexitCode: {completed.returncode}\n"
            f"durationSeconds: {elapsed:.6f}\n"
            f"\n--- stdout ---\n{completed.stdout}\n--- stderr ---\n{completed.stderr}",
            encoding="utf-8",
        )
        self.steps.append({
            "name": name, "status": status, "command": command,
            "durationSeconds": round(elapsed, 6),
            "log": str(log_path.relative_to(self.output)),
            "logSha256": self.sha256(log_path),
        })
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


def require_supported_environment(document: dict[str, Any]) -> None:
    q_version = str(document.get("run", {}).get("qVersion", ""))
    machine = platform.machine().lower()
    if not q_version.startswith("4.1"):
        raise RuntimeError(f"release support baseline requires q 4.1.x, got {q_version!r}")
    if platform.system() != "Linux" or machine not in {"x86_64", "amd64"}:
        raise RuntimeError(
            "release support baseline requires Linux x86-64, got "
            f"{platform.system()} {platform.machine()}"
        )


def verdict(document: dict[str, Any]) -> dict[str, str]:
    pairs = [((row.get("caseId") or row["testId"]), row["status"]) for row in document["tests"]]
    if len(pairs) != len({identity for identity, _ in pairs}):
        raise RuntimeError("report contains duplicate execution identities")
    return dict(pairs)


def semantic_test_projection(document: dict[str, Any]) -> list[dict[str, Any]]:
    """Project mode-independent test evidence for exact normal/isolate comparison."""
    keys = (
        "testId", "caseId", "kind", "suite", "description", "status",
        "assertsRun", "file", "line", "namespace", "tags", "parameters",
        "attempts", "retried", "flaky", "quarantine",
    )
    return [
        {key: row.get(key) for key in keys}
        for row in sorted(
            document["tests"], key=lambda item: item.get("caseId") or item["testId"]
        )
    ]


def reconcile_suites(
    normal: dict[str, Any], isolated: dict[str, Any], output: Path,
) -> dict[str, Any]:
    summary_keys = (
        "suiteCount", "testCount", "passCount", "failCount", "errorCount",
        "skipCount", "assertionCount",
    )
    normal_summary = {key: normal["summary"][key] for key in summary_keys}
    isolated_summary = {key: isolated["summary"][key] for key in summary_keys}
    normal_projection = semantic_test_projection(normal)
    isolated_projection = semantic_test_projection(isolated)
    if normal_summary != isolated_summary:
        raise RuntimeError(
            f"full isolated summary differs from normal: "
            f"{normal_summary!r} != {isolated_summary!r}"
        )
    if normal_projection != isolated_projection:
        raise RuntimeError("full isolated semantic test inventory differs from normal")
    encoded = json.dumps(normal_projection, sort_keys=True, separators=(",", ":")).encode()
    receipt = {
        "schemaVersion": 1,
        "kind": "resq-suite-reconciliation",
        "status": "pass",
        "modeIndependentSummary": normal_summary,
        "testInventorySha256": hashlib.sha256(encoded).hexdigest(),
        "stableIdVerdictParity": verdict(normal) == verdict(isolated),
        "semanticInventoryParity": True,
    }
    output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_schemas(output: Path) -> list[str]:
    destination = output / "schemas"
    destination.mkdir(parents=True, exist_ok=True)
    sources = [
        *sorted((ROOT / "docs/schema").glob("*.json")),
        ROOT / "tests/contracts/ci-lanes.json",
        ROOT / "tests/contracts/quickstart-coverage.json",
        ROOT / "tests/contracts/report-scale-budgets.json",
        ROOT / "tests/contracts/soak-budgets.json",
    ]
    archived: list[str] = []
    for source in sources:
        target = destination / source.name
        shutil.copy2(source, target)
        archived.append(str(target.relative_to(output)))
    return archived


def write_checksums(output: Path) -> Path:
    checksum_path = output / "checksums.sha256"
    rows = []
    for path in sorted(item for item in output.rglob("*") if item.is_file()):
        if path == checksum_path:
            continue
        rows.append(f"{sha256_file(path)}  {path.relative_to(output)}")
    checksum_path.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return checksum_path


def private_state_args(output: Path, lane: str) -> list[str]:
    state = output / "state"
    state.mkdir(parents=True, exist_ok=True)
    return [
        "-state-file", str(state / f"{lane}-last-run.json"),
        "-flake-history", str(state / f"{lane}-flake-history.json"),
        "-quarantine-file", str(state / f"{lane}-quarantine.json"),
        "-flake-proposal-file", str(state / f"{lane}-proposals.json"),
    ]


def _git_output(root: Path, *arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments], cwd=root, text=True, capture_output=True, check=True,
    ).stdout


def _is_excluded_checkout_path(path: Path, root: Path, output: Path | None) -> bool:
    """Return whether release-owned or index-owned state may change during the gate."""
    relative = path.relative_to(root)
    if relative.parts and relative.parts[0] == ".codegraph":
        return True
    if output is None:
        return False
    try:
        path.relative_to(output)
        return True
    except ValueError:
        return False


def _ignored_checkout_snapshot(root: Path, output: Path | None) -> dict[str, str]:
    """Fingerprint ignored files so pre-existing state is allowed but residue is not."""
    raw = subprocess.run(
        ["git", "ls-files", "--others", "--ignored", "--exclude-standard", "-z"],
        cwd=root, capture_output=True, check=True,
    ).stdout
    snapshot: dict[str, str] = {}
    for encoded in raw.split(b"\0"):
        if not encoded:
            continue
        relative = os.fsdecode(encoded)
        path = root / relative
        if _is_excluded_checkout_path(path, root, output):
            continue
        try:
            metadata = path.lstat()
            mode = metadata.st_mode & 0o7777
            if path.is_symlink():
                kind = "symlink"
                digest = hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest()
            elif path.is_file():
                kind = "file"
                digest = sha256_file(path)
            else:
                kind = "other"
                digest = hashlib.sha256(b"").hexdigest()
        except FileNotFoundError:
            # A concurrently disappearing ignored file is itself checkout drift;
            # retain a stable marker so the final comparison reports it clearly.
            mode = 0
            kind = "missing"
            digest = hashlib.sha256(b"").hexdigest()
        snapshot[Path(relative).as_posix()] = f"{kind}:{mode:o}:{digest}"
    return snapshot


def require_residue_free_checkout(
    *, root: Path = ROOT, output: Path | None = None,
    ignored_baseline: dict[str, str] | None = None,
) -> dict[str, str]:
    """Require source cleanliness and optionally compare ignored state to a baseline."""
    root = root.resolve()
    output = output.resolve() if output is not None else None
    tracked = _git_output(root, "status", "--porcelain", "--untracked-files=no").strip()
    untracked = []
    raw_untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "-z"],
        cwd=root, capture_output=True, check=True,
    ).stdout
    for encoded in raw_untracked.split(b"\0"):
        if not encoded:
            continue
        relative = os.fsdecode(encoded)
        if not _is_excluded_checkout_path(root / relative, root, output):
            untracked.append(relative)
    if tracked or untracked:
        details = [item for item in (tracked, *sorted(untracked)) if item]
        raise RuntimeError("release checkout has tracked or non-ignored changes:\n" + "\n".join(details))

    ignored = _ignored_checkout_snapshot(root, output)
    if ignored_baseline is not None and ignored != ignored_baseline:
        before = set(ignored_baseline)
        after = set(ignored)
        added = sorted(after - before)
        removed = sorted(before - after)
        changed = sorted(path for path in before & after if ignored_baseline[path] != ignored[path])
        detail = [
            *(f"added: {path}" for path in added),
            *(f"removed: {path}" for path in removed),
            *(f"changed: {path}" for path in changed),
        ]
        raise RuntimeError("release audit changed ignored checkout state:\n" + "\n".join(detail))
    return ignored


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
    validate_coverage_artifact(detail, report)
    summary = detail["summary"]
    coverage = report["coverage"]
    lcov = lcov_totals(output / "coverage.lcov")
    contract = json.loads(
        (ROOT / "tests/contracts/quickstart-coverage.json").read_text(encoding="utf-8")
    )
    expected = contract["counts"]
    completeness = contract["completeness"]
    for key, value in expected.items():
        if int(summary[key]) != value or int(coverage[key]) != value:
            raise RuntimeError(f"coverage {key} disagrees: {summary!r} / {coverage!r}")
    expected_lcov = {
        "FNF": expected["functionsFound"], "FNH": expected["functionsHit"],
        "LF": expected["linesFound"], "LH": expected["linesHit"],
        "BRF": expected["branchesFound"], "BRH": expected["branchesHit"],
    }
    if lcov != expected_lcov:
        raise RuntimeError(f"LCOV totals disagree: {lcov!r}")
    if len(detail["files"]) != 5:
        raise RuntimeError("quickstart source manifest must contain five files")
    html = (output / "coverage.html").read_text(encoding="utf-8")
    html_totals = (
        f"{expected['functionsHit']} / {expected['functionsFound']}",
        f"{expected['linesHit']} / {expected['linesFound']}",
        f"{expected['statementSitesHit']} / {expected['statementSitesFound']}",
        f"{expected['branchesHit']} / {expected['branchesFound']}",
        f"{completeness['branchSitesInstrumented']} / {completeness['branchSitesFound']}",
    )
    if not all(total in html for total in html_totals):
        raise RuntimeError("HTML does not render canonical coverage totals")
    state_rows = [
        line for line in (output / "coverage_state.txt").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    state_counts = {
        prefix: sum(row.startswith(prefix + " ") for row in state_rows)
        for prefix in ("F", "S", "B", "E")
    }
    expected_state = {
        "F": expected["functionsFound"], "S": expected["statementSitesFound"],
        "B": completeness["branchSitesFound"], "E": expected["branchesFound"],
    }
    if state_counts != expected_state:
        raise RuntimeError(f"coverage state inventory disagrees: {state_counts!r}")
    console_total = f"functions ({expected['functionsHit']}/{expected['functionsFound']})"
    if "Coverage:" not in stdout or console_total not in stdout:
        raise RuntimeError("console does not render canonical function coverage")
    if coverage["basis"] != contract["gateBasis"] or not coverage["passed"]:
        raise RuntimeError(f"coverage gate basis/verdict disagrees: {coverage!r}")
    if summary["statementInstrumentationPercent"] != 100 or summary["branchInstrumentationPercent"] != 100:
        raise RuntimeError(f"coverage instrumentation is incomplete: {summary!r}")
    if not coverage["branchMode"] or coverage["branchInstrumentationPercent"] != 100:
        raise RuntimeError(f"coverage branch contract disagrees: {coverage!r}")
    return {
        **expected,
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
    output_exclusion = requested_output.resolve() if requested_output is not None else None
    ignored_baseline = require_residue_free_checkout(output=output_exclusion)
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        capture_output=True, check=True,
    ).stdout.strip()
    output, temporary = prepare_output(requested_output)
    audit = Audit(q_executable, output)
    expected_version = release_version()
    started_at = datetime.now(timezone.utc)
    try:
        audit.run(
            "shell syntax contracts",
            ["bash", "-n", str(ROOT / "bin/resq"), str(ROOT / "bin/qspec"),
             str(ROOT / "bin/resq-merge")],
        )
        audit.run("licence-free contracts", [str(ROOT / "tools/verify_static.py")])
        audit.run(
            "Python contract tests",
            [str(ROOT / "tools/verify_python_contracts.py")],
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
                *private_state_args(output, "normal"),
            ],
            timeout=1800,
        )
        normal_report = load_report(normal_dir)
        require_version(normal_report, expected_version, "normal self suite")
        require_supported_environment(normal_report)
        verify_self_contract(normal_report)

        audit.run(
            "full strict isolated suite",
            [
                str(ROOT / "bin/resq"), "test", "tests", "-strict", "-isolate",
                "-isolateTimeout", "90", "-isolateWorkers", "4", "-json", "-junit",
                "-quiet", "-report-profile", "full", "-outDir", str(isolated_dir),
                *private_state_args(output, "isolated"),
            ],
            timeout=1800,
        )
        isolated_report = load_report(isolated_dir)
        require_version(isolated_report, expected_version, "isolated self suite")
        verify_self_contract(isolated_report)
        suite_reconciliation = reconcile_suites(
            normal_report, isolated_report, output / "suite-reconciliation.json",
        )

        differential_dir = output / "differential"
        audit.run(
            "extended loader and coverage differentials",
            [
                str(ROOT / "bin/resq"), "test", "tests/test_loader_differential.q",
                "tests/test_coverage_differential.q", "nightly/test_oversized_desc.q",
                "-strict", "-json", "-junit", "-quiet", "-report-profile", "full",
                "-outDir", str(differential_dir),
                *private_state_args(output, "differential"),
            ],
            timeout=1200,
            extra_environment={
                "RESQ_LOADER_DIFF_SEEDS": "400",
                "RESQ_COVERAGE_DIFF_SEEDS": "2000",
            },
        )
        differential_report = load_report(differential_dir)
        require_green(differential_report, "extended differential corpus")
        audit.run(
            "linear preprocessing budget",
            [
                str(ROOT / "tools/benchmark_review_regressions.py"),
                "--q", q_executable, "--report-tests", "10000",
                "--loader-counts", "50", "100", "200",
                "--max-loader-growth-ratio", "3.0",
                "--output", str(output / "preprocess-budget.json"),
            ],
            timeout=600,
        )

        audit.run("supported execution matrix", [str(ROOT / "tools/verify_execution_matrix.py"), "--q", q_executable])
        audit.run("distributed shard merge matrix", [str(ROOT / "tools/verify_shard_merge.py"), "--q", q_executable])
        audit.run("property generator and shrink protocol", [str(ROOT / "tools/verify_property_protocol.py"), "--q", q_executable])
        audit.run("flake evidence and quarantine policy", [str(ROOT / "tools/verify_quarantine.py"), "--q", q_executable])
        audit.run("snapshot inventory and recoverable pruning", [str(ROOT / "tools/verify_snapshot_inventory.py"), "--q", q_executable])
        audit.run("benchmark regression baselines and telemetry", [str(ROOT / "tools/verify_benchmark_regression.py")])
        audit.run("hostile environment audit", [str(ROOT / "tools/verify_hostile_env.py"), "--q", q_executable])
        audit.run("bounded labels and execution context", [str(ROOT / "tools/verify_labels_context.py")])
        audit.run("normalized ingestion contract", [str(ROOT / "tools/verify_ingestion_contract.py")])
        audit.run("external adoption pilots", [str(ROOT / "tools/verify_external_pilots.py"), "--q", q_executable])
        audit.run(
            "pinned qspec compatibility lanes",
            [str(ROOT / "tools/verify_qspec_compatibility.py"), "--q", q_executable,
             "--out-dir", str(output / "compatibility")],
        )
        audit.run(
            "repeated-process soak budget",
            [str(ROOT / "tools/verify_soak.py"), "--q", q_executable,
             "--output", str(output / "soak-evidence.json")],
            timeout=900,
        )
        audit.run(
            "10k artifact and 100k lifecycle scale budgets",
            [str(ROOT / "tools/verify_report_scale.py"), "--q", q_executable,
             "--output", str(output / "report-scale.json")],
            timeout=900,
        )
        audit.run(
            "empty-prefix installation",
            [str(ROOT / "tools/verify_installation.py"), "--repository", str(ROOT),
             "--ref", commit, "--q", q_executable,
             "--output", str(output / "installation-evidence.json")],
            timeout=900,
        )

        coverage_correctness_dir = output / "coverage-correctness"
        audit.run(
            "isolated quickstart correctness",
            [
                str(ROOT / "bin/resq"), "test", "examples/quickstart/test",
                "-strict", "-isolate", "-isolateTimeout", "90", "-isolateWorkers", "2",
                "-json", "-junit", "-quiet", "-report-profile", "full",
                "-outDir", str(coverage_correctness_dir),
                *private_state_args(output, "coverage-correctness"),
            ],
            timeout=300,
        )
        coverage_correctness = load_report(coverage_correctness_dir)
        require_version(coverage_correctness, expected_version, "quickstart correctness")

        coverage_dir = output / "coverage"
        coverage_run = audit.run(
            "canonical quickstart coverage",
            [
                str(ROOT / "bin/resq"), "cover", "examples/quickstart/test",
                "--source", "examples/quickstart/src", "-strict", "-cov-statements", "-cov-branches",
                "-cov-contexts",
                "-cov-min", "70", "-cov-lines-min", "80", "-cov-completeness-min", "100",
                "-cov-branches-min", "50", "-cov-branch-completeness-min", "100",
                "-json", "-junit", "-quiet",
                "-outDir", str(coverage_dir),
                *private_state_args(output, "coverage"),
            ],
            timeout=300,
        )
        coverage_summary = verify_coverage(coverage_dir, coverage_run.stdout + coverage_run.stderr)
        coverage_report = load_report(coverage_dir)
        require_version(coverage_report, expected_version, "quickstart coverage")
        coverage_reconciliation = reconcile_reports(coverage_correctness, coverage_report)
        (output / "coverage-reconciliation.json").write_text(
            json.dumps(coverage_reconciliation, indent=2) + "\n", encoding="utf-8"
        )
        require_residue_free_checkout(
            output=output_exclusion, ignored_baseline=ignored_baseline,
        )

        finished_at = datetime.now(timezone.utc)
        schema_paths = archive_schemas(output)
        uname = platform.uname()
        result = {
            "schemaVersion": 1,
            "kind": "resq-release-audit",
            "framework": "resQ",
            "status": "pass",
            "commit": commit,
            "startedAt": started_at.isoformat().replace("+00:00", "Z"),
            "finishedAt": finished_at.isoformat().replace("+00:00", "Z"),
            "durationSeconds": round((finished_at - started_at).total_seconds(), 6),
            "qVersion": normal_report["run"]["qVersion"],
            "resqVersion": normal_report["frameworkVersion"],
            "environment": {
                "platform": platform.platform(),
                "system": uname.system,
                "release": uname.release,
                "machine": uname.machine,
                "runnerIdentity": uname.node,
                "pythonVersion": platform.python_version(),
                "qExecutable": shutil.which(q_executable) or q_executable,
                "licensedRuntime": {
                    "available": True,
                    "credentialMaterialArchived": False,
                    "note": "The gate records runtime availability, never licence secrets.",
                },
            },
            "qualificationScope": {
                "qualified": ["kdb+/q 4.1.x 64-bit on Linux x86-64"],
                "unqualified": [
                    "other q 4.x releases", "macOS", "Windows",
                    "optional AxLibraries self-coverage provider",
                    "unlisted external codebases and CI providers",
                ],
            },
            "selfSuite": normal_report["summary"],
            "isolatedSuite": isolated_report["summary"],
            "suiteReconciliation": suite_reconciliation,
            "differentialCorpus": {
                "loaderSeeds": 400,
                "coverageSeeds": 2000,
                "summary": differential_report["summary"],
            },
            "preprocessingBudget": json.loads(
                (output / "preprocess-budget.json").read_text(encoding="utf-8")
            ),
            "coverage": coverage_summary,
            "coverageReconciliation": coverage_reconciliation,
            "soak": json.loads((output / "soak-evidence.json").read_text(encoding="utf-8")),
            "reportScale": json.loads(
                (output / "report-scale.json").read_text(encoding="utf-8")
            ),
            "installation": json.loads(
                (output / "installation-evidence.json").read_text(encoding="utf-8")
            ),
            "schemas": schema_paths,
            "archive": {
                "checksumAlgorithm": "SHA-256",
                "checksumManifest": "checksums.sha256",
                "rawCommandLogs": "logs/",
                "retentionPolicy": "90-day CI artifact plus attached release archive",
            },
            "steps": audit.steps,
        }
        result_path = output / "release-audit.json"
        result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        checksum_path = write_checksums(output)
        if not checksum_path.is_file() or not checksum_path.read_text(encoding="utf-8").strip():
            raise RuntimeError("release evidence checksum manifest is empty")
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
