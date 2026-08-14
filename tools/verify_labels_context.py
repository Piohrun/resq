#!/usr/bin/env python3
"""Exercise bounded labels and normalized execution context end to end."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

from process_control import run_bounded


ROOT = Path(__file__).resolve().parents[1]

CI_PREFIXES = (
    "GITHUB_", "GITLAB_", "CI_", "BUILD_", "SYSTEM_", "TEAMCITY_",
    "CIRCLE_", "BUILDKITE_", "bamboo_",
)
CI_MARKERS = {"CI", "TF_BUILD", "JENKINS_URL", "CIRCLECI", "BUILDKITE"}
Q_PROCESS_TIMEOUT_SECONDS = 60


def ci_environment(values: dict[str, str]) -> dict[str, str]:
    environment = {
        key: value for key, value in os.environ.items()
        if key not in CI_MARKERS and not key.startswith(CI_PREFIXES)
    }
    environment.update(values)
    return environment


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
    completed = run_bounded(
        command,
        cwd=work,
        env=environment or os.environ.copy(),
        timeout=Q_PROCESS_TIMEOUT_SECONDS,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
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

        github = ci_environment(
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

        providers = (
            (
                "circleci",
                {
                    "CIRCLECI": "true", "CIRCLE_WORKFLOW_ID": "workflow-42",
                    "CIRCLE_WORKFLOW_JOB_ID": "job-17", "CIRCLE_BUILD_NUM": "3",
                    "CIRCLE_SHA1": "circle-sha", "CIRCLE_BRANCH": "main",
                    "CIRCLE_PROJECT_USERNAME": "acme", "CIRCLE_PROJECT_REPONAME": "orders",
                    "CIRCLE_JOB": "unit", "CIRCLE_BUILD_URL": "https://circle.example/42",
                },
                {
                    "provider": "circleci", "pipelineId": "workflow-42", "jobId": "job-17",
                    "attempt": "3", "commitSha": "circle-sha", "branch": "main",
                    "repository": "acme/orders", "workflow": "unit",
                    "buildUrl": "https://circle.example/42",
                },
            ),
            (
                "buildkite",
                {
                    "BUILDKITE": "true", "BUILDKITE_BUILD_ID": "build-42",
                    "BUILDKITE_JOB_ID": "job-17", "BUILDKITE_RETRY_COUNT": "2",
                    "BUILDKITE_COMMIT": "buildkite-sha", "BUILDKITE_BRANCH": "main",
                    "BUILDKITE_REPO": "git@example/acme/orders.git",
                    "BUILDKITE_PIPELINE_SLUG": "orders-verify",
                    "BUILDKITE_BUILD_URL": "https://buildkite.example/builds/42",
                },
                {
                    "provider": "buildkite", "pipelineId": "build-42", "jobId": "job-17",
                    "attempt": "2", "commitSha": "buildkite-sha", "branch": "main",
                    "repository": "git@example/acme/orders.git", "workflow": "orders-verify",
                    "buildUrl": "https://buildkite.example/builds/42",
                },
            ),
            (
                "teamcity",
                {
                    "TEAMCITY_VERSION": "2026.1", "BUILD_ID": "build-42",
                    "TEAMCITY_BUILDCONF_NAME": "unit", "BUILD_NUMBER": "17",
                    "BUILD_VCS_NUMBER": "teamcity-sha", "TEAMCITY_PROJECT_NAME": "orders",
                    "BUILD_URL": "https://teamcity.example/build/42",
                },
                {
                    "provider": "teamcity", "pipelineId": "build-42", "jobId": "unit",
                    "attempt": "17", "commitSha": "teamcity-sha", "branch": "",
                    "repository": "", "workflow": "orders",
                    "buildUrl": "https://teamcity.example/build/42",
                },
            ),
            (
                "bamboo",
                {
                    "bamboo_buildKey": "ORDERS-VERIFY-JOB1",
                    "bamboo_buildResultKey": "ORDERS-VERIFY-JOB1-42",
                    "bamboo_buildNumber": "42", "bamboo_planRepository_revision": "bamboo-sha",
                    "bamboo_planRepository_branch": "main",
                    "bamboo_planRepository_repositoryUrl": "ssh://example/acme/orders.git",
                    "bamboo_planName": "Orders verify",
                    "bamboo_buildResultsUrl": "https://bamboo.example/result/42",
                },
                {
                    "provider": "bamboo", "pipelineId": "ORDERS-VERIFY-JOB1-42",
                    "jobId": "ORDERS-VERIFY-JOB1", "attempt": "42",
                    "commitSha": "bamboo-sha", "branch": "main",
                    "repository": "ssh://example/acme/orders.git", "workflow": "Orders verify",
                    "buildUrl": "https://bamboo.example/result/42",
                },
            ),
        )
        for name, values, expected_ci in providers:
            _, provider_path = execute(
                work, name, ["-no-vcs"], ci_environment(values),
            )
            observed = load(provider_path)["run"]["ci"]
            if observed != expected_ci:
                raise AssertionError(
                    f"{name} context mapping mismatch: {observed!r} != {expected_ci!r}"
                )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    verify()
    print("label/context verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
