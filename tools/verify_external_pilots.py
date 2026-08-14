#!/usr/bin/env python3
"""Verify pinned external q-codebase adoption pilots offline."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "pilots/manifest.json"
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_vendor(pilot: dict[str, Any]) -> Path:
    root = (ROOT / pilot["root"]).resolve()
    try:
        root.relative_to(ROOT / "pilots/vendor")
    except ValueError as exc:
        raise RuntimeError(f"{pilot['name']}: vendor root escapes pilot tree") from exc
    if pilot.get("license") != "MIT" or not (root / "LICENSE").is_file():
        raise RuntimeError(f"{pilot['name']}: missing declared MIT licence")
    commit = pilot.get("commit", "")
    if len(commit) != 40 or any(char not in "0123456789abcdef" for char in commit):
        raise RuntimeError(f"{pilot['name']}: commit is not a pinned SHA")
    for relative, hashes in pilot["upstreamFiles"].items():
        path = root / relative
        if not path.is_file():
            raise RuntimeError(f"{pilot['name']}: missing vendored file {relative}")
        actual = sha256(path)
        if actual != hashes["vendoredSha256"]:
            raise RuntimeError(
                f"{pilot['name']}: vendored hash drift for {relative}: {actual}"
            )
    return root


def run_mode(
    pilot: dict[str, Any], root: Path, output_root: Path,
    q_executable: str, mode: str, flags: list[str],
) -> dict[str, Any]:
    output = output_root / pilot["name"] / mode
    state = output_root / "state" / f"{pilot['name']}-{mode}.json"
    command = [
        str(ROOT / "bin/resq"), "test", pilot["testFile"],
        "-strict", "-json", "-quiet", "-outDir", str(output),
        "-state-file", str(state),
        "-flake-history", str(output_root / "state" / f"{pilot['name']}-{mode}-flake.json"),
        "-quarantine-file", str(output_root / "state" / f"{pilot['name']}-{mode}-quarantine.json"),
        "-flake-proposal-file", str(output_root / "state" / f"{pilot['name']}-{mode}-proposals.json"),
        *flags,
    ]
    environment = dict(os.environ)
    environment["QBIN"] = q_executable
    completed = subprocess.run(
        command, cwd=root, env=environment, text=True, capture_output=True,
        stdin=subprocess.DEVNULL, check=False, timeout=120,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"{pilot['name']} {mode} exited {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report_path = output / "test-results.json"
    document = json.loads(report_path.read_text(encoding="utf-8"))
    validate(document)
    summary = document["summary"]
    expected = (pilot["expectedTests"], pilot["expectedAssertions"])
    actual = (summary["testCount"], summary["assertionCount"])
    if actual != expected or summary["passCount"] != pilot["expectedTests"]:
        raise RuntimeError(
            f"{pilot['name']} {mode}: expected tests/assertions {expected}, got {actual}"
        )
    return document


def verdict(document: dict[str, Any]) -> dict[str, str]:
    pairs = [((row.get("caseId") or row["testId"]), row["status"])
             for row in document["tests"]]
    if len(pairs) != len({identity for identity, _ in pairs}):
        raise RuntimeError("external pilot report contains duplicate execution identities")
    return dict(pairs)


def verify(q_executable: str) -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    pilots = manifest.get("pilots", [])
    if manifest.get("schemaVersion") != 1 or len(pilots) < 2:
        raise RuntimeError("pilot manifest must contain at least two schema-v1 pilots")
    names = [pilot["name"] for pilot in pilots]
    if len(names) != len(set(names)):
        raise RuntimeError("pilot names must be unique")

    with tempfile.TemporaryDirectory(prefix="resq-external-pilots-") as directory:
        output_root = Path(directory)
        total_tests = 0
        total_assertions = 0
        for pilot in pilots:
            root = verify_vendor(pilot)
            normal = run_mode(pilot, root, output_root, q_executable, "normal", [])
            isolated = run_mode(
                pilot, root, output_root, q_executable, "isolated",
                ["-isolate", "-isolateTimeout", "30"],
            )
            if verdict(normal) != verdict(isolated):
                raise RuntimeError(f"{pilot['name']}: isolated verdict differs from normal")
            total_tests += pilot["expectedTests"]
            total_assertions += pilot["expectedAssertions"]
    print(
        f"external adoption pilots passed: {len(pilots)} codebases, "
        f"{total_tests} tests, {total_assertions} assertions, normal/isolate parity"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable (default: q)")
    args = parser.parse_args()
    try:
        verify(args.q)
    except (
        OSError, subprocess.SubprocessError, json.JSONDecodeError,
        KeyError, TypeError, ValueError, RuntimeError,
    ) as exc:
        print(f"external adoption pilots failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
