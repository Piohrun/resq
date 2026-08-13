#!/usr/bin/env python3
"""End-to-end proof of snapshot inventory, gates, merging, pruning, and safety."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from merge_shards import merge
from validate_report import validate


ROOT = Path(__file__).resolve().parents[1]
PRUNER = ROOT / "tools/prune_snapshots.py"


def write_fixture(root: Path) -> Path:
    tests = root / "tests"
    tests.mkdir()
    common = (
        '.tst.setSnapDir getenv `RESQ_SNAPSHOT_BINARY; '
        '.tst.setSnapTxtDir getenv `RESQ_SNAPSHOT_TEXT; '
    )
    (tests / "test_a.q").write_text(
        common + '.resq.snapshot.declare[`text;"dynamic-extra"]; '
        '.tst.desc["snapshot a"]{should["binary"]{(`a`b!1 2) mustmatchs "alpha"; must[1b;"snapshot reached"];};};\n',
        encoding="utf-8",
    )
    (tests / "test_b.q").write_text(
        common + '.tst.desc["snapshot b"]{should["text"]{(`x`y!3 4) mustmatchst "beta"; must[1b;"snapshot reached"];};};\n',
        encoding="utf-8",
    )
    return tests


def run(
    q: str, work: Path, tests: Path, name: str, flags: list[str], expected: int,
) -> tuple[dict[str, Any], subprocess.CompletedProcess[str], Path]:
    out = work / name
    env = dict(os.environ)
    env.update(
        QBIN=q,
        RESQ_SNAPSHOT_BINARY=str(work / "binary"),
        RESQ_SNAPSHOT_TEXT=str(work / "text"),
    )
    command = [
        str(ROOT / "bin/resq"), "test", str(tests), "-quiet", "-json",
        "-outDir", str(out), "-state-file", str(work / "state.json"),
        "-flake-history", str(work / "flake.json"),
        "-quarantine-file", str(work / "quarantine.json"), *flags,
    ]
    completed = subprocess.run(
        command, cwd=ROOT, env=env, text=True, capture_output=True,
        check=False, timeout=90,
    )
    if completed.returncode != expected:
        raise AssertionError(
            f"{name}: expected exit {expected}, got {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    report = json.loads((out / "test-results.json").read_text(encoding="utf-8"))
    validate(report)
    manifest = json.loads((out / "snapshot-manifest.json").read_text(encoding="utf-8"))
    if manifest != report["snapshotInventory"]:
        raise AssertionError(f"{name}: standalone and embedded inventories differ")
    return report, completed, out


def status_map(report: dict[str, Any]) -> dict[str, str]:
    return {
        f"{entry['backend']}:{entry['name']}": entry["status"]
        for entry in report["snapshotInventory"]["entries"]
    }


def invoke_pruner(manifest: Path, trash: Path, write: bool = False) -> subprocess.CompletedProcess[str]:
    command = [str(PRUNER), str(manifest), "--trash-root", str(trash)]
    if write:
        command.append("--write")
    return subprocess.run(command, text=True, capture_output=True, check=False, timeout=30)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="resq-snapshots-") as temp:
        work = Path(temp)
        tests = write_fixture(work)
        binary = work / "binary"
        text = work / "text"
        binary.mkdir()
        text.mkdir()
        (text / "dynamic-extra.snap.txt").write_text("declared", encoding="utf-8")
        (binary / "obsolete.snap").write_bytes(b"obsolete")

        # First run creates the two executed snapshots. The second strict run is
        # the authoritative complete audit used for every lifecycle assertion.
        run(args.q, work, tests, "01-create", ["-snapshot-audit"], 0)
        audit, _, audit_out = run(args.q, work, tests, "02-audit", ["-strict", "-snapshot-audit"], 0)
        inventory = audit["snapshotInventory"]
        if not inventory["complete"] or inventory["completenessReasons"]:
            raise AssertionError("an unfiltered successful run must publish a complete inventory")
        states = status_map(audit)
        expected = {
            "binary:alpha": "referenced", "text:beta": "referenced",
            "text:dynamic-extra": "referenced", "binary:obsolete": "obsolete",
        }
        if states != expected:
            raise AssertionError(f"unexpected complete inventory: {states!r}")
        snapshot_events = [event for event in audit["events"] if event["type"] == "snapshots.audited"]
        if len(snapshot_events) != 1 or snapshot_events[0]["payload"] != inventory:
            raise AssertionError("snapshot event/report/manifest telemetry differs")

        isolated, _, _ = run(
            args.q, work, tests, "02b-isolated-audit",
            ["-strict", "-snapshot-audit", "-isolate", "-isolateWorkers", "2"], 0,
        )
        if status_map(isolated) != expected or not isolated["snapshotInventory"]["complete"]:
            raise AssertionError("isolate parent did not reconstruct the normal snapshot inventory")

        gated, _, _ = run(args.q, work, tests, "03-gate", ["-strict", "-snapshot-gate"], 1)
        if gated["snapshotInventory"]["gate"]["reasons"] != ["obsolete-snapshots"]:
            raise AssertionError("snapshot gate did not fail specifically on obsolete data")

        partial, _, _ = run(
            args.q, work, tests, "04-filtered", ["-strict", "-snapshot-audit", "-only", "snapshot a"], 0
        )
        if partial["snapshotInventory"]["complete"] or "filtered" not in partial["snapshotInventory"]["completenessReasons"]:
            raise AssertionError("filtered audit was not explicitly partial")
        if "unverified" not in status_map(partial).values():
            raise AssertionError("partial audit mislabeled unobserved stored data as obsolete")
        partial_gate, _, _ = run(
            args.q, work, tests, "05-filtered-gate", ["-strict", "-snapshot-gate", "-only", "snapshot a"], 1
        )
        if "inventory-incomplete" not in partial_gate["snapshotInventory"]["gate"]["reasons"]:
            raise AssertionError("CI gate accepted a partial inventory")

        shard_reports = []
        for index in range(2):
            report, _, out = run(
                args.q, work, tests, f"06-shard-{index}",
                ["-strict", "-snapshot-audit", "-shard-index", str(index), "-shard-count", "2"], 0,
            )
            if report["snapshotInventory"]["complete"]:
                raise AssertionError("native shard must publish a partial inventory")
            shard_reports.append(out / "test-results.json")
        merged, passed = merge(shard_reports, work / "merged")
        if not passed or not merged["snapshotInventory"]["complete"]:
            raise AssertionError("complete shard set did not reconstruct a complete snapshot inventory")
        if status_map(merged) != expected:
            raise AssertionError("merged snapshot classifications differ from unsharded audit")

        manifest = audit_out / "snapshot-manifest.json"
        trash = work / "trash"
        preview = invoke_pruner(manifest, trash)
        if preview.returncode or not (binary / "obsolete.snap").exists() or "DRY RUN" not in preview.stderr:
            raise AssertionError("pruner dry run mutated data or failed")
        written = invoke_pruner(manifest, trash, write=True)
        if written.returncode or (binary / "obsolete.snap").exists():
            raise AssertionError(f"recoverable prune failed: {written.stderr}")
        if len(list(trash.rglob("obsolete.snap"))) != 1:
            raise AssertionError("obsolete snapshot was not preserved exactly once in trash")
        repeated = invoke_pruner(manifest, trash, write=True)
        if repeated.returncode:
            raise AssertionError("pruning an already-moved source must be idempotent")
        clean_gate, _, _ = run(args.q, work, tests, "07-clean-gate", ["-strict", "-snapshot-gate"], 0)
        if clean_gate["snapshotInventory"]["counts"]["obsolete"]:
            raise AssertionError("post-prune gate still sees obsolete snapshots")

        outside = work / "outside.snap"
        outside.write_bytes(b"untouched")
        symlink = binary / "evil.snap"
        symlink.symlink_to(outside)
        hostile_manifest = json.loads(manifest.read_text(encoding="utf-8"))
        hostile_manifest["entries"][0].update(
            status="obsolete", absolutePath=str(outside), absoluteRoot=str(binary)
        )
        hostile_path = work / "hostile.json"
        hostile_path.write_text(json.dumps(hostile_manifest), encoding="utf-8")
        refused = invoke_pruner(hostile_path, trash, write=True)
        if refused.returncode != 2 or outside.read_bytes() != b"untouched":
            raise AssertionError("pruner did not refuse a manifest path outside its validated root")
        symlink_manifest = json.loads(manifest.read_text(encoding="utf-8"))
        template = dict(symlink_manifest["entries"][0])
        template.update(
            backend="binary", name="evil", path=str(symlink), root=str(binary),
            absoluteRoot=str(binary), absolutePath=str(symlink), status="obsolete",
            referenced=False, declared=False, dynamic=False, exists=True, unsafe=True,
            executionIds=[], observedStatuses=[],
        )
        symlink_manifest["entries"] = [template]
        symlink_path = work / "symlink.json"
        symlink_path.write_text(json.dumps(symlink_manifest), encoding="utf-8")
        refused = invoke_pruner(symlink_path, trash, write=True)
        if refused.returncode != 2 or outside.read_bytes() != b"untouched":
            raise AssertionError("pruner followed a snapshot symlink")

    print(
        "resQ snapshot verification passed: complete/partial inventories, dynamic declarations, "
        "normal/isolate parity, CI gate, event/JSON parity, shard merge, "
        "dry-run/recoverable/idempotent prune, and hostile path safety"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
