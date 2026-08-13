#!/usr/bin/env python3
"""Exercise bounded labels and normalized execution context end to end."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def execute(
    work: Path,
    output: str,
    extra: list[str],
    environment: dict[str, str] | None = None,
    expected: int = 0,
) -> tuple[subprocess.CompletedProcess[str], Path]:
    destination = work / output
    command = [
        str(ROOT / "bin/resq"), "test", str(work / "test_labels.q"), "-strict", "-json",
        "-quiet", "-outDir", str(destination), *extra,
    ]
    completed = subprocess.run(
        command,
        cwd=work,
        env=environment or os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != expected:
        raise AssertionError(
            f"unexpected exit {completed.returncode}, expected {expected}:\n{completed.stdout}"
        )
    return completed, destination / "test-results.json"


def load(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def verify() -> None:
    with tempfile.TemporaryDirectory(prefix="resq-label-context-") as raw:
        work = Path(raw)
        (work / "test_labels.q").write_text(
            '.tst.desc["labels"]{should["pass"]{1 musteq 1;};};\n',
            encoding="utf-8",
        )
        (work / "resq.json").write_text(
            json.dumps(
                {
                    "labels": {
                        "environment": "config",
                        "service": "orders",
                    }
                }
            ),
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["RESQ_LABELS_JSON"] = json.dumps(
            {"environment": "environment", "region": "eu-central"}
        )
        _, report_path = execute(
            work,
            "precedence",
            ["-labels", json.dumps({"deploymentId": "deploy-42", "environment": "cli"})],
            environment,
        )
        labels = load(report_path)["run"]["labels"]
        expected = {
            "deploymentId": "deploy-42",
            "environment": "cli",
            "region": "eu-central",
            "service": "orders",
        }
        if labels != expected or list(labels) != sorted(labels):
            raise AssertionError(f"label precedence/order mismatch: {labels!r}")

        hostile = os.environ.copy()
        hostile["RESQ_LABELS_JSON"] = json.dumps({"x" * 65: "value"})
        completed, rejected_path = execute(work, "hostile", [], hostile, expected=1)
        if "LABEL ERROR: RESQ_LABELS_JSON" not in completed.stdout:
            raise AssertionError("hostile environment labels lacked a clear boundary error")
        if rejected_path.exists():
            raise AssertionError("hostile labels produced a report artifact")

        _, disabled_path = execute(work, "disabled", ["-no-vcs"])
        if load(disabled_path)["run"]["vcs"]["status"] != "disabled":
            raise AssertionError("-no-vcs did not publish disabled status")

        (work / "resq.json").unlink()
        _, outside_path = execute(work, "outside", [])
        if load(outside_path)["run"]["vcs"]["status"] != "unavailable":
            raise AssertionError("a non-repository working directory did not degrade gracefully")

        github = os.environ.copy()
        github.update(
            {
                "GITHUB_ACTIONS": "true",
                "GITHUB_RUN_ID": "9001",
                "GITHUB_RUN_ATTEMPT": "2",
                "GITHUB_SHA": "abc123",
                "GITHUB_REF_NAME": "main",
                "GITHUB_REPOSITORY": "acme/orders",
                "GITHUB_WORKFLOW": "verify",
                "GITHUB_JOB": "tests",
                "GITHUB_SERVER_URL": "https://github.example",
            }
        )
        _, github_path = execute(work, "github", ["-no-vcs"], github)
        ci = load(github_path)["run"]["ci"]
        if ci["provider"] != "github" or ci["pipelineId"] != "9001":
            raise AssertionError(f"GitHub context mapping mismatch: {ci!r}")
        if ci["buildUrl"] != "https://github.example/acme/orders/actions/runs/9001":
            raise AssertionError(f"GitHub build URL mismatch: {ci!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    verify()
    print("label/context verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
