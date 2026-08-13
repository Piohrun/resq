#!/usr/bin/env python3
"""End-to-end proof of resQ's evidence, quarantine, expiry, and telemetry policy."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from validate_report import validate


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/flake_controlled.q"
UPDATER = ROOT / "tools/update_quarantine.py"


def run(
    q_executable: str,
    root: Path,
    name: str,
    *,
    passing: bool,
    extra: list[str] | None = None,
    reporters: bool = False,
) -> tuple[subprocess.CompletedProcess[str], dict[str, Any], Path]:
    out = root / name
    command = [
        str(ROOT / "bin/resq"), "test", str(FIXTURE), "-strict",
        "-json", "-outDir", str(out),
        "-state-file", str(root / "last-run.json"),
        "-flake-history", str(root / "history.json"),
        "-quarantine-file", str(root / "quarantine.json"),
        "-flake-proposal-file", str(root / "proposals.json"),
        "-flake-evidence-min", "3", "-flake-failure-min", "2", "-flake-window", "8",
    ]
    if reporters:
        command.extend(["-junit", "-xunit"])
    command.extend(extra or [])
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    environment["RESQ_FLAKE_PASS"] = "1" if passing else "0"
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
        timeout=60,
    )
    report_path = out / "test-results.json"
    if not report_path.exists():
        raise RuntimeError(
            f"{name}: report missing (exit {completed.returncode})\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report = json.loads(report_path.read_text(encoding="utf-8"))
    validate(report)
    return completed, report, out


def state(report: dict[str, Any]) -> dict[str, Any]:
    tests = report["tests"]
    if len(tests) != 1:
        raise AssertionError(f"expected one result, got {len(tests)}")
    return tests[0]["quarantine"]


def expect_code(completed: subprocess.CompletedProcess[str], expected: int, name: str) -> None:
    if completed.returncode != expected:
        raise AssertionError(
            f"{name}: expected exit {expected}, got {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )


def xml_properties(path: Path, element: str) -> dict[str, str]:
    root = ET.parse(path).getroot()
    return {
        node.attrib["name"]: node.attrib.get("value", "")
        for node in root.iter(element)
        if "name" in node.attrib
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="resq-quarantine-") as temp:
        work = Path(temp)

        first, first_report, _ = run(args.q, work, "01-first-failure", passing=False)
        expect_code(first, 1, "first failure")
        if state(first_report)["state"] != "insufficient":
            raise AssertionError("a first failure must never become suspect or quarantined")

        second, second_report, _ = run(args.q, work, "02-pass", passing=True)
        expect_code(second, 0, "second pass")
        if state(second_report)["state"] != "insufficient":
            raise AssertionError("two observations are still below configured evidence")

        third, third_report, _ = run(
            args.q, work, "03-suspect", passing=False, extra=["-flake-proposals"]
        )
        expect_code(third, 1, "suspect run")
        suspect = state(third_report)
        if suspect["state"] != "suspect" or suspect["failures"] != 2 or suspect["passes"] != 1:
            raise AssertionError(f"expected 2/1 suspect evidence, got {suspect!r}")
        proposal_path = work / "proposals.json"
        proposals = json.loads(proposal_path.read_text(encoding="utf-8"))
        if len(proposals.get("proposals", [])) != 1:
            raise AssertionError("suspect run must emit exactly one read-only proposal")
        manifest_path = work / "quarantine.json"
        if manifest_path.exists():
            raise AssertionError("proposal generation must never create or mutate the manifest")

        update_base = [
            str(UPDATER), "--proposals", str(proposal_path), "--manifest", str(manifest_path),
            "--owner", "quality-team", "--reason", "intermittent external dependency",
            "--issue", "Q-123", "--expires", "2099-12-31",
        ]
        preview = subprocess.run(update_base, text=True, capture_output=True, check=False, timeout=20)
        if preview.returncode != 0 or manifest_path.exists() or "DRY RUN" not in preview.stderr:
            raise AssertionError("manifest updater must be read-only unless --write is explicit")
        written = subprocess.run([*update_base, "--write"], text=True, capture_output=True, check=False, timeout=20)
        if written.returncode != 0 or not manifest_path.exists():
            raise AssertionError(f"explicit manifest update failed: {written.stderr}")

        blocking, blocking_report, _ = run(args.q, work, "04-blocking", passing=False)
        expect_code(blocking, 1, "active quarantine without opt-in")
        blocking_state = state(blocking_report)
        if blocking_state["state"] != "quarantined" or blocking_state["nonBlocking"]:
            raise AssertionError("active quarantine must remain blocking by default")
        if blocking_report["tests"][0]["status"] != "fail":
            raise AssertionError("quarantine must not rewrite the underlying result")

        nonblocking, report, report_dir = run(
            args.q,
            work,
            "05-nonblocking",
            passing=False,
            extra=["-quarantine-non-blocking"],
            reporters=True,
        )
        expect_code(nonblocking, 0, "explicit non-blocking quarantine")
        qstate = state(report)
        if qstate["state"] != "quarantined" or not qstate["nonBlocking"]:
            raise AssertionError("non-blocking opt-in was not represented on the raw failing row")
        if report["tests"][0]["status"] != "fail" or report["summary"]["failCount"] != 1:
            raise AssertionError("non-blocking policy must retain raw failure counts")
        if "Run passed with quarantined failures" not in nonblocking.stdout + nonblocking.stderr:
            raise AssertionError("console did not explain the non-blocking verdict")
        finished = [event for event in report["events"] if event["type"] == "test.finished"]
        if len(finished) != 1 or finished[0]["payload"].get("quarantine", {}).get("state") != "quarantined":
            raise AssertionError("test.finished event omitted quarantine state")
        junit = xml_properties(report_dir / "test-results.junit.xml", "property")
        xunit = xml_properties(report_dir / "test-results.xunit.xml", "trait")
        for props, label in ((junit, "JUnit"), (xunit, "xUnit")):
            if props.get("resq.quarantine.state") != "quarantined":
                raise AssertionError(f"{label} omitted quarantine state")
            if props.get("resq.quarantine.owner") != "quality-team":
                raise AssertionError(f"{label} omitted quarantine ownership")

        history_before = json.loads((work / "history.json").read_text(encoding="utf-8"))
        observations_before = len(history_before["tests"][0]["observations"])
        isolated, isolated_report, _ = run(
            args.q,
            work,
            "06-isolated-nonblocking",
            passing=False,
            extra=["-isolate", "-isolateWorkers", "2", "-quarantine-non-blocking"],
        )
        expect_code(isolated, 0, "isolated non-blocking quarantine")
        isolated_state = state(isolated_report)
        if isolated_state["state"] != "quarantined" or not isolated_state["nonBlocking"]:
            raise AssertionError("isolate parent did not apply the same quarantine policy")
        if isolated_report["tests"][0]["status"] != "fail":
            raise AssertionError("isolate mode rewrote the underlying quarantined failure")
        history_after = json.loads((work / "history.json").read_text(encoding="utf-8"))
        observations_after = len(history_after["tests"][0]["observations"])
        if observations_after != observations_before + 1:
            raise AssertionError(
                "isolate parent must append exactly one merged observation; "
                f"got {observations_before} -> {observations_after}"
            )

        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["entries"][0]["expiresAt"] = "2000-01-01"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        expired, expired_report, _ = run(
            args.q, work, "07-expired", passing=False, extra=["-quarantine-non-blocking"]
        )
        expect_code(expired, 1, "expired quarantine")
        expired_state = state(expired_report)
        if expired_state["state"] != "expired" or expired_state["nonBlocking"]:
            raise AssertionError("expiry must restore the failure to blocking")

        manifest_path.write_text("{not-json", encoding="utf-8")
        malformed, malformed_report, _ = run(
            args.q, work, "08-malformed", passing=False, extra=["-quarantine-non-blocking"]
        )
        expect_code(malformed, 1, "malformed manifest")
        if malformed_report["flake"]["manifestStatus"] != "invalid":
            raise AssertionError("malformed manifest was not surfaced in telemetry")
        if state(malformed_report)["nonBlocking"]:
            raise AssertionError("malformed manifest must fail closed")

    print(
        "resQ quarantine verification passed: evidence threshold, read-only proposals, "
        "explicit updates, raw results, opt-in non-blocking policy, expiry, malformed fail-closed, "
        "normal/isolate parity, single-writer history, console/JSON/events/JUnit/xUnit telemetry"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
