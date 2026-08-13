#!/usr/bin/env python3
"""Verify public property generators, shrinking, replay, and report telemetry."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


def verify(q_executable: str) -> None:
    with tempfile.TemporaryDirectory(prefix="resq-property-") as directory:
        output = Path(directory) / "report"
        state = Path(directory) / "state.json"
        environment = dict(os.environ)
        environment["QBIN"] = q_executable
        command = [
            str(ROOT / "bin/resq"), "test",
            str(ROOT / "tests/fixtures/property_protocol.q"),
            "-strict", "-json", "-junit", "-xunit", "-outDir", str(output),
            "-state-file", str(state),
        ]
        completed = subprocess.run(
            command, cwd=ROOT, env=environment, text=True,
            stdin=subprocess.DEVNULL, capture_output=True, check=False, timeout=120,
        )
        if completed.returncode != 1:
            raise RuntimeError(
                f"expected property fixture to fail with exit 1, got {completed.returncode}\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
        console = completed.stdout + completed.stderr
        for marker in (
            "Replay: resq-pbt-v1/424242/0",
            "Original failing input:",
            "Minimal reproducible input:",
            "Shrink:",
        ):
            if marker not in console:
                raise RuntimeError(f"console property telemetry missing {marker!r}")

        document = json.loads((output / "test-results.json").read_text(encoding="utf-8"))
        validate(document)
        if len(document["tests"]) != 1 or document["tests"][0]["status"] != "fail":
            raise RuntimeError("property fixture did not produce one failing row")
        prop = document["tests"][0]["property"]
        expected = {
            "generatorProtocol": "resq-generator-v1",
            "replayToken": "resq-pbt-v1/424242/0",
            "runs": 1,
            "failCount": 1,
            "passCount": 0,
            "shrinkTermination": "minimal",
        }
        for field, value in expected.items():
            if prop[field] != value:
                raise RuntimeError(f"property.{field}: expected {value!r}, got {prop[field]!r}")
        if prop["replayTokens"] != [prop["replayToken"]]:
            raise RuntimeError("per-failure replay tokens are incomplete")
        if prop["originalInput"] != prop["failedInputs"][0]:
            raise RuntimeError("original failing input differs from the first failed input")
        if prop["minimalInput"] != prop["shrunkInput"]:
            raise RuntimeError("minimalInput and legacy shrunkInput disagree")
        if len(prop["minimalInput"]) != 2:
            raise RuntimeError("collection shrinker did not respect its minimum length")
        if prop["shrinkSteps"] <= 0 or prop["shrinkCandidates"] < prop["shrinkSteps"]:
            raise RuntimeError("shrink work counters are not credible")
        if not prop["failureSignature"].startswith("fuzz-failure-v1/"):
            raise RuntimeError("failure signature is missing or unstable")

        junit_root = ElementTree.parse(output / "test-results.junit.xml").getroot()
        junit_props = {
            node.attrib["name"]: node.attrib["value"]
            for node in junit_root.findall(".//testcase/properties/property")
        }
        xunit_root = ElementTree.parse(output / "test-results.xunit.xml").getroot()
        xunit_traits = {
            node.attrib["name"]: node.attrib["value"]
            for node in xunit_root.findall(".//test/traits/trait")
        }
        for emitted in (junit_props, xunit_traits):
            if emitted.get("resq.property.replayToken") != prop["replayToken"]:
                raise RuntimeError("XML property replay token disagrees with JSON")
            if emitted.get("resq.property.shrinkTermination") != prop["shrinkTermination"]:
                raise RuntimeError("XML shrink termination disagrees with JSON")
            if "resq.property.originalInput" not in emitted or "resq.property.minimalInput" not in emitted:
                raise RuntimeError("XML reporter omitted original/minimal property inputs")

    print("resQ property protocol verification passed: deterministic generators, replay, bounded type-aware shrinking, console/JSON/JUnit/xUnit telemetry")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable (default: q)")
    args = parser.parse_args()
    try:
        verify(args.q)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"property protocol verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
