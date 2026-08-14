#!/usr/bin/env python3
"""Migrate resQ identity-bearing state from one report generation to another.

The source and destination reports are the mapping proof.  Migration succeeds
only when every semantic test/case key and every referenced state ID has one
unambiguous old/new pairing.  The source state is never modified.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
from pathlib import Path
from typing import Any


CURRENT_ALGORITHM = "resq-test-case-id-v3"
CURRENT_STATE_VERSION = 2


class MigrationError(RuntimeError):
    """Raised when the supplied reports do not prove a safe identity mapping."""


def read_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise MigrationError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise MigrationError(f"{label} {path} must contain a JSON object")
    return value


def manifest(report: dict[str, Any], label: str) -> dict[str, Any]:
    value = report.get("manifest")
    if not isinstance(value, dict) or not isinstance(value.get("tests"), list):
        raise MigrationError(f"{label} report has no execution manifest")
    algorithm = value.get("identityAlgorithm")
    if not isinstance(algorithm, str) or not algorithm:
        raise MigrationError(f"{label} report has no identity algorithm")
    return value


def frozen(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def execution_key(entry: dict[str, Any]) -> tuple[Any, ...]:
    return (
        entry.get("file"), entry.get("suite"), entry.get("description"),
        entry.get("kind"), frozen(entry.get("parameters")),
        frozen(entry.get("tags")),
    )


def parent_key(entry: dict[str, Any]) -> tuple[Any, ...]:
    return entry.get("file"), entry.get("suite"), entry.get("description")


def indexed(
    entries: list[Any], key_fn: Any, id_field: str, label: str,
) -> dict[tuple[Any, ...], str]:
    result: dict[tuple[Any, ...], str] = {}
    for position, raw in enumerate(entries):
        if not isinstance(raw, dict):
            raise MigrationError(f"{label} manifest entry {position} is not an object")
        identifier = raw.get(id_field)
        if not isinstance(identifier, str) or not identifier:
            raise MigrationError(f"{label} manifest entry {position} has no {id_field}")
        key = key_fn(raw)
        prior = result.get(key)
        if prior is not None and prior != identifier:
            raise MigrationError(
                f"{label} manifest has an ambiguous semantic key for {id_field}"
            )
        result[key] = identifier
    return result


def pair_maps(old: dict[str, Any], new: dict[str, Any]) -> tuple[dict[str, str], dict[str, Any]]:
    old_manifest = manifest(old, "old")
    new_manifest = manifest(new, "new")
    if new_manifest.get("identityAlgorithm") != CURRENT_ALGORITHM:
        raise MigrationError(
            f"new report must use {CURRENT_ALGORITHM}, got "
            f"{new_manifest.get('identityAlgorithm')!r}"
        )
    codec = new_manifest.get("identityCodec")
    if not isinstance(codec, dict) or not codec:
        raise MigrationError("new report has no identity codec envelope")

    old_entries = old_manifest["tests"]
    new_entries = new_manifest["tests"]
    old_exec = indexed(old_entries, execution_key, "executionId", "old")
    new_exec = indexed(new_entries, execution_key, "executionId", "new")
    if set(old_exec) != set(new_exec):
        missing = len(set(old_exec) - set(new_exec))
        added = len(set(new_exec) - set(old_exec))
        raise MigrationError(
            f"report inventories differ ({missing} old keys missing, {added} new keys added)"
        )

    old_parent = indexed(old_entries, parent_key, "testId", "old")
    new_parent = indexed(new_entries, parent_key, "testId", "new")
    if set(old_parent) != set(new_parent):
        raise MigrationError("report parent-test inventories differ")

    mapping: dict[str, str] = {}
    for key, old_id in old_exec.items():
        new_id = new_exec[key]
        prior = mapping.get(old_id)
        if prior is not None and prior != new_id:
            raise MigrationError(f"old execution ID {old_id!r} maps ambiguously")
        mapping[old_id] = new_id
    for key, old_id in old_parent.items():
        new_id = new_parent[key]
        prior = mapping.get(old_id)
        if prior is not None and prior != new_id:
            raise MigrationError(f"old test ID {old_id!r} maps ambiguously")
        mapping[old_id] = new_id
    return mapping, copy.deepcopy(codec)


def map_id(identifier: Any, mapping: dict[str, str], context: str) -> str:
    if not isinstance(identifier, str) or not identifier:
        raise MigrationError(f"{context} must be a non-empty string")
    try:
        return mapping[identifier]
    except KeyError as exc:
        raise MigrationError(f"{context} {identifier!r} has no proven mapping") from exc


def migrate_state(
    state: dict[str, Any], mapping: dict[str, str], codec: dict[str, Any],
) -> dict[str, Any]:
    migrated = copy.deepcopy(state)
    kind = migrated.get("kind")
    if "failedTestIds" in migrated:
        ids = migrated["failedTestIds"]
        if not isinstance(ids, list):
            raise MigrationError("rerun failedTestIds must be an array")
        migrated["failedTestIds"] = [
            map_id(value, mapping, f"failedTestIds[{index}]")
            for index, value in enumerate(ids)
        ]
    elif kind == "resq-flake-history":
        rows = migrated.get("tests")
        if not isinstance(rows, list):
            raise MigrationError("flake history tests must be an array")
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                raise MigrationError(f"flake history test {index} must be an object")
            row["testId"] = map_id(row.get("testId"), mapping, f"tests[{index}].testId")
    elif kind == "resq-quarantine-manifest":
        rows = migrated.get("entries")
        if not isinstance(rows, list):
            raise MigrationError("quarantine entries must be an array")
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                raise MigrationError(f"quarantine entry {index} must be an object")
            row["testId"] = map_id(row.get("testId"), mapping, f"entries[{index}].testId")
    elif kind == "resq-quarantine-proposals":
        rows = migrated.get("proposals")
        if not isinstance(rows, list):
            raise MigrationError("quarantine proposals must be an array")
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                raise MigrationError(f"quarantine proposal {index} must be an object")
            row["testId"] = map_id(row.get("testId"), mapping, f"proposals[{index}].testId")
            suggested = row.get("suggestedEntry")
            if isinstance(suggested, dict) and "testId" in suggested:
                suggested["testId"] = map_id(
                    suggested["testId"], mapping,
                    f"proposals[{index}].suggestedEntry.testId",
                )
    else:
        raise MigrationError("unrecognized identity-bearing state document")

    migrated["schemaVersion"] = CURRENT_STATE_VERSION
    migrated["identityAlgorithm"] = CURRENT_ALGORITHM
    migrated["identityCodec"] = codec
    return migrated


def migrate(old_report: Path, new_report: Path, state_path: Path, output: Path) -> dict[str, Any]:
    if output.resolve() == state_path.resolve():
        raise MigrationError("output must differ from the source state path")
    if output.exists():
        raise MigrationError(f"output already exists: {output}")
    mapping, codec = pair_maps(
        read_object(old_report, "old report"), read_object(new_report, "new report")
    )
    migrated = migrate_state(read_object(state_path, "state"), mapping, codec)
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(migrated, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as target:
        target.write(payload)
        target.flush()
        os.fsync(target.fileno())
    return migrated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old-report", required=True, type=Path)
    parser.add_argument("--new-report", required=True, type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        migrated = migrate(args.old_report, args.new_report, args.state, args.output)
    except (MigrationError, OSError) as exc:
        print(f"identity state migration failed: {exc}", file=sys.stderr)
        return 2
    print(
        f"migrated {args.state} -> {args.output} using "
        f"{migrated['identityAlgorithm']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
