from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402
from report_profiles import project  # noqa: E402


def test_row(name: str, status: str, suffix: str) -> dict:
    return {
        "suite": "adapter suite",
        "description": name,
        "status": status,
        "message": "boom" if status == "fail" else "",
        "time": "0D00:00:00.001000000",
        "durationSeconds": 0.001,
        "failures": ["boom"] if status == "fail" else [],
        "assertsRun": 1,
        "file": "tests/test_adapter.q",
        "line": 10,
        "namespace": "",
        "tags": ["unit"],
        "output": "",
        "testId": f"test_{suffix * 32}",
        "caseId": "",
        "kind": "test",
        "parameters": {},
        "attempts": 1,
        "retried": False,
        "flaky": False,
        "attemptHistory": [],
        "parameterCases": [],
        "property": {},
        "diagnostics": [],
        "snapshots": [],
        "benchmark": {},
        "quarantine": {},
    }


def report() -> dict:
    rows = [test_row("passes", "pass", "b"), test_row("fails", "fail", "c")]
    return {
        "schemaVersion": 2,
        "framework": "resQ",
        "frameworkVersion": "1.8.0",
        "run": {
            "id": f"run_{'a' * 32}",
            "startedAt": "2026-08-12T12:00:00.000000000Z",
            "finishedAt": "2026-08-12T12:00:01.000000000Z",
            "durationSeconds": 1.0,
            "hostname": "ci-1",
            "cwd": "/checkout",
            "qVersion": "4.1",
            "qRelease": "2024.01.01",
            "os": "linux",
            "resqVersion": "1.8.0",
            "vcs": {"sha": "deadbeef", "branch": "main", "dirty": False},
            "ci": {"CI": "true"},
            "config": {},
            "ordering": {"randomized": False, "seed": 0, "algorithm": "md5-counter-v1"},
            "selection": {
                "mode": "all", "stateFile": ".resq/last-run.json",
                "historyStatus": "missing", "priorFailedCount": 0,
                "applied": False, "selectedTestCount": 2,
            },
            "shard": {
                "index": 0, "count": 1, "unit": "file", "algorithm": "sorted-index-mod-v1",
                "allFileCount": 1, "selectedFileCount": 1,
                "allUnitCount": 1, "selectedUnitCount": 1,
                "selectedFiles": ["tests/test_adapter.q"],
                "selectedExecutionIds": [row["testId"] for row in rows],
            },
        },
        "summary": {
            "suiteCount": 1, "testCount": 2, "assertionCount": 2,
            "passCount": 1, "failCount": 1, "errorCount": 0,
            "skipCount": 0, "duration": "0D00:00:00.002000000",
            "durationSeconds": 0.002,
        },
        "tests": rows,
        "performance": [],
        "coverage": {},
        "diagnostics": [],
        "flake": {
            "schemaVersion": 1,
            "historyPath": ".resq/flake-history.json",
            "historyStatus": "missing",
            "manifestPath": ".resq/quarantine.json",
            "manifestStatus": "missing",
            "nonBlockingEnabled": False,
            "evidenceMin": 3,
            "failureMin": 2,
            "window": 20,
            "healthy": 0,
            "suspect": 0,
            "quarantined": 0,
            "expired": 0,
            "insufficient": 0,
            "proposalCount": 0,
        },
        "snapshotInventory": {
            "schemaVersion": 1, "kind": "resq-snapshot-inventory",
            "enabled": False, "generatedAt": "2026-08-12T12:00:01Z",
            "complete": False, "completenessReasons": ["disabled"],
            "roots": [], "entries": [],
            "counts": {"referenced": 0, "missing": 0, "obsolete": 0,
                       "unverified": 0, "unsafe": 0, "stored": 0, "declared": 0},
            "gate": {"enabled": False, "passed": True, "reasons": []},
        },
        "benchmarkAnalysis": {
            "schemaVersion": 1, "kind": "resq-benchmark-analysis",
            "enabled": False, "baselinePath": "", "baselineStatus": "disabled",
            "method": {"name": "Mann-Whitney U", "alternative": "two-sided",
                       "continuityCorrection": True, "tieCorrection": True,
                       "multipleComparison": "Holm-Bonferroni"},
            "config": {"alpha": 0.05, "practicalEffectPercent": 5,
                       "minimumSamples": 5, "metric": "timeNs"},
            "environment": {"qVersion": "4.1", "qRelease": "2024.01.01",
                            "os": "linux", "architecture": "x86_64",
                            "cpuModel": "unit", "logicalCores": 1,
                            "fingerprint": f"environment_{'1' * 32}"},
            "counts": {"total": 0, "baselineFound": 0, "comparable": 0,
                       "improved": 0, "stable": 0, "inconclusive": 0,
                       "regressed": 0, "environmentMismatches": 0},
            "comparisons": [],
            "gate": {"enabled": False, "deferred": False, "passed": True, "reasons": []},
        },
    }


class AdapterTests(unittest.TestCase):
    def test_validator_enforces_manifest_and_event_linkage(self) -> None:
        contract = json.loads(
            (ROOT / "tests/contracts/report-v2.json").read_text(encoding="utf-8")
        )
        validate(contract)

        bad_sequence = deepcopy(contract)
        bad_sequence["events"][3]["sequence"] = 99
        with self.assertRaisesRegex(ValueError, "sequence"):
            validate(bad_sequence)

        bad_manifest = deepcopy(contract)
        bad_manifest["manifest"]["tests"][0]["testId"] = f"test_{'9' * 32}"
        with self.assertRaisesRegex(ValueError, "executionId"):
            validate(bad_manifest)

    def test_validator_accepts_legacy_events_and_enforces_v2_observed_time(self) -> None:
        legacy = json.loads(
            (ROOT / "tests/contracts/report-v2.json").read_text(encoding="utf-8")
        )
        validate(legacy)
        observed = deepcopy(legacy)
        started = "2026-08-12T12:00:00.100000000Z"
        finished = "2026-08-12T12:00:00.101000000Z"
        row = observed["tests"][0]
        row.update(startedAt=started, finishedAt=finished)
        row["attemptHistory"][0].update(startedAt=started, finishedAt=finished)
        for event in observed["events"]:
            event["schemaVersion"] = 2
            if event["type"] in {"test.started", "attempt.started"}:
                event["occurredAt"] = started
            if event["type"] in {"test.finished", "attempt.finished"}:
                event["occurredAt"] = finished
        manifest = observed["manifest"]
        observed["events"][1]["payload"] = {
            "schemaVersion": manifest["schemaVersion"],
            "kind": manifest["kind"],
            "digest": manifest["digest"],
            "digestAlgorithm": manifest["digestAlgorithm"],
            "identityAlgorithm": manifest["identityAlgorithm"],
            "frameworkVersion": manifest["frameworkVersion"],
            "fileCount": len(manifest["files"]),
            "testCount": len(manifest["tests"]),
        }
        validate(observed)
        observed["events"][4]["occurredAt"] = "2026-08-12T12:00:00.200000000Z"
        with self.assertRaisesRegex(ValueError, "test.started timing differs"):
            validate(observed)

    def test_validator_rejects_duplicate_stable_ids(self) -> None:
        duplicate = report()
        duplicate["tests"][1]["testId"] = duplicate["tests"][0]["testId"]
        with self.assertRaisesRegex(ValueError, "duplicate execution identity"):
            validate(duplicate)

    def test_validator_rejects_inconsistent_retry_and_property_telemetry(self) -> None:
        bad_retry = report()
        bad_retry["tests"][0]["retried"] = True
        with self.assertRaisesRegex(ValueError, "retried must agree"):
            validate(bad_retry)

        bad_property = deepcopy(report())
        bad_property["tests"][0]["property"] = {
            "seed": 42, "runs": 10, "maxFailRate": 0,
            "failRate": 0, "passCount": 8, "failCount": 1,
            "failedInputs": [], "shrunkInput": None,
            "generatorProtocol": "resq-generator-v1", "replayToken": "token",
            "replayTokens": ["token"], "originalInput": 1, "minimalInput": 0,
            "shrinkSteps": 1, "shrinkCandidates": 1,
            "shrinkTermination": "minimal", "failureSignature": "signature",
            "shrinkDurationMs": 0.1,
        }
        with self.assertRaisesRegex(ValueError, "totals must equal runs"):
            validate(bad_property)

        bad_replay = report()
        bad_replay["tests"][0]["property"] = {
            "seed": 42, "runs": 1, "maxFailRate": 0,
            "failRate": 1, "passCount": 0, "failCount": 1,
            "failedInputs": [1], "shrunkInput": 0,
            "generatorProtocol": "resq-generator-v1",
            "replayToken": "resq-pbt-v1/42/0", "replayTokens": [],
            "originalInput": 1, "minimalInput": 0,
            "shrinkSteps": 1, "shrinkCandidates": 1,
            "shrinkTermination": "minimal",
            "failureSignature": "fuzz-failure-v1/1/abc",
            "shrinkDurationMs": 0.1,
        }
        with self.assertRaisesRegex(ValueError, "replay token count"):
            validate(bad_replay)

        bad_quarantine = report()
        bad_quarantine["tests"][0]["quarantine"] = {
            "schemaVersion": 1, "state": "expired", "active": False,
            "nonBlocking": True, "observations": 4, "passes": 2,
            "failures": 2, "flakes": 0, "owner": "quality",
            "reason": "known intermittent", "evidence": {}, "issue": "Q-1",
            "createdAt": "2026-08-01T00:00:00Z", "expiresAt": "2026-08-10",
        }
        with self.assertRaisesRegex(ValueError, "only active quarantine"):
            validate(bad_quarantine)

    def test_ndjson_preserves_run_and_stable_test_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "report.json"
            output = root / "events.ndjson"
            source.write_text(json.dumps(report()), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(ROOT / "tools/resq_to_ndjson.py"), str(source), "-o", str(output)],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            events = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(["resq.run", "resq.test", "resq.test"], [e["eventType"] for e in events])
            self.assertTrue(all(e["runId"] == f"run_{'a' * 32}" for e in events))
            self.assertEqual(f"test_{'b' * 32}", events[1]["test"]["testId"])

    def test_declared_profiles_validate_and_omissions_are_exact(self) -> None:
        base = json.loads(
            (ROOT / "tests/contracts/report-v2.json").read_text(encoding="utf-8")
        )
        for profile in ("full", "results", "telemetry"):
            document = project(base, profile)
            validate(document)
            self.assertEqual(profile, document["profile"])
        telemetry = project(base, "telemetry")
        self.assertNotIn("manifest", telemetry)
        self.assertNotIn("attemptHistory", telemetry["tests"][0])
        dishonest = deepcopy(telemetry)
        dishonest["coverage"] = {}
        with self.assertRaisesRegex(ValueError, "declared omitted sections are present"):
            validate(dishonest)

    def test_ndjson_streams_profiles_and_enforces_input_ceiling(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "telemetry.json"
            output = root / "events.ndjson"
            source.write_text(json.dumps(project(report(), "telemetry")), encoding="utf-8")
            accepted = subprocess.run(
                [sys.executable, str(ROOT / "tools/resq_to_ndjson.py"), str(source),
                 "-o", str(output), "--max-input-bytes", str(source.stat().st_size)],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(0, accepted.returncode, accepted.stderr)
            first = json.loads(output.read_text(encoding="utf-8").splitlines()[0])
            self.assertEqual("telemetry", first["profile"])
            self.assertNotIn("coverage", first)
            rejected = subprocess.run(
                [sys.executable, str(ROOT / "tools/resq_to_ndjson.py"), str(source),
                 "--max-input-bytes", str(source.stat().st_size - 1)],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(1, rejected.returncode)
            self.assertIn("converter ceiling", rejected.stderr)

    def test_allure_maps_status_history_and_labels(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "report.json"
            output = root / "allure-results"
            document = report()
            document["tests"][0].update(
                startedAt="2026-08-12T12:00:00.100000000Z",
                finishedAt="2026-08-12T12:00:00.101000000Z",
            )
            document["tests"][0]["parameters"] = {"region": "eu", "size": 3}
            document["tests"][0]["quarantine"] = {
                "schemaVersion": 1, "state": "quarantined", "active": True,
                "nonBlocking": True, "observations": 4, "passes": 2,
                "failures": 2, "flakes": 0, "owner": "quality",
                "reason": "known intermittent", "evidence": {}, "issue": "Q-1",
                "createdAt": "2026-08-01T00:00:00Z", "expiresAt": "2026-09-01",
            }
            document["tests"][1]["kind"] = "fuzz"
            document["tests"][1]["property"] = {
                "seed": 42, "runs": 1, "maxFailRate": 0,
                "failRate": 1, "passCount": 0, "failCount": 1,
                "failedInputs": [[4, 2]], "shrunkInput": [0],
                "generatorProtocol": "resq-generator-v1",
                "replayToken": "resq-pbt-v1/42/0",
                "replayTokens": ["resq-pbt-v1/42/0"],
                "originalInput": [4, 2], "minimalInput": [0],
                "shrinkSteps": 2, "shrinkCandidates": 3,
                "shrinkTermination": "minimal",
                "failureSignature": "fuzz-failure-v1/1/abc",
                "shrinkDurationMs": 0.1,
            }
            source.write_text(json.dumps(document), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(ROOT / "tools/resq_to_allure.py"), str(source), str(output)],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            result_files = sorted(output.glob("*-result.json"))
            self.assertEqual(2, len(result_files))
            results = [json.loads(path.read_text(encoding="utf-8")) for path in result_files]
            failed = next(item for item in results if item["name"] == "fails")
            self.assertEqual("failed", failed["status"])
            self.assertEqual(f"test_{'c' * 32}", failed["historyId"])
            self.assertEqual("boom", failed["statusDetails"]["message"])
            self.assertIn({"name": "tag", "value": "unit"}, failed["labels"])
            self.assertNotIn("start", failed)
            self.assertNotIn("stop", failed)
            self.assertIn(
                {"name": "propertyReplayToken", "value": "resq-pbt-v1/42/0"},
                failed["parameters"],
            )
            self.assertIn(
                {"name": "propertyMinimalInput", "value": "[0]"},
                failed["parameters"],
            )
            passed = next(item for item in results if item["name"] == "passes")
            self.assertIn({"name": "region", "value": "eu"}, passed["parameters"])
            self.assertIn({"name": "size", "value": "3"}, passed["parameters"])
            self.assertIn(
                {"name": "quarantineState", "value": "quarantined"},
                passed["parameters"],
            )
            self.assertEqual(1, passed["stop"] - passed["start"])
            self.assertTrue((output / "executor.json").is_file())
            self.assertTrue((output / "environment.properties").is_file())


if __name__ == "__main__":
    unittest.main()
