#!/usr/bin/env python3
"""Preview or recoverably prune obsolete snapshots from a complete resQ manifest."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class PruneError(RuntimeError):
    pass


def has_symlink_component(path: Path) -> bool:
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.is_symlink():
            return True
    return False


def load_manifest(path: Path) -> dict[str, Any]:
    document = json.loads(path.read_text(encoding="utf-8"))
    required = {
        "schemaVersion", "kind", "enabled", "complete", "completenessReasons",
        "roots", "entries", "counts", "gate",
    }
    if not isinstance(document, dict) or not required.issubset(document):
        raise PruneError("invalid snapshot manifest")
    if document["schemaVersion"] != 1 or document["kind"] != "resq-snapshot-inventory":
        raise PruneError("unsupported snapshot manifest schema")
    if not document["enabled"] or not document["complete"]:
        raise PruneError("refusing to prune from a disabled or partial inventory")
    return document


def safe_source(entry: dict[str, Any]) -> tuple[Path, Path]:
    if entry.get("status") != "obsolete":
        raise PruneError("only obsolete entries may be pruned")
    source = Path(str(entry.get("absolutePath", "")))
    root = Path(str(entry.get("absoluteRoot", "")))
    if not source.is_absolute() or not root.is_absolute():
        raise PruneError("manifest must carry absolute source and root paths")
    if has_symlink_component(root) or has_symlink_component(source):
        raise PruneError(f"refusing symlink snapshot path: {source}")
    try:
        relative = source.relative_to(root)
    except ValueError as exc:
        raise PruneError(f"snapshot escapes validated root: {source}") from exc
    if len(relative.parts) != 1 or relative.name in {"", ".", ".."}:
        raise PruneError(f"snapshot is not a direct root child: {source}")
    suffix = ".snap" if entry.get("backend") == "binary" else ".snap.txt"
    if not source.name.endswith(suffix):
        raise PruneError(f"snapshot extension disagrees with backend: {source}")
    return source, relative


def prune(manifest: Path, trash_root: Path, *, write: bool) -> dict[str, Any]:
    document = load_manifest(manifest)
    obsolete = [entry for entry in document["entries"] if entry.get("status") == "obsolete"]
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    batch = trash_root.resolve() / stamp
    operations: list[dict[str, Any]] = []
    for entry in obsolete:
        source, relative = safe_source(entry)
        backend = str(entry.get("backend", "unknown"))
        destination = batch / backend / relative
        state = "missing" if not source.exists() else "planned"
        if source.exists() and not source.is_file():
            raise PruneError(f"snapshot source is not a regular file: {source}")
        operations.append({
            "backend": backend, "source": str(source),
            "destination": str(destination), "state": state,
        })
    if write:
        for operation in operations:
            if operation["state"] == "missing":
                continue
            source = Path(operation["source"])
            destination = Path(operation["destination"])
            if destination.exists():
                raise PruneError(f"refusing to overwrite trash entry: {destination}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
            operation["state"] = "moved"
        batch.mkdir(parents=True, exist_ok=True)
        audit = {
            "schemaVersion": 1, "kind": "resq-snapshot-prune",
            "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "sourceManifest": str(manifest.resolve()), "operations": operations,
        }
        temporary = batch / f"prune.json.tmp.{os.getpid()}"
        temporary.write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, batch / "prune.json")
    return {"write": write, "batch": str(batch), "operations": operations}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--trash-root", type=Path, default=Path(".resq/trash/snapshots"))
    parser.add_argument("--write", action="store_true", help="perform the recoverable moves")
    args = parser.parse_args()
    try:
        result = prune(args.manifest, args.trash_root, write=args.write)
    except (OSError, json.JSONDecodeError, PruneError) as exc:
        print(f"snapshot prune refused: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2))
    if not args.write:
        print("DRY RUN: no snapshots moved; repeat with --write after review", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
