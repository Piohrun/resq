#!/usr/bin/env python3
"""Clone an exact resQ revision into an empty prefix and exercise its launchers."""

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


def run(
    command: list[str], *, cwd: Path, environment: dict[str, str] | None = None,
    timeout: int = 300,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
        text=True, capture_output=True, check=False, timeout=timeout,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command exited {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def package_version(checkout: Path, q_executable: str) -> str:
    completed = run(
        [str(checkout / "bin/resq"), "--version"], cwd=checkout,
        environment={**os.environ, "QBIN": q_executable},
    )
    output = (completed.stdout + completed.stderr).strip()
    words = output.split()
    if not words or not any(word[0:1].isdigit() for word in words):
        raise RuntimeError(f"resq --version produced an unexpected result: {output!r}")
    return output


def verify(
    repository: str, reference: str, q_executable: str, output: Path | None,
    branch_clone: bool,
) -> dict[str, Any]:
    repository_path = Path(repository)
    clone_source = str(repository_path.resolve()) if repository_path.exists() else repository
    with tempfile.TemporaryDirectory(prefix="resq-empty-install-") as raw:
        empty = Path(raw)
        prefix = empty / ".local"
        checkout = prefix / "share/resq"
        launchers = prefix / "bin"
        project = empty / "project"
        launchers.mkdir(parents=True)
        project.mkdir()

        clone = ["git", "clone", "--quiet"]
        if branch_clone:
            clone.extend(["--branch", reference, "--depth", "1"])
        else:
            clone.append("--no-hardlinks")
        clone.extend([clone_source, str(checkout)])
        run(clone, cwd=empty)
        if not branch_clone:
            run(["git", "checkout", "--quiet", "--detach", reference], cwd=checkout)

        resolved = run(["git", "rev-parse", "HEAD"], cwd=checkout).stdout.strip()
        dirty = run(["git", "status", "--porcelain"], cwd=checkout).stdout.strip()
        if dirty:
            raise RuntimeError(f"new installation is unexpectedly dirty: {dirty}")

        (launchers / "resq").symlink_to(checkout / "bin/resq")
        (launchers / "qspec").symlink_to(checkout / "bin/qspec")
        (launchers / "resq-merge").symlink_to(checkout / "bin/resq-merge")
        environment = dict(os.environ)
        environment["PATH"] = str(launchers) + os.pathsep + environment.get("PATH", "")
        environment["QBIN"] = q_executable

        version_output = package_version(checkout, q_executable)
        # resq-merge symlink: resolve the installed target before locating tools.
        merge_help = run(
            [str(launchers / "resq-merge"), "--help"], cwd=project,
            environment=environment,
        ).stdout
        if "merge" not in merge_help.lower() or "report" not in merge_help.lower():
            raise RuntimeError("installed resq-merge symlink did not reach its CLI")
        report_dir = empty / "quickstart-evidence"
        completed = run(
            [
                str(launchers / "resq"), "test",
                str(checkout / "examples/quickstart/test"), "-strict", "-json",
                "-quiet", "-outDir", str(report_dir),
                "-state-file", str(empty / "state.json"),
            ],
            cwd=project, environment=environment, timeout=600,
        )
        report = json.loads((report_dir / "test-results.json").read_text(encoding="utf-8"))
        summary = report.get("summary", {})
        if (
            summary.get("testCount", 0) < 1
            or summary.get("passCount") != summary.get("testCount")
            or summary.get("failCount")
            or summary.get("errorCount")
        ):
            raise RuntimeError(f"installed quickstart was not green: {summary!r}")
        result = {
            "schemaVersion": 1,
            "kind": "resq-installation-evidence",
            "status": "pass",
            "repository": clone_source,
            "requestedRef": reference,
            "branchClone": branch_clone,
            "resolvedCommit": resolved,
            "versionOutput": version_output,
            "quickstart": summary,
            "emptyPrefix": True,
            "symlinkLaunchers": ["resq", "qspec", "resq-merge"],
            "mergeHelp": True,
            "console": completed.stdout + completed.stderr,
        }
        if output:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=str(ROOT))
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"))
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--branch-clone", action="store_true",
        help="use the documented git clone --branch form (requires a branch or tag ref)",
    )
    args = parser.parse_args()
    try:
        result = verify(
            args.repository, args.ref, args.q, args.output, args.branch_clone,
        )
        print(
            "installation contract passed: "
            f"{result['requestedRef']} -> {result['resolvedCommit']}"
        )
        return 0
    except (
        OSError, subprocess.SubprocessError, json.JSONDecodeError,
        RuntimeError, ValueError,
    ) as exc:
        print(f"installation contract failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
