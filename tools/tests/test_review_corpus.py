from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from review_corpus import loader_source, scale_report  # noqa: E402
from benchmark_review_regressions import growth_ratios, robust_samples  # noqa: E402
from validate_report import validate  # noqa: E402


class ReviewCorpusTests(unittest.TestCase):
    def test_loader_generator_is_deterministic_and_dense(self) -> None:
        source = loader_source(110)
        self.assertEqual(source, loader_source(110))
        self.assertEqual(110, source.count('should["generated case'))
        self.assertTrue(source.endswith("::\n"))

    def test_loader_growth_ratios_are_adjacent_and_deterministic(self) -> None:
        measurements = [
            {"expectations": 50, "preprocessSeconds": 0.1},
            {"expectations": 100, "preprocessSeconds": 0.21},
            {"expectations": 200, "preprocessSeconds": 0.44},
        ]
        self.assertEqual([2.1, 2.095238], growth_ratios(measurements))

    def test_review_benchmarks_use_robust_samples(self) -> None:
        values = iter([100.0, 200.0, 1.0, 2.0, 500.0, 3.0, 4.0])
        calls = []

        def measure() -> dict[str, float]:
            calls.append(1)
            return {"wallSeconds": next(values), "peakBytes": 10.0}

        samples, medians = robust_samples(measure, warmups=2, samples=5)
        self.assertEqual(7, len(calls))
        self.assertEqual(5, len(samples))
        self.assertEqual(3.0, medians["wallSeconds"])
        self.assertEqual(10.0, medians["peakBytes"])
        with self.assertRaisesRegex(ValueError, ">=3 samples"):
            robust_samples(measure, warmups=0, samples=1)

    def test_constructor_fixture_covers_every_affected_token(self) -> None:
        source = (ROOT / "tests/fixtures/review/loader_constructor_literals.q").read_text(
            encoding="utf-8"
        )
        for constructor in (
            "should", "it", "shouldEach", "holds", "perf",
            "skip", "pending", "skipIf", "retry", "testOnly",
        ):
            self.assertIn(f"{constructor}[", source)
        self.assertIn("second same-line constructor", source)

    def test_default_report_is_deterministic_and_valid(self) -> None:
        first = scale_report(12)
        second = scale_report(12)
        self.assertEqual(first, second)
        validate(first)
        self.assertEqual(12, len(first["tests"]))
        self.assertEqual(12, len(first["manifest"]["tests"]))
        self.assertEqual(55, len(first["events"]))

    def test_failure_and_optional_evidence_variants_are_bounded(self) -> None:
        document = scale_report(
            20,
            failure_every=5,
            failure_bytes=128,
            include_coverage=True,
            include_property=True,
            include_benchmark=True,
        )
        validate(document)
        failures = [row for row in document["tests"] if row["status"] == "fail"]
        self.assertEqual(4, len(failures))
        self.assertTrue(all(len(row["message"]) == 128 for row in failures))
        self.assertTrue(document["coverage"]["enabled"])
        self.assertTrue(document["tests"][0]["property"])
        self.assertTrue(document["performance"])

    def test_checked_mutation_catalog_is_complete_and_unique(self) -> None:
        path = ROOT / "tests/contracts/review/mutations.json"
        catalog = json.loads(path.read_text(encoding="utf-8"))
        names = [case["name"] for case in catalog["cases"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(8, len(names))
        self.assertEqual({3, 5, 9}, {case["requiredByStep"] for case in catalog["cases"]})

    def test_command_line_generators_write_outside_the_checkout(self) -> None:
        with tempfile.TemporaryDirectory(prefix="resq-review-corpus-test-") as directory:
            root = Path(directory)
            q_path = root / "loader.q"
            report_path = root / "report.json"
            for command in (
                [sys.executable, str(ROOT / "tools/review_corpus.py"), "loader", "5", str(q_path)],
                [sys.executable, str(ROOT / "tools/review_corpus.py"), "report", "5", str(report_path)],
            ):
                completed = subprocess.run(command, text=True, capture_output=True, check=False)
                self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(5, q_path.read_text(encoding="utf-8").count('should["generated case'))
            validate(json.loads(report_path.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
