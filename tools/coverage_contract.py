"""Dependency-free invariant validation for resQ coverage schema v2."""

from __future__ import annotations

import math
import re
from typing import Any


SITE_ID = re.compile(r"^(?:statement|branch)_[0-9a-f]{32}$")
EDGE_ID = re.compile(r"^edge_[0-9a-f]{32}$")
RUN_ID = re.compile(r"^run_[0-9a-f]{32}$")
CONTEXT_KINDS = {"test", "attempt", "unattributed", "overflow"}
METRIC_KINDS = {"function", "statement", "branch"}
FALLBACKS = {
    "none",
    "statement_mode_disabled",
    "source_not_loaded",
    "function_wrapper_unavailable",
    "rewrite_rejected",
}

SUMMARY_COUNTS = {
    "linesFound", "linesHit", "functionsFound", "functionsHit",
    "statementSitesFound", "statementSitesHit", "statementSitesInstrumented",
    "branchesFound", "branchesHit", "branchSitesEligible", "branchSitesInstrumented",
    "filesFound", "filesLoaded", "filesWithStatements", "functionsEligible",
    "functionsInstrumented", "statementFunctionsEligible", "statementFunctionsInstrumented",
}
SUMMARY_PERCENTAGES = {
    "linePercent", "functionPercent", "statementSitePercent",
    "statementSiteInstrumentationPercent", "branchPercent",
    "branchInstrumentationPercent", "functionInstrumentationPercent",
    "statementInstrumentationPercent",
}
SUMMARY_BOOLEANS = {
    "statementSiteInstrumentationComplete", "branchMode",
    "branchInstrumentationComplete", "statementMode",
    "statementInstrumentationComplete",
}


def require(obj: Any, names: set[str], where: str) -> dict[str, Any]:
    if not isinstance(obj, dict):
        raise ValueError(f"{where}: expected object")
    missing = sorted(names - obj.keys())
    if missing:
        raise ValueError(f"{where}: missing {', '.join(missing)}")
    return obj


def nonnegative_int(value: Any, where: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{where}: expected non-negative integer")
    return value


def boolean(value: Any, where: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{where}: expected boolean")
    return value


def percent(value: Any, where: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{where}: expected percentage")
    number = float(value)
    if not math.isfinite(number) or not 0.0 <= number <= 100.0:
        raise ValueError(f"{where}: expected percentage from 0 through 100")
    return number


def expected_percent(hit: int, found: int) -> float:
    return 0.0 if found == 0 else 100.0 * hit / found


def equal_percent(actual: Any, hit: int, found: int, where: str) -> None:
    expected = expected_percent(hit, found)
    if abs(percent(actual, where) - expected) > 0.0001:
        raise ValueError(f"{where}: disagrees with hit/found counts")


def validate_summary(summary: Any, where: str = "coverage.summary") -> dict[str, Any]:
    value = require(
        summary,
        SUMMARY_COUNTS | SUMMARY_PERCENTAGES | SUMMARY_BOOLEANS | {"fallbackCounts"},
        where,
    )
    for name in SUMMARY_COUNTS:
        nonnegative_int(value[name], f"{where}.{name}")
    for name in SUMMARY_BOOLEANS:
        boolean(value[name], f"{where}.{name}")
    pairs = (
        ("linePercent", "linesHit", "linesFound"),
        ("functionPercent", "functionsHit", "functionsFound"),
        ("statementSitePercent", "statementSitesHit", "statementSitesFound"),
        (
            "statementSiteInstrumentationPercent",
            "statementSitesInstrumented",
            "statementSitesFound",
        ),
        ("branchPercent", "branchesHit", "branchesFound"),
        (
            "branchInstrumentationPercent",
            "branchSitesInstrumented",
            "branchSitesEligible",
        ),
        (
            "functionInstrumentationPercent",
            "functionsInstrumented",
            "functionsEligible",
        ),
        (
            "statementInstrumentationPercent",
            "statementFunctionsInstrumented",
            "statementFunctionsEligible",
        ),
    )
    for percentage, hit, found in pairs:
        if value[hit] > value[found]:
            raise ValueError(f"{where}.{hit}: exceeds {found}")
        equal_percent(value[percentage], value[hit], value[found], f"{where}.{percentage}")
    completeness = (
        ("statementSiteInstrumentationComplete", "statementSitesInstrumented", "statementSitesFound", value["statementMode"]),
        ("branchInstrumentationComplete", "branchSitesInstrumented", "branchSitesEligible", value["branchMode"]),
        ("statementInstrumentationComplete", "statementFunctionsInstrumented", "statementFunctionsEligible", value["statementMode"]),
    )
    for flag, measured, eligible, mode in completeness:
        expected = bool(mode and value[eligible] > 0 and value[measured] == value[eligible])
        if value[flag] != expected:
            raise ValueError(f"{where}.{flag}: disagrees with mode/completeness counts")
    fallbacks = require(value["fallbackCounts"], set(), f"{where}.fallbackCounts")
    for reason, count in fallbacks.items():
        if reason not in FALLBACKS:
            raise ValueError(f"{where}.fallbackCounts: unknown reason {reason!r}")
        nonnegative_int(count, f"{where}.fallbackCounts.{reason}")
    if "sourceParseComplete" in value or "sourceParseDiagnostics" in value:
        complete = boolean(value.get("sourceParseComplete"), f"{where}.sourceParseComplete")
        diagnostics = value.get("sourceParseDiagnostics")
        if not isinstance(diagnostics, list):
            raise ValueError(f"{where}.sourceParseDiagnostics: expected array")
        required = {"file", "function", "phase", "message"}
        for index, diagnostic in enumerate(diagnostics):
            row = require(diagnostic, required, f"{where}.sourceParseDiagnostics[{index}]")
            for name in required:
                if not isinstance(row[name], str):
                    raise ValueError(
                        f"{where}.sourceParseDiagnostics[{index}].{name}: expected string"
                    )
        if complete != (len(diagnostics) == 0):
            raise ValueError(
                f"{where}.sourceParseComplete: disagrees with sourceParseDiagnostics"
            )
    return value


def validate_gate(gate: Any, where: str) -> dict[str, Any]:
    value = require(gate, {"measurable", "basis", "percent", "hit", "found", "minimum", "passed"}, where)
    boolean(value["measurable"], f"{where}.measurable")
    boolean(value["passed"], f"{where}.passed")
    hit = nonnegative_int(value["hit"], f"{where}.hit")
    found = nonnegative_int(value["found"], f"{where}.found")
    if hit > found:
        raise ValueError(f"{where}.hit: exceeds found")
    equal_percent(value["percent"], hit, found, f"{where}.percent")
    minimum = percent(value["minimum"], f"{where}.minimum")
    if value["measurable"] != (found > 0):
        raise ValueError(f"{where}.measurable: disagrees with denominator")
    if value["passed"] != bool(value["measurable"] and float(value["percent"]) >= minimum):
        raise ValueError(f"{where}.passed: disagrees with measurable/threshold")
    return value


def validate_report_coverage(value: Any, where: str = "coverage") -> None:
    if value == {}:
        return
    coverage = require(
        value,
        SUMMARY_COUNTS
        | SUMMARY_PERCENTAGES
        | SUMMARY_BOOLEANS
        | {
            "schemaVersion", "enabled", "detailArtifact", "fallbackCounts",
            "gates", "allowPartialLines", "partialLines", "partialBranches",
            "basis", "minimum", "passed",
        },
        where,
    )
    if coverage["schemaVersion"] != 2 or coverage["enabled"] is not True:
        raise ValueError(f"{where}: expected enabled schemaVersion 2 measurement")
    if coverage["detailArtifact"] != "coverage.json":
        raise ValueError(f"{where}.detailArtifact: expected coverage.json")
    validate_summary(coverage, where)
    gates = require(
        coverage["gates"],
        {"functions", "lines", "completeness", "branches", "branchCompleteness"},
        f"{where}.gates",
    )
    checked = {name: validate_gate(gates[name], f"{where}.gates.{name}") for name in gates}
    expected = {
        "functions": ("functions", "functionsHit", "functionsFound"),
        "lines": ("measured_lines", "linesHit", "linesFound"),
        "completeness": (
            "statement_instrumentation", "statementFunctionsInstrumented",
            "statementFunctionsEligible",
        ),
        "branches": ("branches", "branchesHit", "branchesFound"),
        "branchCompleteness": (
            "branch_instrumentation", "branchSitesInstrumented", "branchSitesEligible",
        ),
    }
    for name, (basis, hit, found) in expected.items():
        if checked[name]["basis"] != basis:
            raise ValueError(f"{where}.gates.{name}.basis: unexpected")
        if checked[name]["hit"] != coverage[hit] or checked[name]["found"] != coverage[found]:
            raise ValueError(f"{where}.gates.{name}: disagrees with coverage summary")
    for name in ("allowPartialLines", "partialLines", "partialBranches", "passed"):
        boolean(coverage[name], f"{where}.{name}")
    if coverage["partialLines"] != bool(
        coverage["statementMode"]
        and coverage["statementFunctionsInstrumented"] < coverage["statementFunctionsEligible"]
    ):
        raise ValueError(f"{where}.partialLines: disagrees with statement completeness")
    if coverage["partialBranches"] != bool(
        coverage["branchMode"]
        and coverage["branchSitesInstrumented"] < coverage["branchSitesEligible"]
    ):
        raise ValueError(f"{where}.partialBranches: disagrees with branch completeness")
    if coverage["basis"] != checked["functions"]["basis"]:
        raise ValueError(f"{where}.basis: disagrees with function gate")
    if float(coverage["minimum"]) != float(checked["functions"]["minimum"]):
        raise ValueError(f"{where}.minimum: disagrees with function gate")
    expected_passed = checked["functions"]["passed"]
    if checked["lines"]["minimum"] > 0:
        expected_passed = bool(
            expected_passed
            and (coverage["allowPartialLines"] or not coverage["partialLines"])
            and checked["lines"]["passed"]
        )
    if checked["completeness"]["minimum"] > 0:
        expected_passed = bool(expected_passed and checked["completeness"]["passed"])
    if checked["branches"]["minimum"] > 0:
        expected_passed = bool(
            expected_passed and not coverage["partialBranches"] and checked["branches"]["passed"]
        )
    if checked["branchCompleteness"]["minimum"] > 0:
        expected_passed = bool(expected_passed and checked["branchCompleteness"]["passed"])
    if coverage["passed"] != expected_passed:
        raise ValueError(f"{where}.passed: disagrees with independent gates")


def validate_hit_record(row: Any, where: str) -> dict[str, Any]:
    value = require(row, {"hits", "covered"}, where)
    hits = nonnegative_int(value["hits"], f"{where}.hits")
    covered = boolean(value["covered"], f"{where}.covered")
    if covered != (hits > 0):
        raise ValueError(f"{where}.covered: disagrees with hits")
    return value


def validate_site(row: Any, where: str, kind: str) -> dict[str, Any]:
    common = {
        "siteId", "function", "line", "column", "lambdaId", "lambdaDepth",
        "anonymous", "eligible", "instrumented", "fallbackReason",
    }
    value = require(row, common | ({"hits", "covered"} if kind == "statement" else {
        "kind", "conditionIndex", "block", "edgesFound", "edgesHit", "edges"
    }), where)
    if not isinstance(value["siteId"], str) or not SITE_ID.fullmatch(value["siteId"]):
        raise ValueError(f"{where}.siteId: invalid")
    for name in ("line", "column", "lambdaDepth"):
        nonnegative_int(value[name], f"{where}.{name}")
    for name in ("anonymous", "eligible", "instrumented"):
        boolean(value[name], f"{where}.{name}")
    if value["fallbackReason"] not in FALLBACKS:
        raise ValueError(f"{where}.fallbackReason: unknown")
    if value["instrumented"] and not value["eligible"]:
        raise ValueError(f"{where}: ineligible site cannot be instrumented")
    if kind == "statement":
        validate_hit_record(value, where)
        if not value["instrumented"] and value["hits"]:
            raise ValueError(f"{where}: uninstrumented statement cannot have hits")
        return value
    if value["kind"] not in {"if", "while", "$", "conditional"}:
        raise ValueError(f"{where}.kind: invalid")
    nonnegative_int(value["conditionIndex"], f"{where}.conditionIndex")
    nonnegative_int(value["block"], f"{where}.block")
    edges = value["edges"]
    if not isinstance(edges, list) or len(edges) != 2:
        raise ValueError(f"{where}.edges: expected true and false edges")
    labels: list[str] = []
    ids: list[str] = []
    for index, edge in enumerate(edges):
        edge_where = f"{where}.edges[{index}]"
        item = require(edge, {"edgeId", "index", "label", "hits", "covered"}, edge_where)
        if not isinstance(item["edgeId"], str) or not EDGE_ID.fullmatch(item["edgeId"]):
            raise ValueError(f"{edge_where}.edgeId: invalid")
        if item["index"] not in {0, 1}:
            raise ValueError(f"{edge_where}.index: expected 0 or 1")
        if item["label"] not in {"true", "false"}:
            raise ValueError(f"{edge_where}.label: invalid")
        if item["label"] != ("true" if item["index"] == 0 else "false"):
            raise ValueError(f"{edge_where}.label: disagrees with edge index")
        validate_hit_record(item, edge_where)
        if not value["instrumented"] and item["hits"]:
            raise ValueError(f"{edge_where}: uninstrumented branch cannot have hits")
        labels.append(item["label"])
        ids.append(item["edgeId"])
    if sorted(edge["index"] for edge in edges) != [0, 1] or len(ids) != len(set(ids)):
        raise ValueError(f"{where}.edges: expected unique true/false identities")
    found = 2 if value["eligible"] else 0
    hit = sum(edge["hits"] > 0 for edge in edges) if value["eligible"] else 0
    if value["edgesFound"] != found or value["edgesHit"] != hit:
        raise ValueError(f"{where}: edge aggregates disagree with edges")
    return value


def validate_coverage_artifact(
    document: Any, report: dict[str, Any] | None = None
) -> None:
    root = require(
        document,
        {
            "schemaVersion", "kind", "framework", "frameworkVersion", "runId",
            "summary", "files", "contextMeasurement",
        },
        "coverage artifact",
    )
    if root["schemaVersion"] != 2 or root["kind"] != "resq-coverage" or root["framework"] != "resQ":
        raise ValueError("coverage artifact: unsupported producer/schema")
    if not isinstance(root["runId"], str) or not RUN_ID.fullmatch(root["runId"]):
        raise ValueError("coverage.runId: invalid")
    summary = validate_summary(root["summary"])
    files = root["files"]
    if not isinstance(files, list):
        raise ValueError("coverage.files: expected array")
    paths: list[str] = []
    all_functions: list[dict[str, Any]] = []
    all_lines: list[dict[str, Any]] = []
    all_sites: list[dict[str, Any]] = []
    all_branches: list[dict[str, Any]] = []
    function_catalog: set[tuple[str, str]] = set()
    site_catalog: set[tuple[str, str]] = set()
    edge_catalog: set[tuple[str, str, int]] = set()
    for file_index, file_row in enumerate(files):
        where = f"coverage.files[{file_index}]"
        value = require(
            file_row,
            {
                "path", "loaded", "functionFound", "functionHit", "statementFunctionsInstrumented",
                "lineFound", "lineHit", "statementSitesEligible", "statementSitesInstrumented",
                "statementSitesHit", "branchSitesEligible", "branchSitesInstrumented",
                "branchFound", "branchHit", "functions", "lines", "statementSites", "branches",
            },
            where,
        )
        if not isinstance(value["path"], str) or not value["path"]:
            raise ValueError(f"{where}.path: expected nonempty string")
        paths.append(value["path"])
        boolean(value["loaded"], f"{where}.loaded")
        for name in (
            "functionFound", "functionHit", "statementFunctionsInstrumented", "lineFound", "lineHit",
            "statementSitesEligible", "statementSitesInstrumented", "statementSitesHit",
            "branchSitesEligible", "branchSitesInstrumented", "branchFound", "branchHit",
        ):
            nonnegative_int(value[name], f"{where}.{name}")
        functions = value["functions"]
        lines = value["lines"]
        sites = value["statementSites"]
        branches = value["branches"]
        if not all(isinstance(rows, list) for rows in (functions, lines, sites, branches)):
            raise ValueError(f"{where}: coverage child collections must be arrays")
        function_ids: set[tuple[str, int]] = set()
        embedded_sites: list[dict[str, Any]] = []
        embedded_branches: list[dict[str, Any]] = []
        embedded_lines: list[dict[str, Any]] = []
        for function_index, function in enumerate(functions):
            fn_where = f"{where}.functions[{function_index}]"
            fn = require(
                function,
                {
                    "name", "line", "hits", "covered", "functionEligible", "functionInstrumented",
                    "statementEligible", "statementInstrumented", "fallbackReason", "statementFound",
                    "statementHit", "statements", "statementSitesFound", "statementSitesHit",
                    "statementSitesInstrumented", "statementSites", "branchSitesEligible",
                    "branchSitesInstrumented", "branchFound", "branchHit", "branches",
                },
                fn_where,
            )
            if not isinstance(fn["name"], str):
                raise ValueError(f"{fn_where}.name: expected string")
            line = nonnegative_int(fn["line"], f"{fn_where}.line")
            identity = (fn["name"], line)
            if identity in function_ids:
                raise ValueError(f"{where}.functions: duplicate function identity")
            function_ids.add(identity)
            function_catalog.add((value["path"], fn["name"]))
            validate_hit_record(fn, fn_where)
            for name in ("functionEligible", "functionInstrumented", "statementEligible", "statementInstrumented"):
                boolean(fn[name], f"{fn_where}.{name}")
            if fn["functionInstrumented"] and not fn["functionEligible"]:
                raise ValueError(f"{fn_where}: ineligible function cannot be instrumented")
            if fn["fallbackReason"] not in FALLBACKS:
                raise ValueError(f"{fn_where}.fallbackReason: unknown")
            statement_rows = fn["statements"]
            if not isinstance(statement_rows, list):
                raise ValueError(f"{fn_where}.statements: expected array")
            seen_lines: set[int] = set()
            for statement_index, statement in enumerate(statement_rows):
                statement_where = f"{fn_where}.statements[{statement_index}]"
                item = require(statement, {"line", "hits", "covered"}, statement_where)
                line_number = nonnegative_int(item["line"], f"{statement_where}.line")
                if line_number in seen_lines:
                    raise ValueError(f"{fn_where}.statements: duplicate line")
                seen_lines.add(line_number)
                validate_hit_record(item, statement_where)
            fn_sites = [validate_site(row, f"{fn_where}.statementSites[{i}]", "statement") for i, row in enumerate(fn["statementSites"])]
            fn_branches = [validate_site(row, f"{fn_where}.branches[{i}]", "branch") for i, row in enumerate(fn["branches"])]
            expected_counts = {
                "statementFound": len(statement_rows),
                "statementHit": sum(row["hits"] > 0 for row in statement_rows),
                "statementSitesFound": sum(row["eligible"] for row in fn_sites),
                "statementSitesHit": sum(row["eligible"] and row["hits"] > 0 for row in fn_sites),
                "statementSitesInstrumented": sum(row["instrumented"] for row in fn_sites),
                "branchSitesEligible": sum(row["eligible"] for row in fn_branches),
                "branchSitesInstrumented": sum(row["instrumented"] for row in fn_branches),
                "branchFound": sum(row["edgesFound"] for row in fn_branches if row["eligible"]),
                "branchHit": sum(row["edgesHit"] for row in fn_branches if row["eligible"]),
            }
            for name, expected in expected_counts.items():
                if fn[name] != expected:
                    raise ValueError(f"{fn_where}.{name}: disagrees with child records")
            embedded_lines.extend(statement_rows)
            embedded_sites.extend(fn_sites)
            embedded_branches.extend(fn_branches)
        validated_lines = []
        line_ids: set[int] = set()
        for line_index, line_row in enumerate(lines):
            line_where = f"{where}.lines[{line_index}]"
            item = require(line_row, {"line", "hits", "covered"}, line_where)
            line_number = nonnegative_int(item["line"], f"{line_where}.line")
            if line_number in line_ids:
                raise ValueError(f"{where}.lines: duplicate line")
            line_ids.add(line_number)
            validate_hit_record(item, line_where)
            validated_lines.append(item)
        validated_sites = [validate_site(row, f"{where}.statementSites[{i}]", "statement") for i, row in enumerate(sites)]
        validated_branches = [validate_site(row, f"{where}.branches[{i}]", "branch") for i, row in enumerate(branches)]
        site_catalog.update((value["path"], row["siteId"]) for row in validated_sites + validated_branches)
        edge_catalog.update(
            (value["path"], row["siteId"], edge["index"])
            for row in validated_branches for edge in row["edges"]
        )
        line_map = {row["line"]: row for row in embedded_lines}
        public_line_map = {row["line"]: row for row in validated_lines}
        site_map = {row["siteId"]: row for row in embedded_sites}
        public_site_map = {row["siteId"]: row for row in validated_sites}
        branch_map = {row["siteId"]: row for row in embedded_branches}
        public_branch_map = {row["siteId"]: row for row in validated_branches}
        if line_map != public_line_map or site_map != public_site_map or branch_map != public_branch_map:
            raise ValueError(f"{where}: file-level coverage rows differ from function children")
        file_counts = {
            "functionFound": len(functions),
            "functionHit": sum(row["hits"] > 0 for row in functions),
            "statementFunctionsInstrumented": sum(row["statementInstrumented"] for row in functions),
            "lineFound": len(lines),
            "lineHit": sum(row["hits"] > 0 for row in lines),
            "statementSitesEligible": sum(row["eligible"] for row in validated_sites),
            "statementSitesInstrumented": sum(row["instrumented"] for row in validated_sites),
            "statementSitesHit": sum(row["eligible"] and row["hits"] > 0 for row in validated_sites),
            "branchSitesEligible": sum(row["eligible"] for row in validated_branches),
            "branchSitesInstrumented": sum(row["instrumented"] for row in validated_branches),
            "branchFound": sum(row["edgesFound"] for row in validated_branches if row["eligible"]),
            "branchHit": sum(row["edgesHit"] for row in validated_branches if row["eligible"]),
        }
        for name, expected in file_counts.items():
            if value[name] != expected:
                raise ValueError(f"{where}.{name}: disagrees with child records")
        all_functions.extend(functions)
        all_lines.extend(lines)
        all_sites.extend(validated_sites)
        all_branches.extend(validated_branches)
    if len(paths) != len(set(paths)):
        raise ValueError("coverage.files: duplicate path")
    site_ids = [row["siteId"] for row in all_sites + all_branches]
    edge_ids = [edge["edgeId"] for branch in all_branches for edge in branch["edges"]]
    if len(site_ids) != len(set(site_ids)) or len(edge_ids) != len(set(edge_ids)):
        raise ValueError("coverage: duplicate site or edge identity")
    aggregate = {
        "filesFound": len(files),
        "filesLoaded": sum(row["loaded"] for row in files),
        "filesWithStatements": sum(row["lineFound"] > 0 for row in files),
        "functionsFound": len(all_functions),
        "functionsHit": sum(row["hits"] > 0 for row in all_functions),
        "functionsEligible": sum(row["functionEligible"] for row in all_functions),
        "functionsInstrumented": sum(row["functionInstrumented"] for row in all_functions),
        "statementFunctionsEligible": sum(row["statementEligible"] for row in all_functions),
        "statementFunctionsInstrumented": sum(row["statementInstrumented"] for row in all_functions),
        "linesFound": len(all_lines),
        "linesHit": sum(row["hits"] > 0 for row in all_lines),
        "statementSitesFound": sum(row["eligible"] for row in all_sites),
        "statementSitesInstrumented": sum(row["instrumented"] for row in all_sites),
        "statementSitesHit": sum(row["eligible"] and row["hits"] > 0 for row in all_sites),
        "branchSitesEligible": sum(row["eligible"] for row in all_branches),
        "branchSitesInstrumented": sum(row["instrumented"] for row in all_branches),
        "branchesFound": sum(row["edgesFound"] for row in all_branches if row["eligible"]),
        "branchesHit": sum(row["edgesHit"] for row in all_branches if row["eligible"]),
    }
    for name, expected in aggregate.items():
        if summary[name] != expected:
            raise ValueError(f"coverage.summary.{name}: disagrees with files")
    fallback_counts = {name: 0 for name in summary["fallbackCounts"]}
    for function in all_functions:
        reason = function["fallbackReason"]
        if reason != "none":
            fallback_counts.setdefault(reason, 0)
            fallback_counts[reason] += 1
    if summary["fallbackCounts"] != fallback_counts:
        raise ValueError("coverage.summary.fallbackCounts: disagrees with functions")
    context_metrics = validate_context_measurement(root["contextMeasurement"])
    for metric in context_metrics:
        path = metric["file"]
        if path not in paths:
            raise ValueError("coverage context metric references an unknown file")
        if metric["kind"] == "function":
            if (path, metric["function"]) not in function_catalog:
                raise ValueError("coverage function metric references an unknown function")
        elif metric["kind"] == "statement":
            if (path, metric["siteId"]) not in site_catalog:
                raise ValueError("coverage statement metric references an unknown site")
        elif (path, metric["siteId"], metric["edgeIndex"]) not in edge_catalog:
            raise ValueError("coverage branch metric references an unknown edge")
    if report is not None:
        if report.get("run", {}).get("id") != root["runId"]:
            raise ValueError("coverage.runId differs from report")
        if report.get("frameworkVersion") != root["frameworkVersion"]:
            raise ValueError("coverage.frameworkVersion differs from report")
        validate_report_coverage(report.get("coverage", {}), "report.coverage")
        report_coverage = report.get("coverage", {})
        if report_coverage:
            for name in SUMMARY_COUNTS | SUMMARY_PERCENTAGES | SUMMARY_BOOLEANS | {"fallbackCounts"}:
                if report_coverage[name] != summary[name]:
                    raise ValueError(f"report.coverage.{name}: differs from coverage artifact")
        test_ids = {row.get("testId") for row in report.get("tests", [])}
        for context in root["contextMeasurement"].get("contexts", []):
            if context["kind"] in {"test", "attempt"} and context["testId"] not in test_ids:
                raise ValueError("coverage context testId does not exist in report")


def validate_context_measurement(value: Any) -> list[dict[str, Any]]:
    where = "coverage.contextMeasurement"
    measurement = require(
        value,
        {"schemaVersion", "enabled", "detail", "contextLimit", "entryLimit", "summary", "contexts"},
        where,
    )
    if measurement["schemaVersion"] != 1:
        raise ValueError(f"{where}.schemaVersion: unsupported")
    enabled = boolean(measurement["enabled"], f"{where}.enabled")
    if measurement["detail"] not in {"test", "attempt"}:
        raise ValueError(f"{where}.detail: invalid")
    context_limit = nonnegative_int(measurement["contextLimit"], f"{where}.contextLimit")
    entry_limit = nonnegative_int(measurement["entryLimit"], f"{where}.entryLimit")
    summary = require(
        measurement["summary"],
        {
            "contextsStored", "metricEntriesStored", "functionHits", "statementHits",
            "branchHits", "unattributedHits", "overflowActivations", "droppedMetricHits", "truncated",
        },
        f"{where}.summary",
    )
    for name in summary.keys() - {"truncated"}:
        nonnegative_int(summary[name], f"{where}.summary.{name}")
    boolean(summary["truncated"], f"{where}.summary.truncated")
    contexts = measurement["contexts"]
    if not isinstance(contexts, list):
        raise ValueError(f"{where}.contexts: expected array")
    ids: list[str] = []
    metrics: list[dict[str, Any]] = []
    unattributed_hits = 0
    normal_count = 0
    for index, context in enumerate(contexts):
        context_where = f"{where}.contexts[{index}]"
        item = require(
            context,
            {"contextId", "kind", "testId", "attempt", "suite", "description", "file", "metrics"},
            context_where,
        )
        if not isinstance(item["contextId"], str) or not item["contextId"]:
            raise ValueError(f"{context_where}.contextId: expected nonempty string")
        if item["kind"] not in CONTEXT_KINDS:
            raise ValueError(f"{context_where}.kind: invalid")
        nonnegative_int(item["attempt"], f"{context_where}.attempt")
        if item["kind"] == "attempt" and item["attempt"] < 1:
            raise ValueError(f"{context_where}.attempt: attempt context requires positive number")
        if measurement["detail"] == "test" and item["kind"] == "attempt":
            raise ValueError(f"{context_where}: attempt context in test-detail measurement")
        ids.append(item["contextId"])
        if item["kind"] not in {"unattributed", "overflow"}:
            normal_count += 1
        rows = item["metrics"]
        if not isinstance(rows, list):
            raise ValueError(f"{context_where}.metrics: expected array")
        metric_ids: set[str] = set()
        for metric_index, metric in enumerate(rows):
            metric_where = f"{context_where}.metrics[{metric_index}]"
            record = require(
                metric,
                {"contextId", "metricId", "kind", "file", "function", "siteId", "edgeIndex", "edgeLabel", "hits"},
                metric_where,
            )
            if record["contextId"] != item["contextId"]:
                raise ValueError(f"{metric_where}.contextId: differs from parent")
            for name in ("metricId", "file", "function", "siteId", "edgeLabel"):
                if not isinstance(record[name], str):
                    raise ValueError(f"{metric_where}.{name}: expected string")
            if not record["metricId"]:
                raise ValueError(f"{metric_where}.metricId: expected nonempty string")
            if record["metricId"] in metric_ids:
                raise ValueError(f"{context_where}.metrics: duplicate metricId")
            metric_ids.add(record["metricId"])
            if record["kind"] not in METRIC_KINDS:
                raise ValueError(f"{metric_where}.kind: invalid")
            edge_index = record["edgeIndex"]
            if isinstance(edge_index, bool) or not isinstance(edge_index, int):
                raise ValueError(f"{metric_where}.edgeIndex: expected integer")
            if record["kind"] == "function":
                if record["siteId"] or edge_index != -1 or record["edgeLabel"]:
                    raise ValueError(f"{metric_where}: invalid function metric identity")
            elif record["kind"] == "statement":
                if not SITE_ID.fullmatch(record["siteId"]) or edge_index != -1 or record["edgeLabel"]:
                    raise ValueError(f"{metric_where}: invalid statement metric identity")
            else:
                if (
                    not SITE_ID.fullmatch(record["siteId"])
                    or edge_index not in {0, 1}
                    or record["edgeLabel"] != ("true" if edge_index == 0 else "false")
                ):
                    raise ValueError(f"{metric_where}: invalid branch metric identity")
            hits = nonnegative_int(record["hits"], f"{metric_where}.hits")
            if hits < 1:
                raise ValueError(f"{metric_where}.hits: stored metrics require observed hits")
            if item["kind"] == "unattributed":
                unattributed_hits += hits
            metrics.append(record)
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        raise ValueError(f"{where}.contexts: identities must be unique and sorted")
    if not enabled and contexts:
        raise ValueError(f"{where}: disabled measurement must not retain contexts")
    if normal_count > context_limit or len(metrics) > entry_limit:
        raise ValueError(f"{where}: configured storage limits exceeded")
    expected = {
        "contextsStored": normal_count,
        "metricEntriesStored": len(metrics),
        "functionHits": sum(row["hits"] for row in metrics if row["kind"] == "function"),
        "statementHits": sum(row["hits"] for row in metrics if row["kind"] == "statement"),
        "branchHits": sum(row["hits"] for row in metrics if row["kind"] == "branch"),
        "unattributedHits": unattributed_hits,
    }
    for name, expected_value in expected.items():
        if summary[name] != expected_value:
            raise ValueError(f"{where}.summary.{name}: disagrees with contexts")
    truncated = bool(summary["overflowActivations"] or summary["droppedMetricHits"])
    if summary["truncated"] != truncated:
        raise ValueError(f"{where}.summary.truncated: disagrees with loss counters")
    return metrics
