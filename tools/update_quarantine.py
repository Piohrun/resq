#!/usr/bin/env python3
"""Review resQ flake proposals and explicitly update a quarantine manifest.

Without --write this is a read-only preview. The runtime never calls this tool
and never promotes a suspect test into quarantine on its own.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return value


def load_proposals(path: Path) -> dict[str, Any]:
    document = load_json(path)
    if document.get("schemaVersion") != SCHEMA_VERSION or document.get("kind") != "resq-quarantine-proposals":
        raise ValueError(f"{path}: expected resQ quarantine proposals v2; migrate legacy identity state first")
    if not isinstance(document.get("identityAlgorithm"), str) or not isinstance(
        document.get("identityCodec"), dict
    ):
        raise ValueError(f"{path}: identity algorithm/codec envelope is missing")
    proposals = document.get("proposals")
    if not isinstance(proposals, list):
        raise ValueError(f"{path}: proposals must be an array")
    for index, proposal in enumerate(proposals):
        if not isinstance(proposal, dict) or not isinstance(proposal.get("testId"), str):
            raise ValueError(f"{path}: malformed proposal at index {index}")
        if proposal.get("state") != "suspect":
            raise ValueError(f"{path}: proposal {proposal.get('testId')} is not suspect")
    return document


def load_manifest(path: Path, algorithm: str, codec: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return {
            "schemaVersion": SCHEMA_VERSION,
            "identityAlgorithm": algorithm,
            "identityCodec": codec,
            "kind": "resq-quarantine-manifest",
            "updatedAt": "",
            "entries": [],
        }
    document = load_json(path)
    if document.get("schemaVersion") != SCHEMA_VERSION or document.get("kind") != "resq-quarantine-manifest":
        raise ValueError(f"{path}: expected resQ quarantine manifest v2; migrate legacy identity state first")
    if document.get("identityAlgorithm") != algorithm or document.get("identityCodec") != codec:
        raise ValueError(f"{path}: manifest identity algorithm/codec differs from the proposals")
    if not isinstance(document.get("entries"), list):
        raise ValueError(f"{path}: entries must be an array")
    return document


def parse_expiry(value: str) -> str:
    parsed = date.fromisoformat(value)
    if parsed < date.today():
        raise ValueError("--expires must not be in the past")
    return parsed.isoformat()


def atomic_write(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def build_manifest(args: argparse.Namespace) -> dict[str, Any]:
    proposal_document = load_proposals(args.proposals)
    proposals = proposal_document["proposals"]
    selected = set(args.test_id or [proposal["testId"] for proposal in proposals])
    available = {proposal["testId"]: proposal for proposal in proposals}
    missing = sorted(selected - available.keys())
    if missing:
        raise ValueError(f"requested test IDs are absent from proposals: {', '.join(missing)}")
    manifest = load_manifest(
        args.manifest,
        proposal_document["identityAlgorithm"],
        proposal_document["identityCodec"],
    )
    existing = {
        entry.get("testId"): entry
        for entry in manifest["entries"]
        if isinstance(entry, dict) and isinstance(entry.get("testId"), str)
    }
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for test_id in sorted(selected):
        proposal = available[test_id]
        old = existing.get(test_id, {})
        existing[test_id] = {
            "testId": test_id,
            "owner": args.owner,
            "reason": args.reason,
            "evidence": proposal.get("evidence", {}),
            "issue": args.issue,
            "createdAt": old.get("createdAt") or now,
            "expiresAt": args.expires,
        }
    manifest["updatedAt"] = now
    manifest["entries"] = [existing[test_id] for test_id in sorted(existing)]
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposals", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--reason", required=True)
    parser.add_argument("--issue", required=True)
    parser.add_argument("--expires", required=True, type=parse_expiry)
    parser.add_argument("--test-id", action="append", help="select one proposal; repeatable")
    parser.add_argument("--write", action="store_true", help="atomically replace the manifest")
    args = parser.parse_args()
    try:
        document = build_manifest(args)
        rendered = json.dumps(document, indent=2, sort_keys=True)
        if args.write:
            atomic_write(args.manifest, document)
            print(f"updated quarantine manifest: {args.manifest}")
        else:
            print(rendered)
            print("DRY RUN: manifest was not changed; pass --write after review", file=sys.stderr)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        print(f"quarantine update refused: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
