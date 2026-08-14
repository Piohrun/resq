from __future__ import annotations

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from verify_formatter_boundaries import check, scan_text  # noqa: E402


class FormatterBoundaryTests(unittest.TestCase):
    def test_repository_production_q_respects_boundary(self) -> None:
        self.assertEqual([], check(ROOT))

    def test_seeded_identity_snapshot_xml_and_assertion_violations_are_found(self) -> None:
        fixtures = {
            "identity.q": 'id:.Q.s1 parameters;\n',
            "snapshot.q": 'payload:-3!value;\n',
            "xml.q": 'xml:"<failure>",.Q.s1[message],"</failure>";\n',
            "assertions.q": 'failure:"got ",(-3!actual);\n',
        }
        for name, source in fixtures.items():
            with self.subTest(name=name):
                violations = scan_text(Path(name), source)
                self.assertEqual(1, len(violations))
                self.assertIn(violations[0].token, (".Q.s1", "-3!"))

    def test_iterator_slash_does_not_hide_the_rest_of_the_line(self) -> None:
        fixtures = {
            "adverb_over.q": 'seed:{r:(+/) x; s:.Q.s1 r; s};\n',
            "adverb_each.q": 'joined:{raze each/[2;x]; -3!x};\n',
            "adverb_glued.q": 'total:sum over x;flat:,/[x];bad:.Q.s1 flat;\n',
        }
        for name, source in fixtures.items():
            with self.subTest(name=name):
                violations = scan_text(Path(name), source)
                self.assertEqual(1, len(violations), source)

    def test_whitespace_slash_still_starts_a_comment(self) -> None:
        source = 'x:1+2 / trailing comment naming .Q.s1 and -3!\n'
        self.assertEqual([], scan_text(Path("trailing.q"), source))

    def test_comments_do_not_false_positive_but_dynamic_source_strings_do(self) -> None:
        source = "\n".join((
            "/ .Q.s1 and -3! are named in this comment",
            "/",
            ".Q.s1 is also named inside a block comment",
            "\\",
            'generated:"{x:.Q.s1 y}";',
        ))
        violations = scan_text(Path("comments.q"), source)
        self.assertEqual(1, len(violations))
        self.assertEqual(".Q.s1", violations[0].token)


if __name__ == "__main__":
    unittest.main()
