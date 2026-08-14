#!/usr/bin/env python3
"""Run independent licence-free validator, merger, NDJSON, and Allure suites."""

from __future__ import annotations

import argparse
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


SUITES = {
    "validator": [
        "tools.tests.test_adapters.ValidatorContractTests",
        "tools.tests.test_report_invariants",
        "tools.tests.test_coverage_contract",
        "tools.tests.test_coverage_reconciliation",
        "tools.tests.test_self_coverage_trend",
    ],
    "merger": ["tools.tests.test_merge_shards"],
    "ndjson": ["tools.tests.test_adapters.NdjsonAdapterTests"],
    "allure": ["tools.tests.test_adapters.AllureAdapterTests"],
    "supporting": [
        "tools.tests.test_formatter_boundaries",
        "tools.tests.test_ingestion",
        "tools.tests.test_identity_migration",
        "tools.tests.test_coverage_performance",
        "tools.tests.test_review_corpus",
        "tools.tests.test_report_scale",
        "tools.tests.test_release_gate",
        "tools.tests.test_documentation_scope",
    ],
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--suite", action="append", choices=tuple(SUITES),
        help="suite to run; repeat as needed (default: every suite)",
    )
    args = parser.parse_args()
    selected = args.suite or list(SUITES)
    loader = unittest.TestLoader()
    passed = True
    for name in selected:
        print(f"[python-contracts] {name}", flush=True)
        result = unittest.TextTestRunner(verbosity=2).run(
            loader.loadTestsFromNames(SUITES[name])
        )
        passed = passed and result.wasSuccessful()
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
