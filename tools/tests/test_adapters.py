from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


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
        "attempts": 1,
        "retried": False,
        "flaky": False,
        "attemptHistory": [],
        "parameterCases": [],
        "property": {},
        "diagnostics": [],
        "snapshots": [],
        "benchmark": {},
    }


def report() -> dict:
    rows = [test_row("passes", "pass", "b"), test_row("fails", "fail", "c")]
    return {
        "schemaVersion": 2,
        "framework": "resQ",
        "frameworkVersion": "1.0.0",
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
            "resqVersion": "1.0.0",
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
                "index": 0, "count": 1, "algorithm": "sorted-index-mod-v1",
                "allFileCount": 1, "selectedFileCount": 1,
                "selectedFiles": ["tests/test_adapter.q"],
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
    }


class AdapterTests(unittest.TestCase):
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

    def test_allure_maps_status_history_and_labels(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "report.json"
            output = root / "allure-results"
            source.write_text(json.dumps(report()), encoding="utf-8")
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
            self.assertTrue((output / "executor.json").is_file())
            self.assertTrue((output / "environment.properties").is_file())


if __name__ == "__main__":
    unittest.main()
