#!/usr/bin/env python3
"""Validate a resQ run, normalize it, and load it in one SQL transaction."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any

from ingestion_contract import execute_ddl, load_payload
from resq_to_tables import read_json, table_contract


def ingest_postgres(dsn: str, payload: dict[str, Any]) -> None:
    try:
        import psycopg  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError(
            "PostgreSQL ingestion requires psycopg 3 (install 'psycopg[binary]')"
        ) from exc
    connection = None
    try:
        connection = psycopg.connect(dsn)
        execute_ddl(connection, "postgres")
        load_payload(connection, "postgres", payload)
    except psycopg.Error as exc:
        raise RuntimeError(f"PostgreSQL load failed: {exc}") from exc
    finally:
        if connection is not None:
            connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="full/results/telemetry resQ report-v2 JSON")
    parser.add_argument("--coverage", type=Path, help="optional detailed coverage.json")
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--sqlite", type=Path, help="SQLite database path")
    destination.add_argument("--postgres-dsn", help="psycopg connection string")
    parser.add_argument("--tables-out", type=Path, help="retain normalized table-v2 JSON")
    args = parser.parse_args()
    connection: Any | None = None
    try:
        report = read_json(args.report)
        coverage = read_json(args.coverage) if args.coverage else None
        payload = table_contract(report, coverage)
        if args.tables_out:
            args.tables_out.parent.mkdir(parents=True, exist_ok=True)
            args.tables_out.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                encoding="utf-8",
            )
        if args.sqlite:
            args.sqlite.parent.mkdir(parents=True, exist_ok=True)
            connection = sqlite3.connect(args.sqlite)
            dialect = "sqlite"
            execute_ddl(connection, dialect)
            load_payload(connection, dialect, payload)
        else:
            dialect = "postgres"
            ingest_postgres(args.postgres_dsn, payload)
    except (
        OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError,
        sqlite3.DatabaseError,
    ) as error:
        print(f"resQ ingestion failed: {error}", file=sys.stderr)
        return 1
    finally:
        if connection is not None:
            connection.close()
    print(f"loaded run {payload['source']['runId']} into {dialect}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
