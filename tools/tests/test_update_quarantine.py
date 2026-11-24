"""The quarantine updater accepts a manifest written under another q build."""

from __future__ import annotations

import argparse
import json
import tempfile
import unittest
from pathlib import Path

from tools import update_quarantine


CODEC = {
    "name": "resq-value-v1+q-ipc-leaves",
    "version": 1,
    "qVersion": "4.1",
    "qRelease": "2026.05.01",
    "ipcSerialization": "q unary -8!/-9!",
    "capabilityLevel": "local unary serialization; no negotiated IPC connection capability",
}
ALGORITHM = "resq-test-case-id-v3"
TEST_ID = "test_" + "a" * 32


class UpdateQuarantineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.proposals = self.root / "proposals.json"
        self.manifest = self.root / "quarantine.json"
        self.proposals.write_text(json.dumps({
            "schemaVersion": 2, "kind": "resq-quarantine-proposals",
            "identityAlgorithm": ALGORITHM, "identityCodec": CODEC,
            "proposals": [{"testId": TEST_ID, "state": "suspect", "evidence": {"observations": 3}}],
        }), encoding="utf-8")

    def tearDown(self) -> None:
        self.dir.cleanup()

    def write_manifest(self, codec: dict, algorithm: str = ALGORITHM) -> None:
        self.manifest.write_text(json.dumps({
            "schemaVersion": 2, "kind": "resq-quarantine-manifest",
            "identityAlgorithm": algorithm, "identityCodec": codec,
            "updatedAt": "", "entries": [],
        }), encoding="utf-8")

    def build(self) -> dict:
        args = argparse.Namespace(
            proposals=self.proposals, manifest=self.manifest, owner="team",
            reason="vendor sandbox", issue="Q-1", expires="2099-01-01", test_id=None,
        )
        return update_quarantine.build_manifest(args)

    def test_manifest_from_another_q_build_is_updated_in_place(self) -> None:
        other = dict(CODEC, qVersion="4.0", qRelease="2023.08.11")
        self.write_manifest(other)
        document = self.build()
        self.assertEqual([entry["testId"] for entry in document["entries"]], [TEST_ID])
        # the manifest keeps the envelope it was written with
        self.assertEqual(document["identityCodec"], other)

    def test_another_algorithm_or_value_codec_is_still_refused(self) -> None:
        self.write_manifest(CODEC, algorithm="resq-test-case-id-v2")
        with self.assertRaisesRegex(ValueError, "differs from the proposals"):
            self.build()
        self.write_manifest(dict(CODEC, version=2))
        with self.assertRaisesRegex(ValueError, "differs from the proposals"):
            self.build()
        self.write_manifest({key: value for key, value in CODEC.items() if key != "qRelease"})
        with self.assertRaisesRegex(ValueError, "differs from the proposals"):
            self.build()


if __name__ == "__main__":
    unittest.main()
