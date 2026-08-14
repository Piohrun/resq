from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from migrate_identity_state import MigrationError, migrate  # noqa: E402
from review_corpus import scale_report  # noqa: E402


class IdentityMigrationTests(unittest.TestCase):
    def reports(self) -> tuple[dict, dict]:
        new = scale_report(2)
        old = copy.deepcopy(new)
        old["manifest"]["identityAlgorithm"] = "resq-test-case-id-v2"
        old["manifest"].pop("identityCodec", None)
        for index, entry in enumerate(old["manifest"]["tests"]):
            entry["testId"] = f"test_old_{index}"
            entry["executionId"] = f"test_old_{index}"
        return old, new

    @staticmethod
    def write(path: Path, value: dict) -> None:
        path.write_text(json.dumps(value), encoding="utf-8")

    def test_migrates_rerun_history_without_modifying_source(self) -> None:
        old, new = self.reports()
        source = {"schemaVersion": 1, "failedTestIds": ["test_old_1"]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old_path, new_path = root / "old.json", root / "new.json"
            state_path, output = root / "state.json", root / "migrated.json"
            self.write(old_path, old)
            self.write(new_path, new)
            self.write(state_path, source)
            migrated = migrate(old_path, new_path, state_path, output)
            self.assertEqual(source, json.loads(state_path.read_text()))
            self.assertEqual(2, migrated["schemaVersion"])
            self.assertEqual("resq-test-case-id-v3", migrated["identityAlgorithm"])
            self.assertEqual(
                new["manifest"]["tests"][1]["testId"], migrated["failedTestIds"][0]
            )
            self.assertEqual(migrated, json.loads(output.read_text()))

    def test_migrates_flake_and_quarantine_execution_ids(self) -> None:
        old, new = self.reports()
        for kind, collection in (
            ("resq-flake-history", "tests"),
            ("resq-quarantine-manifest", "entries"),
        ):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                old_path, new_path = root / "old.json", root / "new.json"
                state_path, output = root / "state.json", root / "migrated.json"
                self.write(old_path, old)
                self.write(new_path, new)
                self.write(
                    state_path,
                    {"schemaVersion": 1, "kind": kind,
                     collection: [{"testId": "test_old_0"}]},
                )
                result = migrate(old_path, new_path, state_path, output)
                self.assertEqual(
                    new["manifest"]["tests"][0]["executionId"],
                    result[collection][0]["testId"],
                )

    def test_rejects_inventory_drift_missing_ids_ambiguity_and_overwrite(self) -> None:
        old, new = self.reports()
        cases = []
        drifted = copy.deepcopy(new)
        drifted["manifest"]["tests"][0]["description"] = "changed"
        cases.append((old, drifted, {"schemaVersion": 1, "failedTestIds": []}, "inventories"))
        cases.append((old, new, {"schemaVersion": 1, "failedTestIds": ["unknown"]}, "no proven mapping"))
        ambiguous = copy.deepcopy(old)
        ambiguous["manifest"]["tests"][1].update(
            file=ambiguous["manifest"]["tests"][0]["file"],
            suite=ambiguous["manifest"]["tests"][0]["suite"],
            description=ambiguous["manifest"]["tests"][0]["description"],
            line=ambiguous["manifest"]["tests"][0]["line"],
            kind=ambiguous["manifest"]["tests"][0]["kind"],
            parameters=ambiguous["manifest"]["tests"][0]["parameters"],
            tags=ambiguous["manifest"]["tests"][0]["tags"],
        )
        cases.append((ambiguous, new, {"schemaVersion": 1, "failedTestIds": []}, "ambiguous"))
        for index, (old_doc, new_doc, state, expected) in enumerate(cases):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                paths = [root / name for name in ("old.json", "new.json", "state.json")]
                for path, value in zip(paths, (old_doc, new_doc, state)):
                    self.write(path, value)
                with self.assertRaisesRegex(MigrationError, expected):
                    migrate(*paths, root / "out.json")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = [root / name for name in ("old.json", "new.json", "state.json")]
            for path, value in zip(paths, (old, new, {"schemaVersion": 1, "failedTestIds": []})):
                self.write(path, value)
            output = root / "out.json"
            output.write_text("sentinel", encoding="utf-8")
            with self.assertRaisesRegex(MigrationError, "already exists"):
                migrate(*paths, output)
            self.assertEqual("sentinel", output.read_text())


if __name__ == "__main__":
    unittest.main()
