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


FILTER = "(:service = '' OR r.service = :service) AND (:environment = '' OR r.environment = :environment)"
QUERIES: tuple[Query, ...] = (
    Query("services", "Services", "SELECT DISTINCT service AS __text, service AS __value FROM resq_runs WHERE service <> '' ORDER BY service"),
    Query("environments", "Environments", "SELECT DISTINCT environment AS __text, environment AS __value FROM resq_runs WHERE environment <> '' AND (:service = '' OR service = :service) ORDER BY environment"),
    Query("pass_fail_rate", "Pass/fail rate", f"""
SELECT r.finished_at AS time, r.service, r.environment,
       CASE WHEN r.test_count = 0 THEN 100.0 ELSE 100.0 * r.pass_count / r.test_count END AS pass_rate,
       r.fail_count + r.error_count AS failures
FROM resq_runs AS r WHERE {FILTER} ORDER BY r.finished_at
""", "timeseries"),
    Query("run_duration", "Run duration", f"""
SELECT r.finished_at AS time, r.service, r.environment, r.duration_seconds
FROM resq_runs AS r WHERE {FILTER} ORDER BY r.finished_at
""", "timeseries"),
    Query("test_history", "Per-test history", f"""
SELECT r.finished_at AS time, t.test_id, t.case_id, t.suite, t.description,
       t.status, t.duration_seconds, t.file_path
FROM resq_tests AS t JOIN resq_runs AS r ON r.run_id = t.run_id
WHERE {FILTER} ORDER BY r.finished_at, t.test_id, t.case_id
"""),
    Query("benchmark_history", "Benchmark median/classification", f"""
SELECT r.finished_at AS time, b.benchmark_id, b.suite, b.description,
       b.med_time_ms, b.comparison_class
FROM resq_benchmarks AS b JOIN resq_runs AS r ON r.run_id = b.run_id
WHERE {FILTER} ORDER BY r.finished_at, b.benchmark_id
""", "timeseries"),
    Query("coverage_trend", "Coverage basis/completeness", f"""
SELECT r.finished_at AS time, c.function_percent, c.line_percent,
       c.statement_site_percent, c.statement_site_instrumentation_percent,
       c.branch_percent, c.branch_instrumentation_percent
FROM resq_coverage_runs AS c JOIN resq_runs AS r ON r.run_id = c.run_id
WHERE {FILTER} ORDER BY r.finished_at
""", "timeseries"),
    Query("deployment_host", "Branch/deployment/host correlation", f"""
SELECT r.finished_at AS time, r.service, r.environment, r.deployment_id,
       r.artifact_digest, r.vcs_sha, r.vcs_branch, r.hostname, r.q_version,
       r.os, r.ci_provider, r.ci_pipeline_id, r.fail_count, r.error_count
FROM resq_runs AS r WHERE {FILTER} ORDER BY r.finished_at DESC
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
    if dialect == "sqlite":
        return sql
    if dialect == "postgres":
        return re.sub(r":(service|environment)\b", r"%(\1)s", sql)
    if dialect == "grafana":
        return re.sub(r":(service|environment)\b", r"${\1:sqlstring}", sql)
    if dialect == "psql":
        return re.sub(r":(service|environment)\b", r":'\1'", sql)
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
