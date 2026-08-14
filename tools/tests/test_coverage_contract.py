from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from coverage_contract import validate_coverage_artifact, validate_report_coverage  # noqa: E402
from review_corpus import scale_report  # noqa: E402


def summary() -> dict[str, object]:
    return {
        "linesFound": 1, "linesHit": 1, "linePercent": 100.0,
        "functionsFound": 1, "functionsHit": 1, "functionPercent": 100.0,
        "statementSitesFound": 1, "statementSitesHit": 1,
        "statementSitePercent": 100.0, "statementSitesInstrumented": 1,
        "statementSiteInstrumentationPercent": 100.0,
        "statementSiteInstrumentationComplete": True,
        "branchesFound": 2, "branchesHit": 1, "branchPercent": 50.0,
        "branchMode": True, "branchSitesEligible": 1,
        "branchSitesInstrumented": 1, "branchInstrumentationPercent": 100.0,
        "branchInstrumentationComplete": True,
        "filesFound": 1, "filesLoaded": 1, "filesWithStatements": 1,
        "functionsEligible": 1, "functionsInstrumented": 1,
        "functionInstrumentationPercent": 100.0,
        "statementMode": True, "statementFunctionsEligible": 1,
        "statementFunctionsInstrumented": 1,
        "statementInstrumentationPercent": 100.0,
        "statementInstrumentationComplete": True,
        "fallbackCounts": {},
    }


def report_coverage() -> dict[str, object]:
    value = {
        "schemaVersion": 2,
        "enabled": True,
        "detailArtifact": "coverage.json",
        **summary(),
        "gates": {},
        "allowPartialLines": False,
        "partialLines": False,
        "partialBranches": False,
        "basis": "functions",
        "minimum": 0,
        "passed": True,
    }
    definitions = {
        "functions": ("functions", 1, 1, 100.0),
        "lines": ("measured_lines", 1, 1, 100.0),
        "completeness": ("statement_instrumentation", 1, 1, 100.0),
        "branches": ("branches", 1, 2, 50.0),
        "branchCompleteness": ("branch_instrumentation", 1, 1, 100.0),
    }
    for name, (basis, hit, found, percentage) in definitions.items():
        value["gates"][name] = {
            "measurable": True, "basis": basis, "percent": percentage,
            "hit": hit, "found": found, "minimum": 0, "passed": True,
        }
    return value


def artifact(test_id: str, run_id: str = "run_" + "a" * 32) -> dict[str, object]:
    statement_site = {
        "siteId": "statement_" + "1" * 32,
        "function": ".fixture.f", "line": 2, "column": 2,
        "lambdaId": "", "lambdaDepth": 0, "anonymous": False,
        "eligible": True, "instrumented": True, "fallbackReason": "none",
        "hits": 1, "covered": True,
    }
    branch_site = {
        "siteId": "branch_" + "2" * 32,
        "function": ".fixture.f", "kind": "if", "conditionIndex": 0,
        "line": 3, "column": 2, "lambdaId": "", "lambdaDepth": 0,
        "anonymous": False, "block": 0, "eligible": True,
        "instrumented": True, "fallbackReason": "none",
        "edgesFound": 2, "edgesHit": 1,
        "edges": [
            {"edgeId": "edge_" + "3" * 32, "index": 0, "label": "true", "hits": 1, "covered": True},
            {"edgeId": "edge_" + "4" * 32, "index": 1, "label": "false", "hits": 0, "covered": False},
        ],
    }
    function = {
        "name": ".fixture.f", "line": 1, "hits": 1, "covered": True,
        "functionEligible": True, "functionInstrumented": True,
        "statementEligible": True, "statementInstrumented": True,
        "fallbackReason": "none", "statementFound": 1, "statementHit": 1,
        "statements": [{"line": 2, "hits": 1, "covered": True}],
        "statementSitesFound": 1, "statementSitesHit": 1,
        "statementSitesInstrumented": 1, "statementSites": [copy.deepcopy(statement_site)],
        "branchSitesEligible": 1, "branchSitesInstrumented": 1,
        "branchFound": 2, "branchHit": 1, "branches": [copy.deepcopy(branch_site)],
    }
    path = "src/fixture.q"
    context_id = test_id
    metrics = [
        {"contextId": context_id, "metricId": "metric_function", "kind": "function", "file": path, "function": ".fixture.f", "siteId": "", "edgeIndex": -1, "edgeLabel": "", "hits": 1},
        {"contextId": context_id, "metricId": "metric_statement", "kind": "statement", "file": path, "function": ".fixture.f", "siteId": statement_site["siteId"], "edgeIndex": -1, "edgeLabel": "", "hits": 1},
        {"contextId": context_id, "metricId": "metric_branch", "kind": "branch", "file": path, "function": ".fixture.f", "siteId": branch_site["siteId"], "edgeIndex": 0, "edgeLabel": "true", "hits": 1},
    ]
    return {
        "schemaVersion": 2, "kind": "resq-coverage", "framework": "resQ",
        "frameworkVersion": "1.8.1", "runId": run_id, "summary": summary(),
        "files": [{
            "path": path, "loaded": True, "functionFound": 1, "functionHit": 1,
            "statementFunctionsInstrumented": 1, "lineFound": 1, "lineHit": 1,
            "statementSitesEligible": 1, "statementSitesInstrumented": 1,
            "statementSitesHit": 1, "branchSitesEligible": 1,
            "branchSitesInstrumented": 1, "branchFound": 2, "branchHit": 1,
            "functions": [function], "lines": [{"line": 2, "hits": 1, "covered": True}],
            "statementSites": [statement_site], "branches": [branch_site],
        }],
        "contextMeasurement": {
            "schemaVersion": 1, "enabled": True, "detail": "test",
            "contextLimit": 100, "entryLimit": 1000,
            "summary": {
                "contextsStored": 1, "metricEntriesStored": 3,
                "functionHits": 1, "statementHits": 1, "branchHits": 1,
                "unattributedHits": 0, "overflowActivations": 0,
                "droppedMetricHits": 0, "truncated": False,
            },
            "contexts": [{
                "contextId": context_id, "kind": "test", "testId": test_id,
                "attempt": 0, "suite": "fixture", "description": "covers",
                "file": "tests/test_fixture.q", "metrics": metrics,
            }],
        },
    }


class CoverageContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.report = scale_report(1)
        self.report["coverage"] = report_coverage()
        self.artifact = artifact(
            self.report["tests"][0]["testId"], self.report["run"]["id"]
        )

    def test_rejects_absent_or_mismatched_run_identity(self) -> None:
        missing = copy.deepcopy(self.artifact)
        del missing["runId"]
        with self.assertRaisesRegex(ValueError, "runId"):
            validate_coverage_artifact(missing, self.report)

        mismatched = copy.deepcopy(self.artifact)
        mismatched["runId"] = "run_" + "f" * 32
        with self.assertRaisesRegex(ValueError, "differs from report"):
            validate_coverage_artifact(mismatched, self.report)

    def test_accepts_exact_report_and_detailed_coverage(self) -> None:
        validate_report_coverage(self.report["coverage"])
        validate_coverage_artifact(self.artifact, self.report)

    def test_source_parse_completeness_is_structured_and_fail_closed(self) -> None:
        complete = copy.deepcopy(self.artifact)
        complete["summary"].update(
            sourceParseComplete=True, sourceParseDiagnostics=[]
        )
        validate_coverage_artifact(complete)

        incomplete = copy.deepcopy(self.artifact)
        incomplete["summary"].update(
            sourceParseComplete=False,
            sourceParseDiagnostics=[{
                "file": "src/fixture.q",
                "function": ".fixture.f",
                "phase": "statement_inventory",
                "message": "source masking failed",
            }],
        )
        validate_coverage_artifact(incomplete)

        invalid = copy.deepcopy(incomplete)
        invalid["summary"]["sourceParseComplete"] = True
        with self.assertRaisesRegex(ValueError, "disagrees"):
            validate_coverage_artifact(invalid)

    def test_rejects_percentage_and_aggregate_drift(self) -> None:
        bad = copy.deepcopy(self.artifact)
        bad["summary"]["functionPercent"] = 99.0
        with self.assertRaisesRegex(ValueError, "functionPercent"):
            validate_coverage_artifact(bad)

        bad = copy.deepcopy(self.artifact)
        bad["summary"]["functionsHit"] = 0
        with self.assertRaisesRegex(ValueError, "functionPercent|functionsHit"):
            validate_coverage_artifact(bad)

        bad_report = copy.deepcopy(self.report["coverage"])
        bad_report["passed"] = False
        with self.assertRaisesRegex(ValueError, "independent gates"):
            validate_report_coverage(bad_report)

    def test_rejects_impossible_hits_and_broken_site_joins(self) -> None:
        impossible = copy.deepcopy(self.artifact)
        impossible["files"][0]["statementSites"][0]["covered"] = False
        with self.assertRaisesRegex(ValueError, "covered"):
            validate_coverage_artifact(impossible)

        broken = copy.deepcopy(self.artifact)
        broken["contextMeasurement"]["contexts"][0]["metrics"][1]["siteId"] = "statement_" + "9" * 32
        with self.assertRaisesRegex(ValueError, "unknown site"):
            validate_coverage_artifact(broken)

    def test_rejects_context_and_parent_report_drift(self) -> None:
        bad_context = copy.deepcopy(self.artifact)
        bad_context["contextMeasurement"]["summary"]["statementHits"] = 2
        with self.assertRaisesRegex(ValueError, "statementHits"):
            validate_coverage_artifact(bad_context)

        bad_report = copy.deepcopy(self.report)
        bad_report["coverage"]["linesHit"] = 0
        with self.assertRaisesRegex(ValueError, "linePercent|differs"):
            validate_coverage_artifact(self.artifact, bad_report)

    def test_empty_report_coverage_remains_valid_outside_coverage_runs(self) -> None:
        validate_report_coverage({})
