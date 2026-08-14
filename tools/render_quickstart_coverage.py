#!/usr/bin/env python3
"""Render or verify the checked quickstart coverage block in the audit."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "tests/contracts/quickstart-coverage.json"
DOCUMENT = ROOT / "docs/PRODUCTION_AUDIT_1_8.md"
START = "<!-- QUICKSTART_COVERAGE_START -->"
END = "<!-- QUICKSTART_COVERAGE_END -->"


def load_contract() -> dict[str, object]:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("schemaVersion") != 1 or contract.get("kind") != "resq-quickstart-coverage":
        raise ValueError("quickstart coverage contract identity is invalid")
    counts = contract.get("counts")
    completeness = contract.get("completeness")
    if not isinstance(counts, dict) or not isinstance(completeness, dict):
        raise ValueError("quickstart coverage contract lacks counts/completeness")
    required_counts = {
        "functionsFound", "functionsHit", "linesFound", "linesHit",
        "statementSitesFound", "statementSitesHit", "branchesFound", "branchesHit",
    }
    required_completeness = {
        "statementFunctionsFound", "statementFunctionsInstrumented",
        "branchSitesFound", "branchSitesInstrumented",
    }
    if set(counts) != required_counts or set(completeness) != required_completeness:
        raise ValueError("quickstart coverage contract fields are incomplete")
    values = [*counts.values(), *completeness.values()]
    if any(not isinstance(value, int) or value < 0 for value in values):
        raise ValueError("quickstart coverage values must be non-negative integers")
    for found, hit in (
        ("functionsFound", "functionsHit"), ("linesFound", "linesHit"),
        ("statementSitesFound", "statementSitesHit"), ("branchesFound", "branchesHit"),
    ):
        if counts[hit] > counts[found]:
            raise ValueError(f"quickstart coverage {hit} exceeds {found}")
    return contract


def render(contract: dict[str, object]) -> str:
    counts = contract["counts"]
    complete = contract["completeness"]
    assert isinstance(counts, dict) and isinstance(complete, dict)
    return "\n".join(
        (
            START,
            "| Contract | Evidence |",
            "|---|---:|",
            f"| Function coverage (gate basis) | {counts['functionsHit']} / {counts['functionsFound']} |",
            f"| Measured source lines | {counts['linesHit']} / {counts['linesFound']} |",
            f"| Statement sites | {counts['statementSitesHit']} / {counts['statementSitesFound']} |",
            f"| Statement instrumentation completeness | {complete['statementFunctionsInstrumented']} / {complete['statementFunctionsFound']} eligible functions |",
            f"| Conditional edges | {counts['branchesHit']} / {counts['branchesFound']} |",
            f"| Branch instrumentation completeness | {complete['branchSitesInstrumented']} / {complete['branchSitesFound']} eligible sites |",
            END,
        )
    )


def replace_block(document: str, block: str) -> str:
    if document.count(START) != 1 or document.count(END) != 1:
        raise ValueError("production audit must contain exactly one quickstart coverage block")
    before, remainder = document.split(START, 1)
    _, after = remainder.split(END, 1)
    return before + block + after


def check_document() -> None:
    expected = render(load_contract())
    actual = DOCUMENT.read_text(encoding="utf-8")
    if replace_block(actual, expected) != actual:
        raise ValueError("production audit quickstart coverage block is stale; run tools/render_quickstart_coverage.py --write")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="rewrite the marked audit block")
    args = parser.parse_args()
    expected = render(load_contract())
    if args.write:
        DOCUMENT.write_text(
            replace_block(DOCUMENT.read_text(encoding="utf-8"), expected),
            encoding="utf-8",
        )
        print(f"updated {DOCUMENT.relative_to(ROOT)}")
    else:
        check_document()
        print("quickstart coverage documentation matches its checked contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
