#!/usr/bin/env python3
"""Run resQ checks that require neither q nor a KX licence."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


REQUIRED = {
    "LICENSE", "README.md", "CHANGELOG.md", "SECURITY.md", "resq.q", "bin/resq",
    "bin/qspec", "lib/init.q", "docs/README.md", "docs/API_REFERENCE.md",
    "docs/schema/resq-report-v2.schema.json", "docs/SUPPORT.md",
    "docs/VERSIONING.md", "docs/IDENTITY.md", "tools/validate_report.py",
    "docs/EVENTS_AND_PLUGINS.md",
    "tools/verify_hostile_env.py", "tools/verify_external_pilots.py",
    "tools/verify_release_gate.py", "tools/verify_benchmark_regression.py",
    "tools/update_benchmark_baseline.py",
    "docs/schema/resq-benchmark-baseline-v1.schema.json",
    "docs/RELEASE_CHECKLIST.md",
    "tests/contracts/report-v2.json", "tests/contracts/junit.xml",
    "tests/contracts/xunit.xml",
}
GENERATED = {
    "test-results.xml", "test-results.json", "coverage.lcov",
    "coverage_report.html", "coverage_state.txt",
}
LINK = re.compile(r"!?(?:\[[^]]*\])\(([^)]+)\)")


def tracked_files() -> set[str]:
    completed = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True,
        capture_output=True,
    )
    return {item.decode() for item in completed.stdout.split(b"\0") if item}


def check_package() -> None:
    tracked = tracked_files()
    missing = sorted(relative for relative in REQUIRED if not (ROOT / relative).is_file())
    if missing:
        raise ValueError("required package files are missing: " + ", ".join(missing))
    leaked = sorted(GENERATED & tracked)
    if leaked:
        raise ValueError("generated artifacts are tracked: " + ", ".join(leaked))
    for relative in (
        "bin/resq", "bin/qspec", "tools/validate_report.py",
        "tools/verify_static.py", "tools/verify_hostile_env.py",
        "tools/verify_external_pilots.py", "tools/verify_release_gate.py",
        "tools/verify_benchmark_regression.py", "tools/update_benchmark_baseline.py",
    ):
        if not os.access(ROOT / relative, os.X_OK):
            raise ValueError(f"package entry point is not executable: {relative}")
    init = (ROOT / "lib/init.q").read_text(encoding="utf-8")
    match = re.search(r'^\.resq\.VERSION:\s*"([^"]+)";', init, re.MULTILINE)
    if not match:
        raise ValueError("lib/init.q does not declare .resq.VERSION")
    version = match.group(1)
    version_contracts = {
        "README.md": f"--branch v{version}",
        "docs/GETTING_STARTED.md": f"--branch v{version}",
        "CHANGELOG.md": f"## [{version}]",
    }
    for relative, marker in version_contracts.items():
        if marker not in (ROOT / relative).read_text(encoding="utf-8"):
            raise ValueError(f"release version {version} missing from {relative}")


def link_target(markdown: Path, raw: str) -> Path | None:
    value = raw.strip()
    if value.startswith("<") and ">" in value:
        value = value[1:value.index(">")]
    else:
        value = value.split(maxsplit=1)[0]
    if not value or value.startswith("#"):
        return None
    parsed = urlsplit(value)
    if parsed.scheme or parsed.netloc:
        return None
    path = unquote(parsed.path)
    if not path:
        return None
    return (markdown.parent / path).resolve()


def check_docs() -> int:
    checked = 0
    failures: list[str] = []
    for markdown in sorted(ROOT.rglob("*.md")):
        if ".git" in markdown.parts:
            continue
        text = markdown.read_text(encoding="utf-8")
        for raw in LINK.findall(text):
            target = link_target(markdown, raw)
            if target is None:
                continue
            checked += 1
            try:
                target.relative_to(ROOT)
            except ValueError:
                failures.append(f"{markdown.relative_to(ROOT)}: link escapes repository: {raw}")
                continue
            if not target.exists():
                failures.append(f"{markdown.relative_to(ROOT)}: missing link target: {raw}")
    if failures:
        raise ValueError("documentation link errors:\n" + "\n".join(failures))
    return checked


def check_contracts() -> None:
    schema = json.loads(
        (ROOT / "docs/schema/resq-report-v2.schema.json").read_text(encoding="utf-8")
    )
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise ValueError("report schema must declare JSON Schema draft 2020-12")
    if schema.get("properties", {}).get("schemaVersion", {}).get("const") != 2:
        raise ValueError("report schema does not describe schemaVersion 2")
    baseline_schema = json.loads(
        (ROOT / "docs/schema/resq-benchmark-baseline-v1.schema.json").read_text(
            encoding="utf-8"
        )
    )
    if baseline_schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise ValueError("benchmark baseline schema must declare JSON Schema draft 2020-12")
    if baseline_schema.get("properties", {}).get("schemaVersion", {}).get("const") != 1:
        raise ValueError("benchmark baseline schema does not describe schemaVersion 1")
    if baseline_schema.get("properties", {}).get("kind", {}).get("const") != "resq-benchmark-baseline":
        raise ValueError("benchmark baseline schema has the wrong document kind")
    definitions = schema.get("$defs", {})
    extensible = [schema, *(definitions[name] for name in (
        "run", "summary", "test", "attempt", "case", "diagnostic",
        "snapshot", "benchmarkAnalysis", "benchmarkMeasurement", "manifest", "event",
    ))]
    if not all(item.get("additionalProperties") is True for item in extensible):
        raise ValueError("report-v2 objects must accept additive minor-version fields")
    report = json.loads((ROOT / "tests/contracts/report-v2.json").read_text(encoding="utf-8"))
    validate(report)
    init = (ROOT / "lib/init.q").read_text(encoding="utf-8")
    version = re.search(r'^\.resq\.VERSION:\s*"([^"]+)";', init, re.MULTILINE).group(1)
    if report["frameworkVersion"] != version or report["run"]["resqVersion"] != version:
        raise ValueError("checked-in report contract version differs from .resq.VERSION")
    for name, root_name, row_name in (
        ("junit.xml", "testsuites", "testcase"),
        ("xunit.xml", "assemblies", "test"),
    ):
        root = ElementTree.parse(ROOT / "tests/contracts" / name).getroot()
        if root.tag != root_name:
            raise ValueError(f"{name}: expected root {root_name}, got {root.tag}")
        rows = root.findall(f".//{row_name}")
        if len(rows) != 1:
            raise ValueError(f"{name}: expected one contract test row")
        if not rows[0].get("name"):
            raise ValueError(f"{name}: contract row has no name")


def main() -> int:
    try:
        check_package()
        links = check_docs()
        check_contracts()
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, ElementTree.ParseError, ValueError) as exc:
        print(f"static verification failed: {exc}", file=sys.stderr)
        return 1
    print(f"static verification passed: package, schema/report, XML, and {links} local documentation links")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
