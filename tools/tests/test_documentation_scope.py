from __future__ import annotations

import unittest

from tools.verify_static import check_documentation_scope, documentation_scope_sources


class DocumentationScopeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.documents = documentation_scope_sources()

    def mutated(self, relative: str, marker: str) -> dict[str, str]:
        documents = dict(self.documents)
        self.assertIn(marker, documents[relative])
        documents[relative] = documents[relative].replace(marker, "", 1)
        return documents

    def test_current_documentation_contract_passes(self) -> None:
        check_documentation_scope(self.documents)

    def test_polling_only_async_scope_is_required(self) -> None:
        documents = self.mutated(
            "docs/ASYNC.md",
            "These are polling-only test helpers, not real asynchronous execution support.",
        )
        with self.assertRaisesRegex(ValueError, "polling-only async scope"):
            check_documentation_scope(documents)

    def test_parallel_group_and_licence_scope_is_required(self) -> None:
        documents = self.mutated("docs/PARALLEL.md", "one q runtime/licence allocation")
        with self.assertRaisesRegex(ValueError, "parallel group and licence scope"):
            check_documentation_scope(documents)

    def test_ecosystem_claims_remain_scoped(self) -> None:
        documents = self.mutated(
            "docs/ROADMAP_POST_1_0.md",
            "No mutation-testing runner or service is shipped.",
        )
        with self.assertRaisesRegex(ValueError, "ecosystem claims remain scoped"):
            check_documentation_scope(documents)

    def test_each_claim_family_keeps_an_executable_gate(self) -> None:
        documents = self.mutated("docs/VERIFICATION.md", "| Benchmark statistics |")
        with self.assertRaisesRegex(ValueError, "Benchmark statistics"):
            check_documentation_scope(documents)

    def test_superseded_release_cannot_be_recommended(self) -> None:
        documents = dict(self.documents)
        documents["docs/GETTING_STARTED.md"] += "\nInstall v1.8.0 as the current release.\n"
        with self.assertRaisesRegex(ValueError, "superseded v1.8.0"):
            check_documentation_scope(documents)


if __name__ == "__main__":
    unittest.main()
