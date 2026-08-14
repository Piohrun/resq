from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from merge_shards import (  # noqa: E402
    MergeError,
    canonical,
    diagnostic_id,
    lifecycle,
    shard_diagnostic_ids,
    load_report,
    load_reports,
    merge,
    merge_coverage,
    merge_performance,
    summary,
    topology,
    validate_inventory,
    validate_results,
    validate_snapshot_ownership,
    write_lcov,
)
from review_corpus import scale_report  # noqa: E402
from report_profiles import project  # noqa: E402
from tools.tests.test_coverage_contract import artifact, report_coverage  # noqa: E402
from validate_report import validate  # noqa: E402


def shard_documents(count: int = 2, test_count: int = 4, unit: str = "test") -> list[dict]:
    base = scale_report(test_count)
    base.pop("events", None)
    documents: list[dict] = []
    for shard_index in range(count):
        document = copy.deepcopy(base)
        document["run"]["id"] = f"run_{shard_index + 1:032x}"
        selected_ids: list[str] = []
        for index, entry in enumerate(document["manifest"]["tests"]):
            assigned = 0 if unit == "file" else index % count
            entry["assignedShard"] = assigned
            entry["shardKey"] = (
                entry["fileId"] if unit == "file" else entry["executionId"]
            )
            entry["selected"] = assigned == shard_index
            if entry["selected"]:
                selected_ids.append(entry["executionId"])
        rows = [
            row for row in document["tests"]
            if (row["caseId"] or row["testId"]) in selected_ids
        ]
        document["tests"] = rows
        document["summary"] = summary(rows)
        document["run"]["config"].update(
            shardIndex=shard_index, shardCount=count, shardUnit=unit
        )
        document["run"]["selection"]["selectedTestCount"] = len(rows)
        document["run"]["shard"].update(
            index=shard_index,
            count=count,
            unit=unit,
            algorithm=(
                "sorted-index-mod-v1" if unit == "file"
                else "stable-id-weighted-hash-v1"
            ),
            allFileCount=1,
            selectedFileCount=0 if unit == "file" and not rows else 1,
            allUnitCount=1 if unit == "file" else test_count,
            selectedUnitCount=(1 if rows else 0) if unit == "file" else len(rows),
            selectedFiles=["tests/generated/review_scale.q"] if unit != "file" or rows else [],
            selectedExecutionIds=selected_ids,
        )
        document["manifest"]["shard"] = copy.deepcopy(document["run"]["shard"])
        for file_entry in document["manifest"]["files"]:
            file_entry["assignedShard"] = 0 if unit == "file" else -1
            file_entry["selected"] = unit != "file" or shard_index == 0
        document["flake"].update(
            healthy=0, suspect=0, quarantined=0, expired=0,
            insufficient=len(rows), proposalCount=0,
        )
        document["events"] = lifecycle(
            document["run"], document["manifest"], rows, document["summary"],
            {}, document["diagnostics"], document["snapshotInventory"],
            document["benchmarkAnalysis"],
        )
        validate(document)
        documents.append(document)
    return documents


def write_documents(root: Path, documents: list[dict]) -> list[Path]:
    paths: list[Path] = []
    for index, document in enumerate(documents):
        path = root / f"shard-{index}" / "test-results.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(document), encoding="utf-8")
        paths.append(path)
    return paths


class MergerContractTests(unittest.TestCase):
    def test_valid_merge_is_deterministic_and_preserves_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = write_documents(root, shard_documents())
            forward, passed = merge(paths, root / "forward")
            reverse, reverse_passed = merge(list(reversed(paths)), root / "reverse")
            self.assertTrue(passed and reverse_passed)
            self.assertEqual(forward, reverse)
            self.assertEqual(4, forward["summary"]["testCount"])
            self.assertEqual(
                [row["executionId"] for row in forward["manifest"]["tests"]],
                [row["testId"] for row in forward["tests"]],
            )
            self.assertEqual([0, 1], forward["run"]["shard"]["indices"])
            validate(forward)
        for unit in ("file", "test", "case"):
            with self.subTest(unit=unit), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                paths = write_documents(root, shard_documents(unit=unit))
                report, passed = merge(paths, root / "merged")
                self.assertTrue(passed)
                self.assertEqual(unit, report["run"]["shard"]["unit"])
                self.assertEqual(4, report["summary"]["testCount"])
                self.assertTrue(all(row["attemptHistory"] for row in report["tests"]))

    def test_cli_and_loader_fail_closed_on_missing_malformed_and_weak_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(MergeError, "cannot read report"):
                load_report(root / "missing.json")
            malformed = root / "malformed.json"
            malformed.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(MergeError, "cannot read report"):
                load_report(malformed)
            weak = project(scale_report(1), "results")
            weak_path = root / "weak.json"
            weak_path.write_text(json.dumps(weak), encoding="utf-8")
            with self.assertRaisesRegex(MergeError, "full"):
                load_report(weak_path)
            completed = subprocess.run(
                [sys.executable, str(ROOT / "tools/merge_shards.py"), str(malformed),
                 "--out-dir", str(root / "out")],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(2, completed.returncode)
            self.assertIn("shard merge failed", completed.stderr)

    def test_topology_rejects_duplicate_missing_mixed_and_out_of_range_indices(self) -> None:
        documents = shard_documents()
        duplicate = copy.deepcopy(documents)
        duplicate[1]["run"]["shard"]["index"] = 0
        with self.assertRaisesRegex(MergeError, "duplicate shard index"):
            topology(duplicate)
        with self.assertRaisesRegex(MergeError, "incomplete shard union"):
            topology(documents[:1])
        mixed = copy.deepcopy(documents)
        mixed[1]["run"]["shard"]["count"] = 3
        with self.assertRaisesRegex(MergeError, "mixed shard count"):
            topology(mixed)
        out_of_range = copy.deepcopy(documents)
        out_of_range[1]["run"]["shard"]["index"] = 2
        with self.assertRaisesRegex(MergeError, "incomplete shard union"):
            topology(out_of_range)

    def test_merge_rejects_revision_digest_config_and_framework_disagreement(self) -> None:
        mutations = (
            ("revision", lambda d: (
                d["manifest"]["revision"].update(sha="f" * 40),
                d["run"]["vcs"].update(sha="f" * 40),
            ), "revision"),
            ("digest", lambda d: (
                d["manifest"].update(digest="manifest_" + "f" * 32),
                d["events"][1].update(entityId="manifest_" + "f" * 32),
                d["events"][1]["payload"].update(digest="manifest_" + "f" * 32),
            ), "manifest digest"),
            ("config", lambda d: d["run"]["config"].update(strict=False), "effective configuration"),
            ("framework", lambda d: (
                d.update(frameworkVersion="1.8.2"),
                d["run"].update(resqVersion="1.8.2"),
                d["manifest"].update(frameworkVersion="1.8.2"),
                d["events"][0]["payload"].update(frameworkVersion="1.8.2"),
                d["events"][1]["payload"].update(frameworkVersion="1.8.2"),
            ), "framework version"),
        )
        for label, mutate, expected in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                documents = shard_documents()
                mutate(documents[1])
                paths = write_documents(Path(directory), documents)
                with self.assertRaisesRegex(MergeError, expected):
                    merge(paths, Path(directory) / "merged")

    def test_loader_rejects_mixed_identity_generation_before_joining(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = shard_documents()
            documents[1]["manifest"]["identityAlgorithm"] = "resq-test-case-id-v2"
            paths = write_documents(root, documents)
            with self.assertRaisesRegex(MergeError, "mixed identity algorithms"):
                load_reports(paths)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = shard_documents()
            documents[1]["manifest"]["identityCodec"]["qRelease"] = "different"
            paths = write_documents(root, documents)
            with self.assertRaisesRegex(MergeError, "mixed identity codecs"):
                load_reports(paths)

    def test_inventory_results_and_ownership_mutations_are_rejected(self) -> None:
        documents = shard_documents()
        malformed = copy.deepcopy(documents)
        malformed[0]["manifest"]["tests"][0]["executionId"] = ""
        with self.assertRaisesRegex(MergeError, "malformed execution identity"):
            validate_inventory(malformed, "test", 2)

        inventory, expected = validate_inventory(documents, "test", 2)
        missing = copy.deepcopy(documents)
        missing[0]["tests"] = missing[0]["tests"][:-1]
        with self.assertRaisesRegex(MergeError, "incomplete result set"):
            validate_results(missing, expected)
        duplicate = copy.deepcopy(documents)
        duplicate[0]["tests"].append(copy.deepcopy(duplicate[0]["tests"][0]))
        with self.assertRaisesRegex(MergeError, "duplicate result"):
            validate_results(duplicate, expected)

        run_level = copy.deepcopy(documents[0]["tests"][0])
        identity = run_level["testId"]
        coalesced = validate_results(
            [
                {"run": {"shard": {"index": 0}}, "tests": [run_level]},
                {"run": {"shard": {"index": 1}}, "tests": [copy.deepcopy(run_level)]},
            ],
            [{identity}, {identity}],
            {identity},
        )
        self.assertEqual(1, len(coalesced))
        disagreeing = copy.deepcopy(run_level)
        disagreeing["status"] = "fail"
        with self.assertRaisesRegex(MergeError, "run-level result"):
            validate_results(
                [
                    {"run": {"shard": {"index": 0}}, "tests": [run_level]},
                    {"run": {"shard": {"index": 1}}, "tests": [disagreeing]},
                ],
                [{identity}, {identity}],
                {identity},
            )

        rows = [copy.deepcopy(documents[0]["tests"][0]), copy.deepcopy(documents[1]["tests"][0])]
        for row in rows:
            row["snapshots"] = [{"backend": "text", "path": "shared.snap"}]
        with self.assertRaisesRegex(MergeError, "multiple executions"):
            validate_snapshot_ownership(rows)
        benchmark = {"benchmarkId": "benchmark_" + "a" * 32}
        with self.assertRaisesRegex(MergeError, "more than one shard"):
            merge_performance([{"performance": [benchmark]}, {"performance": [benchmark]}])
        ordered = merge_performance([
            {"performance": [{"benchmarkId": "benchmark_" + "b" * 32}]},
            {"performance": [{"benchmarkId": "benchmark_" + "a" * 32}]},
        ])
        self.assertEqual(
            ["benchmark_" + "a" * 32, "benchmark_" + "b" * 32],
            [row["benchmarkId"] for row in ordered],
        )
        self.assertEqual(4, len(inventory))

    def test_incomplete_member_and_complete_coverage_merge_contracts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = shard_documents()
            omitted = documents[0]["tests"].pop()
            documents[0]["summary"] = summary(documents[0]["tests"])
            documents[0]["flake"]["insufficient"] = len(documents[0]["tests"])
            documents[0]["run"]["completion"] = {
                "state": "incomplete", "complete": False, "truncated": True,
                "reason": "failFast", "selectedTestCount": 2, "resultCount": 1,
                "missingExecutionIds": [omitted["testId"]],
            }
            documents[0]["events"] = lifecycle(
                documents[0]["run"], documents[0]["manifest"], documents[0]["tests"],
                documents[0]["summary"], {}, [], documents[0]["snapshotInventory"],
                documents[0]["benchmarkAnalysis"],
            )
            validate(documents[0])
            paths = write_documents(root, documents)
            with self.assertRaisesRegex(MergeError, "incomplete result set"):
                merge(paths, root / "incomplete")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = shard_documents()
            for document in documents:
                document["coverage"] = report_coverage()
                document["events"] = lifecycle(
                    document["run"], document["manifest"], document["tests"],
                    document["summary"], document["coverage"], [],
                    document["snapshotInventory"], document["benchmarkAnalysis"],
                )
                validate(document)
            paths = write_documents(root, documents)
            for path, document in zip(paths, documents):
                test_id = document["tests"][0]["testId"]
                (path.parent / "coverage.json").write_text(
                    json.dumps(artifact(test_id, document["run"]["id"])), encoding="utf-8"
                )
            report, passed = merge(paths, root / "covered")
            self.assertTrue(passed)
            self.assertEqual(1, report["coverage"]["functionsFound"])
            detail = json.loads((root / "covered/coverage.json").read_text(encoding="utf-8"))
            self.assertEqual(2, len(detail["contextMeasurement"]["contexts"]))

    def test_snapshot_completeness_aggregates_all_shards(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = shard_documents()
            for document in documents:
                document["snapshotInventory"].update(
                    enabled=True, complete=True, completenessReasons=[],
                )
            documents[0]["snapshotInventory"]["counts"]["unverified"] = 2
            documents[1]["snapshotInventory"]["counts"]["unverified"] = 3
            documents[1]["snapshotInventory"].update(
                complete=False, completenessReasons=["interrupted"],
            )
            documents[1]["snapshotInventory"]["gate"] = {
                "enabled": True, "passed": False, "reasons": ["member-incomplete"],
            }
            for document in documents:
                document["events"] = lifecycle(
                    document["run"], document["manifest"], document["tests"],
                    document["summary"], {}, document["diagnostics"],
                    document["snapshotInventory"], document["benchmarkAnalysis"],
                )
                validate(document)
            report, passed = merge(write_documents(root, documents), root / "merged")
            inventory = report["snapshotInventory"]
            self.assertFalse(passed)
            self.assertTrue(inventory["enabled"])
            self.assertFalse(inventory["complete"])
            self.assertEqual(["interrupted"], inventory["completenessReasons"])
            self.assertEqual(5, inventory["counts"]["unverified"])
            self.assertEqual(
                ["incomplete-snapshot-inventory", "member-incomplete"],
                inventory["gate"]["reasons"],
            )

    def test_coverage_presence_and_malformed_detail_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = shard_documents()
            paths = write_documents(root, documents)
            (paths[0].parent / "coverage.json").write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(MergeError, "only part"):
                merge_coverage(paths, documents, root / "partial", "run_" + "a" * 32)
            (paths[1].parent / "coverage.json").write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "coverage artifact"):
                merge_coverage(paths, documents, root / "malformed", "run_" + "a" * 32)

    def test_lcov_distinguishes_zero_edge_from_unexecuted_block(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            coverage = artifact("test_" + "a" * 32)
            file_row = coverage["files"][0]
            executed = file_row["branches"][0]
            unexecuted = copy.deepcopy(executed)
            unexecuted.update(line=4, block=1, edgesHit=0)
            for edge in unexecuted["edges"]:
                edge.update(hits=0, covered=False)
            file_row["branches"] = [executed, unexecuted]
            output = root / "coverage.lcov"
            write_lcov(coverage, output)
            lines = output.read_text(encoding="utf-8").splitlines()
            self.assertIn("SF:src/fixture.q", lines)
            self.assertIn("BRDA:3,0,0,1", lines)
            self.assertIn("BRDA:3,0,1,0", lines)
            self.assertEqual(
                ["BRDA:4,1,0,-", "BRDA:4,1,1,-"],
                [line for line in lines if line.startswith("BRDA:4,1,")],
            )

    def test_python_lifecycle_matches_shared_q_golden(self) -> None:
        golden = json.loads(
            (ROOT / "tests/contracts/lifecycle-v2-golden.json").read_text(encoding="utf-8")
        )
        document = scale_report(1)
        row = document["tests"][0]
        row.update(
            startedAt="2026-08-12T12:00:00.100000Z",
            finishedAt="2026-08-12T12:00:00.101000Z",
        )
        row["attemptHistory"][0].update(
            startedAt=row["startedAt"], finishedAt=row["finishedAt"]
        )
        events = lifecycle(
            document["run"], document["manifest"], document["tests"],
            summary(document["tests"]), {}, [], document["snapshotInventory"],
            document["benchmarkAnalysis"],
        )
        self.assertEqual(golden["singleTestTypes"], [event["type"] for event in events])
        self.assertTrue(all(event["schemaVersion"] == golden["eventSchemaVersion"] for event in events))
        by_type = {event["type"]: event for event in events}
        self.assertEqual(row["startedAt"], by_type["test.started"]["occurredAt"])
        self.assertEqual(row["finishedAt"], by_type["test.finished"]["occurredAt"])
        self.assertEqual(
            sorted(golden["manifestPublishedPayloadKeys"]),
            sorted(by_type["manifest.published"]["payload"]),
        )

    def test_diagnostics_use_their_owning_test_or_run_finish_time(self) -> None:
        document = scale_report(1)
        row = document["tests"][0]
        row.update(
            startedAt="2026-08-12T12:00:00.100000Z",
            finishedAt="2026-08-12T12:00:00.101000Z",
            diagnostics=[{
                "type": "test-probe", "severity": "info", "phase": "execution",
                "message": "test diagnostic", "data": {},
            }],
        )
        run_diagnostic = {
            "type": "run-probe", "severity": "info", "phase": "reporting",
            "message": "run diagnostic", "data": {},
        }
        events = lifecycle(
            document["run"], document["manifest"], [row], summary([row]), {},
            [run_diagnostic], document["snapshotInventory"], document["benchmarkAnalysis"],
        )
        diagnostics = [event for event in events if event["type"] == "diagnostic.recorded"]
        test_event = next(event for event in diagnostics if event["parentId"] == row["testId"])
        run_event = next(event for event in diagnostics if event["parentId"] == document["run"]["id"])
        self.assertEqual(row["finishedAt"], test_event["occurredAt"])
        self.assertEqual(document["run"]["finishedAt"], run_event["occurredAt"])

    def test_shard_owned_diagnostic_events_reuse_q_emitted_ids(self) -> None:
        document = scale_report(1)
        row = document["tests"][0]
        diagnostic = {
            "type": "test-probe", "severity": "info", "phase": "execution",
            "message": "test diagnostic", "data": {"elapsed": 0.123456789123456},
        }
        row["diagnostics"] = [diagnostic]
        q_emitted = "diagnostic_" + "e" * 32
        shard_ids = {
            (row["testId"], canonical(diagnostic)): [q_emitted],
        }
        run_diagnostic = {
            "type": "run-probe", "severity": "info", "phase": "reporting",
            "message": "run diagnostic", "data": {},
        }
        events = lifecycle(
            document["run"], document["manifest"], [row], summary([row]), {},
            [run_diagnostic], document["snapshotInventory"],
            document["benchmarkAnalysis"], shard_ids=shard_ids,
        )
        recorded = [e for e in events if e["type"] == "diagnostic.recorded"]
        test_event = next(e for e in recorded if e["parentId"] == row["testId"])
        run_event = next(e for e in recorded if e["parentId"] == document["run"]["id"])
        # Shard-owned diagnostics carry the q-computed identity untouched;
        # merged-run diagnostics have no q counterpart and are minted locally.
        self.assertEqual(q_emitted, test_event["entityId"])
        self.assertEqual(
            diagnostic_id(document["run"]["id"], 0, run_diagnostic),
            run_event["entityId"],
        )

    def test_missing_shard_diagnostic_event_fails_closed(self) -> None:
        document = scale_report(1)
        row = document["tests"][0]
        row["diagnostics"] = [{
            "type": "test-probe", "severity": "info", "phase": "execution",
            "message": "unmapped diagnostic", "data": {},
        }]
        with self.assertRaises(MergeError):
            lifecycle(
                document["run"], document["manifest"], [row], summary([row]), {},
                [], document["snapshotInventory"], document["benchmarkAnalysis"],
                shard_ids={},
            )

    def test_shard_diagnostic_ids_maps_events_by_parent_and_content(self) -> None:
        diagnostic = {"type": "probe", "message": "twice", "data": {}}
        documents = [{
            "events": [
                {"type": "diagnostic.recorded", "parentId": "test_a",
                 "entityId": "diagnostic_1", "payload": diagnostic},
                {"type": "diagnostic.recorded", "parentId": "test_a",
                 "entityId": "diagnostic_2", "payload": diagnostic},
                {"type": "test.finished", "parentId": "suite_x",
                 "entityId": "test_a", "payload": {}},
            ],
        }]
        mapping = shard_diagnostic_ids(documents)
        self.assertEqual(
            {("test_a", canonical(diagnostic)): ["diagnostic_1", "diagnostic_2"]},
            mapping,
        )

    def test_benchmark_uses_its_owning_test_finish_time(self) -> None:
        golden = json.loads(
            (ROOT / "tests/contracts/lifecycle-v2-golden.json").read_text(encoding="utf-8")
        )
        self.assertEqual("test.finishedAt", golden["observedTiming"]["benchmark.finished"])
        document = scale_report(1)
        row = document["tests"][0]
        row.update(
            startedAt="2026-08-12T12:00:00.100000Z",
            finishedAt="2026-08-12T12:00:00.101000Z",
            benchmark={"benchmarkId": "benchmark_" + "a" * 32},
        )
        events = lifecycle(
            document["run"], document["manifest"], [row], summary([row]), {},
            [], document["snapshotInventory"], document["benchmarkAnalysis"],
        )
        benchmark_event = next(
            event for event in events if event["type"] == "benchmark.finished"
        )
        self.assertEqual(row["finishedAt"], benchmark_event["occurredAt"])


if __name__ == "__main__":
    unittest.main()
