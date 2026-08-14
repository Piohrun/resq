from __future__ import annotations

import copy
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.review_corpus import scale_report
from tools.verify_release_gate import (
    private_state_args,
    reconcile_suites,
    require_residue_free_checkout,
    verdict,
)


class ReleaseGateContractTests(unittest.TestCase):
    @staticmethod
    def git(root: Path, *arguments: str) -> None:
        subprocess.run(["git", *arguments], cwd=root, check=True, capture_output=True)

    def clean_repository(self, root: Path) -> None:
        self.git(root, "init", "-q")
        self.git(root, "config", "user.email", "release-gate@example.invalid")
        self.git(root, "config", "user.name", "Release Gate Test")
        (root / ".gitignore").write_text("ignored/\n.codegraph/\noutput/\n", encoding="utf-8")
        (root / "tracked.txt").write_text("tracked\n", encoding="utf-8")
        self.git(root, "add", ".gitignore", "tracked.txt")
        self.git(root, "commit", "-qm", "fixture")

    def test_reconciliation_uses_execution_identity_and_ignores_only_timing(self) -> None:
        normal = scale_report(2)
        isolated = copy.deepcopy(normal)
        isolated["summary"]["duration"] = "0D00:00:01.000000000"
        isolated["summary"]["durationSeconds"] = 1.0
        isolated["summary"]["testDurationSumSeconds"] = 1.0
        isolated["tests"][0]["caseId"] = "case_" + "a" * 32
        normal["tests"][0]["caseId"] = isolated["tests"][0]["caseId"]
        isolated["tests"][0]["durationSeconds"] = 0.9
        isolated["tests"][0]["time"] = "0D00:00:00.900000000"
        with tempfile.TemporaryDirectory() as raw:
            receipt = reconcile_suites(normal, isolated, Path(raw) / "receipt.json")
        self.assertTrue(receipt["semanticInventoryParity"])
        self.assertEqual(2, len(verdict(normal)))

    def test_reconciliation_rejects_policy_state_drift(self) -> None:
        normal = scale_report(1)
        isolated = copy.deepcopy(normal)
        isolated["tests"][0]["quarantine"] = {
            "schemaVersion": 1,
            "state": "healthy",
        }
        with tempfile.TemporaryDirectory() as raw:
            with self.assertRaisesRegex(RuntimeError, "semantic test inventory"):
                reconcile_suites(normal, isolated, Path(raw) / "receipt.json")

    def test_private_state_paths_are_lane_scoped_and_complete(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            normal = private_state_args(root, "normal")
            isolated = private_state_args(root, "isolated")
            self.assertEqual(
                {
                    "-state-file", "-flake-history", "-quarantine-file",
                    "-flake-proposal-file",
                },
                set(normal[::2]),
            )
            self.assertTrue(all(str(root / "state") in path for path in normal[1::2]))
            self.assertTrue(set(normal[1::2]).isdisjoint(isolated[1::2]))

    def test_residue_gate_allows_unchanged_preexisting_ignored_state(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.clean_repository(root)
            (root / "ignored").mkdir()
            (root / "ignored/cache.bin").write_bytes(b"existing")
            baseline = require_residue_free_checkout(root=root)
            self.assertIn("ignored/cache.bin", baseline)
            self.assertEqual(
                baseline,
                require_residue_free_checkout(root=root, ignored_baseline=baseline),
            )

    def test_residue_gate_rejects_new_changed_or_removed_ignored_files(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.clean_repository(root)
            (root / "ignored").mkdir()
            cache = root / "ignored/cache.bin"
            cache.write_bytes(b"existing")
            baseline = require_residue_free_checkout(root=root)

            cache.write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "changed: ignored/cache.bin"):
                require_residue_free_checkout(root=root, ignored_baseline=baseline)
            cache.write_bytes(b"existing")
            (root / "ignored/new.bin").write_bytes(b"new")
            with self.assertRaisesRegex(RuntimeError, "added: ignored/new.bin"):
                require_residue_free_checkout(root=root, ignored_baseline=baseline)
            (root / "ignored/new.bin").unlink()
            cache.unlink()
            with self.assertRaisesRegex(RuntimeError, "removed: ignored/cache.bin"):
                require_residue_free_checkout(root=root, ignored_baseline=baseline)

    def test_residue_gate_excludes_requested_output_and_codegraph_state(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.clean_repository(root)
            output = root / "output"
            baseline = require_residue_free_checkout(root=root, output=output)
            output.mkdir()
            (output / "report.json").write_text("{}", encoding="utf-8")
            (root / ".codegraph").mkdir()
            (root / ".codegraph/index").write_text("volatile", encoding="utf-8")
            require_residue_free_checkout(
                root=root, output=output, ignored_baseline=baseline,
            )

    def test_residue_gate_still_rejects_source_and_nonignored_changes(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.clean_repository(root)
            (root / "tracked.txt").write_text("changed\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "tracked or non-ignored"):
                require_residue_free_checkout(root=root)
            self.git(root, "restore", "tracked.txt")
            (root / "untracked.txt").write_text("new\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "untracked.txt"):
                require_residue_free_checkout(root=root)


if __name__ == "__main__":
    unittest.main()
