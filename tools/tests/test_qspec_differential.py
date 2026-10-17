"""Licence-free contracts for the upstream-qspec differential verifier."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import verify_qspec_differential as differential  # noqa: E402


UPSTREAM_XML = """<testsuites>
<testsuite name="SHA" tests="3">
<testcase name="should hash" time="0"/>
<testcase name="should hash" time="0"/>
<testcase name="it holds that fuzz" time="0"><failure type="x" message="y"/></testcase>
</testsuite>
<testsuite name="Halt"><testcase name="should halt" time="0"><error type="e" message="m"/><failure type="f" message="m"/></testcase>
<testcase name="should skip" time="0"><skipped/></testcase></testsuite>
</testsuites>"""


class ReportParsingTests(unittest.TestCase):
    def test_xml_is_found_after_leading_console_text(self) -> None:
        self.assertEqual(differential.extract_xml("qutil says hi\n<?xml v?><a/>"), "<?xml v?><a/>")
        self.assertEqual(differential.extract_xml("noise <testsuites/>"), "<testsuites/>")
        with self.assertRaises(RuntimeError):
            differential.extract_xml("Tests: 3 total")

    def test_verdicts_key_on_suite_and_name_and_keep_repeats(self) -> None:
        self.assertEqual(differential.verdicts(UPSTREAM_XML), {
            "SHA :: should hash": "pass",
            "SHA :: should hash #2": "pass",
            "SHA :: it holds that fuzz": "fail",
            "Halt :: should halt": "error",
            "Halt :: should skip": "skip",
        })


QSPEC_XUNIT = """<test-suite>
<test-suite name="SHA" reports="1" skips="0" tests="3" errors="0" failures="1" test-cases="3">
<test-case name="hash" label="should hash" errors="0" failures="0" skip="0" tests="1"/>
<test-case name="bad" label="should bad" errors="0" failures="2" skip="0" tests="1">
<sysout>
Failure: x
</sysout>
</test-case>
<test-case name="boom" label="it holds that boom" errors="1" failures="0" skip="0" tests="0"/>
<test-case name="later" label="should later" errors="0" failures="0" skip="1" tests="0"/>
</test-suite>
</test-suite>
"""


class QspecXunitTests(unittest.TestCase):
    def test_bare_test_suite_root_is_found(self) -> None:
        self.assertTrue(differential.extract_xml("noise\n" + QSPEC_XUNIT).startswith("<test-suite>"))

    def test_qspec_xunit_verdicts_key_on_label(self) -> None:
        self.assertEqual(differential.verdicts(QSPEC_XUNIT), {
            "SHA :: should hash": "pass",
            "SHA :: should bad": "fail",
            "SHA :: it holds that boom": "error",
            "SHA :: should later": "skip",
        })


class ComparisonTests(unittest.TestCase):
    upstream = {"S :: should a": "pass", "S :: should b": "pass", "S :: should c": "fail"}

    def test_identical_reports_have_no_differences(self) -> None:
        self.assertEqual(differential.compare(self.upstream, dict(self.upstream), []), ([], []))

    def test_changed_missing_and_extra_tests_are_unexpected(self) -> None:
        resq = {"S :: should a": "fail", "S :: should c": "fail", "S :: b": "pass"}
        unexpected, stale = differential.compare(self.upstream, resq, [])
        self.assertEqual(stale, [])
        self.assertEqual(unexpected, [
            {"test": "S :: b", "upstream": "absent", "resq": "pass"},
            {"test": "S :: should a", "upstream": "pass", "resq": "fail"},
            {"test": "S :: should b", "upstream": "pass", "resq": "absent"},
        ])

    def test_listed_difference_must_match_exactly_and_still_occur(self) -> None:
        resq = dict(self.upstream, **{"S :: should a": "error"})
        listed = [{"test": "S :: should a", "upstream": "pass", "resq": "error", "reason": "r"}]
        self.assertEqual(differential.compare(self.upstream, resq, listed), ([], []))
        wrong_status = [dict(listed[0], resq="fail")]
        unexpected, stale = differential.compare(self.upstream, resq, wrong_status)
        self.assertEqual(len(unexpected), 1)
        self.assertEqual(len(stale), 1)
        unexpected, stale = differential.compare(self.upstream, dict(self.upstream), listed)
        self.assertEqual(unexpected, [])
        self.assertEqual(stale, [{"test": "S :: should a", "upstream": "pass", "resq": "error"}])


class ManifestTests(unittest.TestCase):
    def test_vendored_corpus_matches_the_pinned_manifest(self) -> None:
        manifest = json.loads(differential.MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 1)
        names = {project["name"] for project in manifest["projects"]}
        self.assertTrue({manifest["harness"]["qspec"], manifest["harness"]["qutil"]} <= names)
        for project in manifest["projects"]:
            differential.verify_vendor(project)
        for case in manifest["cases"]:
            self.assertIn(case["project"], names)
            for entry in case["expectedDifferences"]:
                self.assertTrue(entry["reason"].strip(), entry)


if __name__ == "__main__":
    unittest.main()
