#!/usr/bin/env python3
"""Run resQ under an independent KX Developer .cov provider."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from self_coverage_trend import update_file  # noqa: E402
from process_control import run_bounded  # noqa: E402


def default_library() -> str:
    home = os.environ.get("AXLIBRARIES_HOME", "")
    return str(Path(home) / "ws" / "coverage.q_") if home else ""


def validate_artifact(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1 or document.get("kind") != "resq-self-coverage":
        raise RuntimeError("unexpected self-coverage schema/kind")
    measurement = document.get("measurement", {})
    if measurement.get("provider") != "KX Developer .cov":
        raise RuntimeError("self-coverage provider identity is missing")
    if measurement.get("complete") is not False or measurement.get("gatingSupported") is not False:
        raise RuntimeError("self-coverage must be explicitly partial and non-gating")
    required = {
        "functionsMeasured", "functionsHit", "logicalLinesMeasured",
        "logicalLinesHit", "blocksMeasured", "blocksHit",
    }
    if set(document.get("summary", {})) != required:
        raise RuntimeError("self-coverage summary contract drifted")
    if not isinstance(document.get("rawResults"), list):
        raise RuntimeError("self-coverage rawResults must be a row list")
    return document


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", default=default_library(), help="path to AxLibraries ws/coverage.q_")
    parser.add_argument("--output", default="artifacts/self-coverage", help="artifact directory")
    parser.add_argument(
        "--trend-limit", type=int, default=100,
        help="maximum experimental trend points retained (default: 100)",
    )
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"), help="q executable")
    parser.add_argument(
        "--timeout-seconds", type=float, default=1200,
        help="kill the complete q process group after this deadline (default: 1200)",
    )
    parser.add_argument("resq_args", nargs=argparse.REMAINDER, help="arguments after -- (default: test tests -strict -quiet)")
    args = parser.parse_args()

    library = Path(args.library).expanduser() if args.library else None
    if library is None or not library.is_file():
        print("self-coverage requires KX Developer AxLibraries ws/coverage.q_", file=sys.stderr)
        return 2
    resq_args = list(args.resq_args)
    if resq_args[:1] == ["--"]:
        resq_args = resq_args[1:]
    if not resq_args:
        resq_args = ["test", "tests", "-strict", "-quiet"]
    if resq_args[0] != "test":
        print("self-coverage supports test mode only", file=sys.stderr)
        return 2
    if "-isolate" in resq_args:
        print("self-coverage cannot observe isolated child processes", file=sys.stderr)
        return 2

    if args.timeout_seconds <= 0:
        print("self-coverage timeout must be positive", file=sys.stderr)
        return 2
    output = Path(args.output).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".self-coverage-run-", dir=output) as raw:
        staging = Path(raw)
        environment = dict(os.environ)
        environment.update(
            QBIN=args.q,
            RESQ_SELF_COVERAGE_LIBRARY=str(library.resolve()),
            RESQ_SELF_COVERAGE_OUTPUT=str(staging),
        )
        try:
            completed = run_bounded(
                [str(ROOT / "bin" / "resq"), *resq_args], cwd=ROOT,
                env=environment, timeout=args.timeout_seconds,
                stdin=subprocess.DEVNULL,
            )
        except subprocess.TimeoutExpired:
            print(
                f"self-coverage q process timed out after {args.timeout_seconds:g}s",
                file=sys.stderr,
            )
            return 124
        staged_artifact = staging / "self-coverage.json"
        staged_text = staging / "self-coverage.txt"
        if not staged_artifact.is_file() or not staged_text.is_file():
            print(
                "self-coverage provider did not produce both JSON and text evidence",
                file=sys.stderr,
            )
            return completed.returncode or 1
        try:
            document = validate_artifact(staged_artifact)
        except (OSError, json.JSONDecodeError, RuntimeError) as exc:
            print(f"invalid self-coverage artifact: {exc}", file=sys.stderr)
            return completed.returncode or 1
        artifact = output / "self-coverage.json"
        os.replace(staged_artifact, artifact)
        os.replace(staged_text, output / "self-coverage.txt")
        summary = document["summary"]
        try:
            trend = update_file(output / "self-coverage-trend.json", document, args.trend_limit)
        except (OSError, json.JSONDecodeError, RuntimeError) as exc:
            print(f"invalid self-coverage trend: {exc}", file=sys.stderr)
            return completed.returncode or 1
    print(
        "self-coverage evidence: "
        f"{summary['functionsHit']}/{summary['functionsMeasured']} loaded functions, "
        f"{summary['logicalLinesHit']}/{summary['logicalLinesMeasured']} logical lines, "
        f"{summary['blocksHit']}/{summary['blocksMeasured']} blocks (partial; non-gating)"
    )
    print(
        f"self-coverage trend: {len(trend['points'])} bounded point(s) "
        "(experimental; non-gating)"
    )
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
