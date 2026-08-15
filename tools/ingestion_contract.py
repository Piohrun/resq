#!/usr/bin/env python3
"""Executable SQL contract for normalized resQ table-v2 evidence.

The ordered table/column registry below drives DDL, inserts, reference SQL, and
the example Grafana dashboard. Every normalized row is also retained verbatim
in ``raw_payload`` so additive table-v2 fields are never discarded by an older
loader.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Iterable


@dataclass(frozen=True)
class Column:
    source: str
    kind: str = "text"
    nullable: bool = False
    sql_name: str | None = None

    @property
    def name(self) -> str:
        if self.sql_name:
            return self.sql_name
        return re.sub(r"(?<!^)(?=[A-Z])", "_", self.source).lower()


@dataclass(frozen=True)
class ForeignKey:
    columns: tuple[str, ...]
    target_table: str
    target_columns: tuple[str, ...]


@dataclass(frozen=True)
class Table:
    source: str
    columns: tuple[Column, ...]
    primary_key: tuple[str, ...]
    foreign_keys: tuple[ForeignKey, ...] = ()

    @property
    def name(self) -> str:
        return "resq_" + re.sub(r"(?<!^)(?=[A-Z])", "_", self.source).lower()


def c(source: str, kind: str = "text", nullable: bool = False, sql_name: str | None = None) -> Column:
    return Column(source, kind, nullable, sql_name)


TABLES: tuple[Table, ...] = (
    Table("runs", (
        c("runId"), c("startedAt", "timestamp"), c("finishedAt", "timestamp"),
        c("durationSeconds", "real"), c("frameworkVersion"), c("hostname"),
        c("qVersion"), c("os"), c("testCount", "integer"),
        c("passCount", "integer"), c("failCount", "integer"),
        c("errorCount", "integer"), c("skipCount", "integer"),
        c("assertionCount", "integer"), c("labels", "json"), c("environment"),
        c("service"), c("deploymentId"), c("artifactDigest"), c("vcsSha"),
        c("vcsBranch"), c("ciProvider"), c("ciPipelineId"),
    ), ("run_id",)),
    Table("tests", (
        c("runId"), c("executionId"), c("testId"), c("caseId"), c("suite"),
        c("description"), c("kind"), c("status"), c("durationSeconds", "real"),
        c("assertsRun", "integer"), c("attempts", "integer"),
        c("retried", "boolean"), c("flaky", "boolean"),
        c("file", sql_name="file_path"), c("line", "integer", True), c("message"),
        c("quarantineState", nullable=True), c("quarantineActive", "boolean", True),
        c("quarantineOwner", nullable=True), c("quarantineReason", nullable=True),
        c("quarantineIssue", nullable=True), c("quarantineExpiresAt", "timestamp", True),
    ), ("run_id", "execution_id"), (
        ForeignKey(("run_id",), "runs", ("run_id",)),
    )),
    Table("attempts", (
        c("runId"), c("executionId"), c("attemptKey"), c("attempt", "integer"),
        c("status"), c("durationSeconds", "real"),
        c("startedAt", "timestamp", True), c("finishedAt", "timestamp", True),
        c("assertsRun", "integer"), c("message"),
    ), ("attempt_key",), (
        ForeignKey(("run_id", "execution_id"), "tests", ("run_id", "execution_id")),
    )),
    Table("benchmarks", (
        c("runId"), c("benchmarkId"), c("testId"), c("suite"), c("description"),
        c("metric"), c("unit"), c("runs", "integer"),
        c("avgTimeMs", "real", True), c("medTimeMs", "real", True),
        c("maxTimeMs", "real", True), c("avgSpaceBytes", "real", True),
        c("comparisonClass"),
    ), ("run_id", "benchmark_id"), (
        ForeignKey(("run_id",), "runs", ("run_id",)),
    )),
    Table("diagnostics", (
        c("runId"), c("diagnosticKey"), c("type"), c("severity"), c("phase"),
        c("message"), c("data", "json"),
    ), ("diagnostic_key",), (
        ForeignKey(("run_id",), "runs", ("run_id",)),
    )),
    Table("coverageRuns", (
        c("runId"), c("functionsFound", "integer"), c("functionsHit", "integer"),
        c("functionPercent", "real"), c("linesFound", "integer"),
        c("linesHit", "integer"), c("linePercent", "real"),
        c("statementSitesFound", "integer"), c("statementSitesHit", "integer"),
        c("statementSitePercent", "real"),
        c("statementSiteInstrumentationPercent", "real"),
        c("statementSiteInstrumentationComplete", "boolean"),
        c("branchesFound", "integer"), c("branchesHit", "integer"),
        c("branchPercent", "real"), c("branchInstrumentationPercent", "real"),
        c("branchInstrumentationComplete", "boolean"),
        c("functionInstrumentationPercent", "real"),
        c("statementInstrumentationPercent", "real"),
        c("statementInstrumentationComplete", "boolean"),
    ), ("run_id",), (
        ForeignKey(("run_id",), "runs", ("run_id",)),
    )),
    Table("coverageFiles", (
        c("runId"), c("coverageFileKey"), c("path", sql_name="file_path"),
        c("loaded", "boolean"), c("functionFound", "integer"),
        c("functionHit", "integer"), c("lineFound", "integer"),
        c("lineHit", "integer"),
    ), ("coverage_file_key",), (
        ForeignKey(("run_id",), "runs", ("run_id",)),
    )),
    Table("coverageFunctions", (
        c("runId"), c("coverageFileKey"), c("coverageFunctionKey"),
        c("path", sql_name="file_path"), c("name", sql_name="function_name"),
        c("line", "integer"), c("hits", "integer"), c("covered", "boolean"),
    ), ("coverage_function_key",), (
        ForeignKey(("coverage_file_key",), "coverageFiles", ("coverage_file_key",)),
    )),
    Table("coverageSites", (
        c("runId"), c("coverageFileKey"), c("coverageFunctionKey"),
        c("coverageSiteKey"), c("siteId"), c("kind"),
        c("path", sql_name="file_path"), c("function", sql_name="function_name"),
        c("line", "integer", True), c("column", "integer", True, "column_number"),
        c("eligible", "boolean"), c("instrumented", "boolean"),
        c("hits", "integer", True), c("edgesHit", "integer", True),
    ), ("coverage_site_key",), (
        ForeignKey(("coverage_file_key",), "coverageFiles", ("coverage_file_key",)),
    )),
    Table("coverageEdges", (
        c("runId"), c("coverageSiteKey"), c("coverageEdgeKey"), c("edgeId"),
        c("label"), c("hits", "integer"), c("covered", "boolean"),
    ), ("coverage_edge_key",), (
        ForeignKey(("coverage_site_key",), "coverageSites", ("coverage_site_key",)),
    )),
    Table("coverageContexts", (
        c("runId"), c("coverageContextKey"), c("contextId"), c("kind"),
        c("testId"), c("attempt", "integer"), c("suite"), c("description"),
        c("file", sql_name="file_path"),
    ), ("coverage_context_key",), (
        ForeignKey(("run_id",), "runs", ("run_id",)),
    )),
    Table("coverageContextMetrics", (
        c("runId"), c("coverageContextKey"), c("metricId"), c("kind"),
        c("coverageFileKey"), c("coverageSiteKey"),
        c("function", sql_name="function_name"), c("edgeIndex", "integer", True),
        c("edgeLabel"), c("hits", "integer"),
    ), ("run_id", "coverage_context_key", "metric_id"), (
        ForeignKey(("coverage_context_key",), "coverageContexts", ("coverage_context_key",)),
    )),
)

TABLE_BY_SOURCE = {table.source: table for table in TABLES}


@dataclass(frozen=True)
class Query:
    key: str
    title: str
    sql: str
    panel_type: str = "table"


FILTER = ("(:service = '' OR r.service = :service) "
          "AND (:environment = '' OR r.environment = :environment) "
          "AND (:branch = '' OR r.vcs_branch = :branch)")
FILTER_PARAMETERS = ("service", "environment", "branch", "test", "benchmark")
# The same predicate for a correlated subquery that scans runs under its own
# alias (latest-run scoping must respect the active filters).
FILTER2 = FILTER.replace("r.", "r2.")
QUERIES: tuple[Query, ...] = (
    Query("services", "Services", "SELECT DISTINCT service AS __text, service AS __value FROM resq_runs WHERE service <> '' ORDER BY service"),
    Query("environments", "Environments", "SELECT DISTINCT environment AS __text, environment AS __value FROM resq_runs WHERE environment <> '' AND (:service = '' OR service = :service) ORDER BY environment"),
    Query("branches", "Branches", "SELECT DISTINCT vcs_branch AS __text, vcs_branch AS __value FROM resq_runs WHERE vcs_branch <> '' AND (:service = '' OR service = :service) ORDER BY vcs_branch"),
    Query("tests_list", "Tests", f"""
SELECT DISTINCT t.suite || ' :: ' || t.description ||
       CASE WHEN t.case_id <> '' THEN ' [case]' ELSE '' END AS __text,
       t.execution_id AS __value
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} ORDER BY __text LIMIT 2000
"""),
    Query("benchmarks_list", "Benchmarks", f"""
SELECT DISTINCT b.suite || ' :: ' || b.description AS __text,
       b.benchmark_id AS __value
FROM resq_benchmarks AS b JOIN resq_runs AS r ON r.run_id = b.run_id
WHERE {FILTER} ORDER BY __text LIMIT 500
"""),
    Query("headline_trend", "Latest run headline", f"""
SELECT r.finished_at AS time, r.test_count,
       r.fail_count + r.error_count AS failures,
       CASE WHEN r.test_count = 0 THEN 100.0 ELSE 100.0 * r.pass_count / r.test_count END AS pass_rate,
       (SELECT COUNT(*) FROM resq_tests AS t WHERE t.run_id = r.run_id AND t.flaky) AS flaky_count,
       (SELECT COUNT(*) FROM resq_tests AS t WHERE t.run_id = r.run_id AND t.quarantine_active) AS active_quarantines,
       (SELECT c.function_percent FROM resq_coverage_runs AS c WHERE c.run_id = r.run_id) AS function_percent
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "stat"),
    Query("pass_rate", "Pass rate", f"""
SELECT r.finished_at AS time,
       CASE WHEN r.test_count = 0 THEN 100.0 ELSE 100.0 * r.pass_count / r.test_count END AS pass_rate
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("failure_breakdown", "Failures, errors, flakes, skips", f"""
SELECT r.finished_at AS time, r.fail_count AS failed, r.error_count AS errored,
       r.skip_count AS skipped,
       (SELECT COUNT(*) FROM resq_tests AS t
         WHERE t.run_id = r.run_id AND t.flaky) AS flaky
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("run_duration", "Run duration", f"""
SELECT r.finished_at AS time, r.duration_seconds
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("test_volume", "Tests and assertions per run", f"""
SELECT r.finished_at AS time, r.test_count AS tests, r.assertion_count AS assertions
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("coverage_trend", "Coverage by basis", f"""
SELECT r.finished_at AS time, c.function_percent, c.line_percent,
       c.statement_site_percent, c.branch_percent
FROM resq_coverage_runs AS c JOIN resq_runs AS r ON r.run_id = c.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("coverage_completeness", "Instrumentation completeness", f"""
SELECT r.finished_at AS time,
       c.statement_site_instrumentation_percent AS statement_completeness,
       c.branch_instrumentation_percent AS branch_completeness
FROM resq_coverage_runs AS c JOIN resq_runs AS r ON r.run_id = c.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("coverage_drops", "Coverage drops vs previous covered run", f"""
WITH history AS (
    SELECT f.file_path, r.finished_at,
           CASE WHEN f.function_found = 0 THEN 100.0
                ELSE 100.0 * f.function_hit / f.function_found END AS function_percent,
           LAG(CASE WHEN f.function_found = 0 THEN 100.0
                ELSE 100.0 * f.function_hit / f.function_found END) OVER (
               PARTITION BY f.file_path ORDER BY r.finished_at) AS previous_percent
    FROM resq_coverage_files AS f JOIN resq_runs AS r ON r.run_id = f.run_id
    WHERE {FILTER})
SELECT h.file_path, h.previous_percent, h.function_percent,
       h.function_percent - h.previous_percent AS change
FROM history AS h
WHERE h.finished_at = (
    SELECT MAX(r2.finished_at) FROM resq_runs AS r2
    JOIN resq_coverage_runs AS c2 ON c2.run_id = r2.run_id WHERE {FILTER2})
  AND h.previous_percent IS NOT NULL
  AND h.function_percent < h.previous_percent
ORDER BY change, h.file_path LIMIT 25
"""),
    Query("daily_duration", "Daily run duration (avg/max)", f"""
SELECT MIN(r.finished_at) AS time,
       AVG(r.duration_seconds) AS avg_seconds,
       MAX(r.duration_seconds) AS max_seconds
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
GROUP BY SUBSTR(CAST(r.finished_at AS TEXT), 1, 10)
ORDER BY time
""", "timeseries"),
    Query("coverage_files_latest", "Least-covered files (latest run)", f"""
SELECT f.file_path, f.function_hit, f.function_found,
       CASE WHEN f.function_found = 0 THEN 100.0
            ELSE 100.0 * f.function_hit / f.function_found END AS function_percent,
       f.line_hit, f.line_found, f.loaded
FROM resq_coverage_files AS f
JOIN resq_runs AS r ON r.run_id = f.run_id
WHERE {FILTER} AND r.finished_at = (
    SELECT MAX(r2.finished_at) FROM resq_runs AS r2
    JOIN resq_coverage_runs AS c2 ON c2.run_id = r2.run_id WHERE {FILTER2})
ORDER BY function_percent, f.file_path LIMIT 25
"""),
    Query("slowest_tests", "Slowest tests (latest run)", f"""
SELECT t.suite, t.description, t.duration_seconds, t.attempts, t.file_path,
       t.execution_id
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} AND r.finished_at = (
    SELECT MAX(r2.finished_at) FROM resq_runs AS r2 WHERE {FILTER2})
ORDER BY t.duration_seconds DESC LIMIT 15
"""),
    Query("failing_tests", "Most-failing tests (selected range)", f"""
SELECT t.suite, t.description,
       SUM(CASE WHEN t.status IN ('fail', 'error') THEN 1 ELSE 0 END) AS failures,
       SUM(CASE WHEN t.flaky THEN 1 ELSE 0 END) AS flaky_passes,
       COUNT(*) AS runs, MAX(r.finished_at) AS last_seen, t.execution_id
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
GROUP BY t.test_id, t.case_id, t.suite, t.description, t.execution_id
HAVING SUM(CASE WHEN t.status IN ('fail', 'error') THEN 1 ELSE 0 END) > 0
    OR SUM(CASE WHEN t.flaky THEN 1 ELSE 0 END) > 0
ORDER BY failures DESC, flaky_passes DESC LIMIT 15
"""),
    Query("newly_failing", "Newly failing tests (latest vs previous run)", f"""
WITH history AS (
    SELECT t.execution_id, t.suite, t.description, t.status, t.file_path,
           r.finished_at,
           LAG(t.status) OVER (
               PARTITION BY t.execution_id ORDER BY r.finished_at) AS previous_status
    FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
    WHERE {FILTER})
SELECT h.suite, h.description, h.previous_status, h.status, h.file_path,
       h.execution_id
FROM history AS h
WHERE h.finished_at = (SELECT MAX(r2.finished_at) FROM resq_runs AS r2 WHERE {FILTER2})
  AND h.status IN ('fail', 'error') AND h.previous_status = 'pass'
ORDER BY h.suite, h.description LIMIT 25
"""),
    Query("test_detail_history", "Selected test duration history", f"""
SELECT r.finished_at AS time, t.duration_seconds
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} AND (:test = '' OR t.execution_id = :test) /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("test_detail_runs", "Selected test executions", f"""
SELECT r.finished_at AS time, t.status, t.duration_seconds, t.attempts,
       t.flaky, t.message
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} AND (:test = '' OR t.execution_id = :test) /*+timefilter:r.finished_at*/
ORDER BY r.finished_at DESC LIMIT 50
"""),
    Query("test_detail_attempts", "Selected test attempts", f"""
SELECT a.started_at, a.attempt, a.status, a.duration_seconds, a.message
FROM resq_attempts AS a
JOIN resq_runs AS r ON r.run_id = a.run_id
WHERE {FILTER} AND (:test = '' OR a.execution_id = :test)
ORDER BY a.attempt_key DESC LIMIT 100
"""),
    Query("test_history", "Per-test history", f"""
SELECT r.finished_at AS time, t.test_id, t.case_id, t.suite, t.description,
       t.status, t.duration_seconds, t.file_path
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at, t.test_id, t.case_id
"""),
    Query("quarantine_debt", "Quarantine and retry debt", f"""
SELECT r.finished_at AS time,
       (SELECT COUNT(*) FROM resq_tests AS t
         WHERE t.run_id = r.run_id AND t.quarantine_active) AS active_quarantines,
       (SELECT COUNT(*) FROM resq_tests AS t
         WHERE t.run_id = r.run_id AND t.retried) AS retried_tests
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at
""", "timeseries"),
    Query("quarantined_tests", "Active quarantines (latest run)", f"""
SELECT t.suite, t.description, t.status, t.quarantine_state,
       t.quarantine_owner, t.quarantine_reason, t.quarantine_issue,
       t.quarantine_expires_at
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} AND t.quarantine_active AND r.finished_at = (
    SELECT MAX(r2.finished_at) FROM resq_runs AS r2 WHERE {FILTER2})
ORDER BY t.quarantine_expires_at, t.suite, t.description
"""),
    Query("benchmark_history", "Benchmark medians", f"""
SELECT r.finished_at AS time, b.suite || ' :: ' || b.description AS metric,
       b.med_time_ms AS value
FROM resq_benchmarks AS b JOIN resq_runs AS r ON r.run_id = b.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
  AND (:benchmark = '' OR b.benchmark_id = :benchmark)
  AND (:benchmark <> '' OR b.benchmark_id IN (
      SELECT b2.benchmark_id FROM resq_benchmarks AS b2
      JOIN resq_runs AS r2 ON r2.run_id = b2.run_id
      WHERE {FILTER2}
      GROUP BY b2.benchmark_id
      ORDER BY MAX(b2.med_time_ms) DESC LIMIT 12))
ORDER BY r.finished_at, b.benchmark_id
""", "timeseries"),
    Query("benchmark_verdicts", "Benchmark verdicts per run", f"""
SELECT r.finished_at AS time,
       SUM(CASE WHEN b.comparison_class = 'regressed' THEN 1 ELSE 0 END) AS regressed,
       SUM(CASE WHEN b.comparison_class = 'inconclusive' THEN 1 ELSE 0 END) AS inconclusive,
       SUM(CASE WHEN b.comparison_class = 'improved' THEN 1 ELSE 0 END) AS improved,
       SUM(CASE WHEN b.comparison_class = 'stable' THEN 1 ELSE 0 END) AS stable
FROM resq_benchmarks AS b JOIN resq_runs AS r ON r.run_id = b.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
GROUP BY r.finished_at ORDER BY r.finished_at
""", "timeseries"),
    Query("diagnostics_trend", "Framework diagnostics per run", f"""
SELECT r.finished_at AS time,
       SUM(CASE WHEN d.severity = 'error' THEN 1 ELSE 0 END) AS errors,
       SUM(CASE WHEN d.severity = 'warning' THEN 1 ELSE 0 END) AS warnings
FROM resq_diagnostics AS d JOIN resq_runs AS r ON r.run_id = d.run_id
WHERE {FILTER} /*+timefilter:r.finished_at*/
GROUP BY r.finished_at ORDER BY r.finished_at
""", "timeseries"),
    Query("deployment_host", "Branch/deployment/host correlation", f"""
SELECT r.finished_at AS time, r.service, r.environment, r.deployment_id,
       r.artifact_digest, r.vcs_sha, r.vcs_branch, r.hostname, r.q_version,
       r.os, r.ci_provider, r.ci_pipeline_id, r.fail_count, r.error_count
FROM resq_runs AS r WHERE {FILTER} /*+timefilter:r.finished_at*/
ORDER BY r.finished_at DESC
"""),
    Query("qversion_annotations", "q build annotations", f"""
SELECT MIN(r.finished_at) AS time,
       'q ' || r.q_version || ' / ' || r.os AS text
FROM resq_runs AS r WHERE {FILTER}
GROUP BY r.q_version, r.os ORDER BY time
"""),
    Query("deploy_annotations", "Deployment annotations", f"""
SELECT MIN(r.finished_at) AS time,
       'deploy ' || r.deployment_id || ' (' || r.vcs_branch || ' @ ' ||
       SUBSTR(r.vcs_sha, 1, 8) || ')' AS text
FROM resq_runs AS r
WHERE {FILTER} AND r.deployment_id <> ''
GROUP BY r.deployment_id, r.vcs_branch, r.vcs_sha
ORDER BY time
"""),
    Query("coverage_context", "Coverage by test context", f"""
SELECT r.finished_at AS time, c.context_id, c.test_id, t.status, m.kind,
       SUM(m.hits) AS hits
FROM resq_coverage_contexts AS c
JOIN resq_runs AS r ON r.run_id = c.run_id
LEFT JOIN resq_tests AS t ON t.run_id = c.run_id AND t.test_id = c.test_id
JOIN resq_coverage_context_metrics AS m
  ON m.coverage_context_key = c.coverage_context_key
WHERE {FILTER}
GROUP BY r.finished_at, c.context_id, c.test_id, t.status, m.kind
ORDER BY r.finished_at, c.context_id, m.kind
"""),
)

QUERY_BY_KEY = {query.key: query for query in QUERIES}


SQL_TYPES = {
    "sqlite": {"text": "TEXT", "timestamp": "TEXT", "real": "REAL", "integer": "INTEGER", "boolean": "INTEGER", "json": "TEXT"},
    "postgres": {"text": "TEXT", "timestamp": "TIMESTAMPTZ", "real": "DOUBLE PRECISION", "integer": "BIGINT", "boolean": "BOOLEAN", "json": "JSONB"},
}


def ddl_statements(dialect: str) -> list[str]:
    if dialect not in SQL_TYPES:
        raise ValueError(f"unsupported SQL dialect: {dialect}")
    statements: list[str] = []
    for table in TABLES:
        definitions = [
            f"  {column.name} {SQL_TYPES[dialect][column.kind]}"
            + ("" if column.nullable else " NOT NULL")
            for column in table.columns
        ]
        definitions.append(
            f"  raw_payload {SQL_TYPES[dialect]['json']} NOT NULL"
        )
        definitions.append(f"  PRIMARY KEY ({', '.join(table.primary_key)})")
        for foreign in table.foreign_keys:
            target = TABLE_BY_SOURCE[foreign.target_table]
            definitions.append(
                f"  FOREIGN KEY ({', '.join(foreign.columns)}) REFERENCES "
                f"{target.name} ({', '.join(foreign.target_columns)})"
            )
        statements.append(
            f"CREATE TABLE IF NOT EXISTS {table.name} (\n"
            + ",\n".join(definitions) + "\n)"
        )
    return statements


def insert_statement(table: Table, dialect: str) -> str:
    names = [column.name for column in table.columns] + ["raw_payload"]
    if dialect == "sqlite":
        placeholders = ["?"] * len(names)
    elif dialect == "postgres":
        placeholders = [
            "%s::jsonb" if name == "raw_payload" or column.kind == "json" else "%s"
            for name, column in zip(names, (*table.columns, Column("raw_payload", "json")))
        ]
    else:
        raise ValueError(f"unsupported SQL dialect: {dialect}")
    return f"INSERT INTO {table.name} ({', '.join(names)}) VALUES ({', '.join(placeholders)})"


def row_values(table: Table, row: dict[str, Any]) -> tuple[Any, ...]:
    values: list[Any] = []
    for column in table.columns:
        value = row.get(column.source)
        if value is None and not column.nullable:
            raise ValueError(f"{table.source}.{column.source}: required SQL projection is absent")
        if column.kind == "json":
            value = json.dumps(value, ensure_ascii=False, sort_keys=True, allow_nan=False)
        values.append(value)
    values.append(json.dumps(row, ensure_ascii=False, sort_keys=True, allow_nan=False))
    return tuple(values)


def validate_payload(payload: dict[str, Any]) -> None:
    if payload.get("schemaVersion") != 2 or payload.get("kind") != "resq-ingestion-tables":
        raise ValueError("expected resQ normalized table contract v2")
    tables = payload.get("tables")
    if not isinstance(tables, dict) or set(tables) != set(TABLE_BY_SOURCE):
        raise ValueError("normalized table inventory differs from SQL contract")
    for table in TABLES:
        rows = tables[table.source]
        if not isinstance(rows, list):
            raise ValueError(f"tables.{table.source}: expected array")
        for row in rows:
            if not isinstance(row, dict):
                raise ValueError(f"tables.{table.source}: expected row objects")
            row_values(table, row)


def execute_ddl(connection: Any, dialect: str) -> None:
    if dialect == "sqlite":
        connection.execute("PRAGMA foreign_keys = ON")
        with connection:
            for statement in ddl_statements(dialect):
                connection.execute(statement)
        return
    with connection.transaction():
        with connection.cursor() as cursor:
            for statement in ddl_statements(dialect):
                cursor.execute(statement)


def load_payload(connection: Any, dialect: str, payload: dict[str, Any]) -> None:
    validate_payload(payload)
    if dialect == "sqlite":
        connection.execute("PRAGMA foreign_keys = ON")
        with connection:
            for table in TABLES:
                statement = insert_statement(table, dialect)
                connection.executemany(
                    statement,
                    [row_values(table, row) for row in payload["tables"][table.source]],
                )
        return
    if dialect != "postgres":
        raise ValueError(f"unsupported SQL dialect: {dialect}")
    with connection.transaction():
        with connection.cursor() as cursor:
            for table in TABLES:
                statement = insert_statement(table, dialect)
                cursor.executemany(
                    statement,
                    [row_values(table, row) for row in payload["tables"][table.source]],
                )


def query_sql(query: Query, dialect: str) -> str:
    sql = query.sql.strip()
    # The time-scope marker keeps one executable statement per query: Grafana
    # expands it to its dashboard time range, every other dialect runs the
    # statement unscoped (tests load bounded fixtures).
    if dialect in ("grafana", "alert"):
        sql = re.sub(r"/\*\+timefilter:([a-z0-9_.]+)\*/", r"AND $__timeFilter(\1)", sql)
    else:
        sql = re.sub(r"\s*/\*\+timefilter:[a-z0-9_.]+\*/", "", sql)
    names = "|".join(FILTER_PARAMETERS)
    if dialect == "sqlite":
        return sql
    if dialect == "postgres":
        return re.sub(rf":({names})\b", r"%(\1)s", sql)
    if dialect == "grafana":
        return re.sub(rf":({names})\b", r"${\1:sqlstring}", sql)
    if dialect == "alert":
        # Alert rules evaluate without dashboard variables: unfiltered scope.
        return re.sub(rf":({names})\b", "''", sql)
    if dialect == "psql":
        return re.sub(rf":({names})\b", r":'\1'", sql)
    raise ValueError(f"unsupported query dialect: {dialect}")


def execute_queries(connection: Any, dialect: str, parameters: dict[str, str]) -> dict[str, list[Any]]:
    results: dict[str, list[Any]] = {}
    for query in QUERIES:
        if dialect == "sqlite":
            rows = connection.execute(query_sql(query, dialect), parameters).fetchall()
        else:
            with connection.cursor() as cursor:
                cursor.execute(query_sql(query, dialect), parameters)
                rows = cursor.fetchall()
        results[query.key] = list(rows)
    return results


def referenced_sources() -> dict[str, set[str]]:
    return {
        table.source: {column.source for column in table.columns}
        for table in TABLES
    }


def all_sql_names() -> Iterable[str]:
    for table in TABLES:
        yield table.name
        yield from (column.name for column in table.columns)
