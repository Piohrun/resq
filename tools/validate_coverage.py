#!/usr/bin/env python3
"""Validate a detailed resQ coverage-v2 artifact and optional parent report."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from coverage_contract import validate_coverage_artifact
from validate_report import validate


def load(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coverage", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        artifact = load(args.coverage)
        report = load(args.report) if args.report else None
        if report is not None:
            validate(report)
        validate_coverage_artifact(artifact, report)
    except (OSError, json.JSONDecodeError, ValueError, KeyError) as error:
        print(f"invalid resQ coverage: {error}", file=sys.stderr)
        return 1
    print(f"valid resQ coverage v2: {args.coverage}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
