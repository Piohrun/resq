#!/usr/bin/env python3
"""Prove file/test/case shard and strict-merge equivalence on a real q run."""

from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/distributed/distributed_suite.q"
FAIL_FAST = ROOT / "tests/fixtures/distributed/fail_fast_suite.q"
COVERAGE_FIXTURE = ROOT / "tests/fixtures/distributed/coverage_suite.q"
COVERAGE_SOURCE = ROOT / "tests/fixtures/distributed/coverage_source.q"
PLUGIN_FIXTURE = ROOT / "tests/fixtures/sharding/shard_a.q"
PLUGIN = ROOT / "tests/fixtures/plugins/contract_plugin.q"
MERGER = ROOT / "tools/merge_shards.py"
sys.path.insert(0, str(ROOT / "tools"))
from merge_shards import (  # noqa: E402
    MergeError, merge, merge_performance, validate_results, validate_snapshot_ownership,
)
from validate_report import validate  # noqa: E402


def private_state(output: Path) -> list[str]:
    state_root = output.parent / "state"
    state_root.mkdir(parents=True, exist_ok=True)
    topology = re.sub(r"-\d+$", "", output.name)
    return [
        "-state-file", str(output.with_suffix(".state.json")),
        "-flake-history", str(state_root / f"{topology}-flake.json"),
        "-quarantine-file", str(state_root / f"{topology}-quarantine.json"),
        "-flake-proposal-file", str(state_root / f"{topology}-proposals.json"),
    ]


def run(
    q_executable: str, output: Path, flags: list[str], *, fixture: Path = FIXTURE,
    expected_codes: set[int] = {0},
) -> dict[str, Any]:
    command = [
        str(ROOT / "bin/resq"), "test", str(fixture), "-strict", "-json", "-quiet",
        "-outDir", str(output), *private_state(output), *flags,
    ]
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    completed = subprocess.run(
        command, cwd=ROOT, env=environment, text=True, capture_output=True,
        stdin=subprocess.DEVNULL, check=False, timeout=120,
    )
    if completed.returncode not in expected_codes:
        raise RuntimeError(
            f"run exited {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report = json.loads((output / "test-results.json").read_text(encoding="utf-8"))
    validate(report)
    return report


def run_coverage(q_executable: str, output: Path, flags: list[str]) -> tuple[dict[str, Any], dict[str, Any]]:
    command = [
        str(ROOT / "bin/resq"), "cover", str(COVERAGE_FIXTURE),
        "--source", str(COVERAGE_SOURCE), "-strict", "-json", "-quiet",
        "-cov-statements", "-cov-branches", "-cov-contexts",
        "-outDir", str(output), *private_state(output), *flags,
    ]
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    completed = subprocess.run(
        command, cwd=ROOT, env=environment, text=True, capture_output=True,
        stdin=subprocess.DEVNULL, check=False, timeout=120,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"coverage run exited {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report = json.loads((output / "test-results.json").read_text(encoding="utf-8"))
    validate(report)
    coverage = json.loads((output / "coverage.json").read_text(encoding="utf-8"))
    return report, coverage


def run_strict_plugin_shard(
    q_executable: str, output: Path, index: int, count: int,
) -> dict[str, Any]:
    command = [
        str(ROOT / "bin/resq"), "test", str(PLUGIN_FIXTURE),
        "-plugin", str(PLUGIN), "-strict-plugins", "-json", "-quiet",
        "-shard-index", str(index), "-shard-count", str(count),
        "-outDir", str(output), *private_state(output),
    ]
    environment = dict(os.environ)
    environment.update(
        QBIN=q_executable, RESQ_PLUGIN_FAIL="1",
        RESQ_PLUGIN_OUTPUT=str(output.with_suffix(".plugin.json")),
    )
    completed = subprocess.run(
        command, cwd=ROOT, env=environment, text=True, capture_output=True,
        stdin=subprocess.DEVNULL, check=False, timeout=120,
    )
    if completed.returncode != 1:
        raise RuntimeError(
            f"strict plugin shard exited {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report = json.loads((output / "test-results.json").read_text(encoding="utf-8"))
    validate(report)
    return report


def verdict(document: dict[str, Any]) -> dict[str, str]:
    return {(row["caseId"] or row["testId"]): row["status"] for row in document["tests"]}


def merged(root: Path, name: str, reports: list[Path]) -> dict[str, Any]:
    destination = root / f"merged-{name}"
    report, passed = merge(reports, destination)
    if not passed:
        raise RuntimeError(f"{name}: green shard set merged to a failing verdict")
    validate(report)
    return report


def verify(q_executable: str) -> None:
    with tempfile.TemporaryDirectory(prefix="resq-shard-merge-") as directory:
        root = Path(directory)
        baseline = run(q_executable, root / "baseline", [])
        expected = verdict(baseline)
        if len(expected) != 8 or baseline["summary"]["assertionCount"] != 18:
            raise RuntimeError(f"unexpected distributed fixture baseline: {baseline['summary']!r}")
        declared = [row for row in baseline["tests"] if row["kind"] == "case"]
        if (
            len(declared) != 4
            or len({row["testId"] for row in declared}) != 1
            or len({row["caseId"] for row in declared}) != 4
            or [row["parameters"]["input"] for row in declared] != [1, 2, 3, 4]
            or any(not isinstance(row["line"], int) or row["line"] < 1 for row in declared)
        ):
            raise RuntimeError("declarative case identity/parameter/source contract is incomplete")
        dynamic = {
            row["description"]: row for row in baseline["tests"]
            if row["description"].startswith("dynamic ")
        }
        if (
            len(dynamic["dynamic forall cases remain atomic"]["parameterCases"]) != 3
            or len(dynamic["dynamic parametrize cases remain atomic"]["parameterCases"]) != 4
            or any(row["caseId"] for row in dynamic.values())
        ):
            raise RuntimeError("dynamic parameter cases did not remain nested/atomic")
        retry = next(row for row in baseline["tests"] if row["description"] == "retry history survives sharding")
        if (retry["attempts"], retry["retried"], retry["flaky"]) != (2, True, True):
            raise RuntimeError("retry telemetry baseline is not a two-attempt flaky pass")

        for unit in ("file", "test", "case"):
            reports: list[Path] = []
            documents: list[dict[str, Any]] = []
            for index in range(3):
                output = root / f"{unit}-{index}"
                document = run(
                    q_executable, output,
                    ["-shard-unit", unit, "-shard-index", str(index), "-shard-count", "3"],
                )
                documents.append(document)
                reports.append(output / "test-results.json")
            identities = [set(verdict(document)) for document in documents]
            if any(identities[left] & identities[right] for left in range(3) for right in range(left + 1, 3)):
                raise RuntimeError(f"{unit}: shard results overlap")
            if set().union(*identities) != set(expected):
                raise RuntimeError(f"{unit}: shard union differs from baseline")
            result = merged(root, unit, reports)
            if verdict(result) != expected or result["summary"]["assertionCount"] != 18:
                raise RuntimeError(f"{unit}: merged verdict/assertions differ from baseline")
            if unit == "file" and not any(not document["tests"] for document in documents):
                raise RuntimeError("file topology did not exercise empty shards")

        isolated_reports: list[Path] = []
        for index in range(3):
            output = root / f"isolated-case-{index}"
            run(
                q_executable, output,
                ["-isolate", "-isolateTimeout", "30", "-shard-unit", "case",
                 "-shard-index", str(index), "-shard-count", "3"],
            )
            isolated_reports.append(output / "test-results.json")
        if verdict(merged(root, "isolated-case", isolated_reports)) != expected:
            raise RuntimeError("isolated case-shard merge differs from normal baseline")

        plugin_reports: list[Path] = []
        for index in range(2):
            output = root / f"plugin-{index}"
            run_strict_plugin_shard(q_executable, output, index, 2)
            plugin_reports.append(output / "test-results.json")
        plugin_merged, plugin_passed = merge(plugin_reports, root / "merged-plugin")
        validate(plugin_merged)
        plugin_rows = [row for row in plugin_merged["tests"] if row["kind"] == "plugin"]
        if plugin_passed or len(plugin_rows) != 1 or plugin_rows[0]["status"] != "error":
            raise RuntimeError("run-level strict plugin failures were not coalesced faithfully")

        full_report, full_coverage = run_coverage(q_executable, root / "coverage-full", [])
        coverage_reports: list[Path] = []
        for index in range(2):
            output = root / f"coverage-{index}"
            run_coverage(
                q_executable, output,
                ["-shard-unit", "test", "-shard-index", str(index), "-shard-count", "2"],
            )
            coverage_reports.append(output / "test-results.json")
        merged_coverage_report = merged(root, "coverage", coverage_reports)
        merged_coverage = json.loads((root / "merged-coverage/coverage.json").read_text(encoding="utf-8"))
        if verdict(merged_coverage_report) != verdict(full_report):
            raise RuntimeError("coverage shard verdict differs from unsharded coverage run")
        metric_keys = (
            "functionsFound", "functionsHit", "linesFound", "linesHit",
            "statementSitesFound", "statementSitesHit", "branchesFound", "branchesHit",
        )
        if {key: full_coverage["summary"][key] for key in metric_keys} != {
            key: merged_coverage["summary"][key] for key in metric_keys
        }:
            raise RuntimeError("merged aggregate coverage differs from unsharded coverage")
        if full_coverage["contextMeasurement"]["summary"] != merged_coverage["contextMeasurement"]["summary"]:
            raise RuntimeError("merged coverage contexts differ from unsharded attribution")

        fail_output = root / "fail-fast"
        fail_document = run(
            q_executable, fail_output, ["-fail-fast"], fixture=FAIL_FAST,
            expected_codes={1},
        )
        if len(fail_document["manifest"]["tests"]) != 2 or len(fail_document["tests"]) != 1:
            raise RuntimeError("fail-fast fixture did not preserve the omitted identity in its manifest")
        try:
            merge([fail_output / "test-results.json"], root / "must-not-merge")
        except MergeError as exc:
            if "incomplete result set" not in str(exc):
                raise RuntimeError(f"fail-fast rejection was not specific: {exc}") from exc
        else:
            raise RuntimeError("strict merger accepted a fail-fast-incomplete artifact")

        try:
            merge(
                [root / "case-0/test-results.json", root / "case-1/test-results.json"],
                root / "must-not-merge-missing-shard",
            )
        except MergeError as exc:
            if "incomplete shard union" not in str(exc):
                raise RuntimeError(f"missing-shard rejection was not specific: {exc}") from exc
        else:
            raise RuntimeError("strict merger accepted an incomplete shard union")

        try:
            merge(
                [root / "case-0/test-results.json", root / "case-0/test-results.json", root / "case-2/test-results.json"],
                root / "must-not-merge-duplicate-shard",
            )
        except MergeError as exc:
            if "duplicate shard index" not in str(exc):
                raise RuntimeError(f"duplicate-shard rejection was not specific: {exc}") from exc
        else:
            raise RuntimeError("strict merger accepted a duplicate shard index")

        # Mutation checks pin the fail-closed trust boundary without launching q.
        source = json.loads((root / "case-0/test-results.json").read_text(encoding="utf-8"))
        for label, mutate, expected_text in (
            ("revision", lambda d: d["manifest"]["revision"].update(sha="0" * 40), "mixed revision"),
            ("digest", lambda d: (
                d["manifest"].update(digest="manifest_" + "0" * 32),
                d["events"][1].update(entityId="manifest_" + "0" * 32),
                d["events"][1]["payload"].update(digest="manifest_" + "0" * 32),
            ), "mixed manifest digest"),
            ("labels", lambda d: d["run"].update(labels={"environment": "other"}), "mixed run labels"),
        ):
            tampered = root / f"tampered-{label}.json"
            document = copy.deepcopy(source)
            mutate(document)
            tampered.write_text(json.dumps(document), encoding="utf-8")
            paths = [tampered, root / "case-1/test-results.json", root / "case-2/test-results.json"]
            try:
                merge(paths, root / f"must-not-merge-{label}")
            except MergeError as exc:
                if expected_text not in str(exc):
                    raise RuntimeError(f"{label} rejection was not specific: {exc}") from exc
            else:
                raise RuntimeError(f"strict merger accepted mixed {label}")

        duplicate_row = copy.deepcopy(source["tests"][0])
        try:
            validate_results(
                [{"run": {"shard": {"index": 0}}, "tests": [duplicate_row, duplicate_row]}],
                [{duplicate_row["caseId"] or duplicate_row["testId"]}],
            )
        except MergeError as exc:
            if "duplicate result" not in str(exc):
                raise RuntimeError(f"duplicate-result rejection was not specific: {exc}") from exc
        else:
            raise RuntimeError("strict merger accepted a duplicate result identity")

        first = copy.deepcopy(source["tests"][0])
        second = copy.deepcopy(source["tests"][-1])
        first["snapshots"] = [{"backend": "text", "path": "shared.snap"}]
        second["snapshots"] = [{"backend": "text", "path": "shared.snap"}]
        try:
            validate_snapshot_ownership([first, second])
        except MergeError as exc:
            if "multiple executions" not in str(exc):
                raise RuntimeError(f"snapshot-conflict rejection was not specific: {exc}") from exc
        else:
            raise RuntimeError("strict merger accepted conflicting snapshot ownership")

        try:
            merge_performance([
                {"performance": [{"benchmarkId": "benchmark_" + "a" * 32, "suite": "bench", "description": "same"}]},
                {"performance": [{"benchmarkId": "benchmark_" + "a" * 32, "suite": "bench", "description": "same"}]},
            ])
        except MergeError as exc:
            if "more than one shard" not in str(exc):
                raise RuntimeError(f"benchmark-conflict rejection was not specific: {exc}") from exc
        else:
            raise RuntimeError("strict merger accepted duplicate benchmark ownership")

    print(
        "resQ shard merge verification passed: file/test/case parity, empty shards, "
        "declarative fixtures, retry telemetry, isolation, aggregate/context coverage, "
        "atomic dynamic cases, run-level plugin coalescing, "
        "fail-fast omission, missing/duplicate shards/results, revision/manifest tampering, "
        "and snapshot/benchmark ownership conflicts"
    )


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable")
    args = parser.parse_args()
    try:
        verify(args.q)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, RuntimeError, MergeError, ValueError) as exc:
        print(f"shard merge verification failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
