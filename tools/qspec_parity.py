#!/usr/bin/env python3
"""Run workplace qspec/resQ commands and retain testcase-level parity evidence."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any
from xml.etree import ElementTree as ET

from process_control import run_bounded
from verify_qspec_differential import case_status, qspec_xunit_status, compare

STATUSES = {"pass", "fail", "error", "skip", "absent"}


def identity(suite: str, name: str, occurrence: int) -> str:
    return json.dumps([suite, name, occurrence], ensure_ascii=False)


def read_report(text: str) -> list[dict[str, Any]]:
    # Permit startup chatter, but not multiple reports or trailing non-XML text.
    if "<!DOCTYPE" in text or "<!ENTITY" in text:
        raise ValueError("DTD/entity declarations are not supported")
    start = re.search(r"<\?xml\b|<testsuites?\b|<test-suite\b", text)
    if start is None:
        raise ValueError("no JUnit or qspec xUnit report found")
    root = ET.fromstring(text[start.start():])
    if root.tag not in {"testsuites", "testsuite", "test-suite"}:
        raise ValueError("unsupported report root")
    legacy = root.tag == "test-suite"
    suite_tag, case_tag = ("test-suite", "test-case") if legacy else ("testsuite", "testcase")
    for element in root.iter():
        if element.tag in {suite_tag, "testsuites"}:
            count_field = "test-cases" if legacy else "tests"
            if count_field in element.attrib and int(element.attrib[count_field]) != len(list(element.iter(case_tag))):
                raise ValueError(f"declared {count_field} count disagrees with testcase inventory")
    counts: Counter[tuple[str, str]] = Counter()
    rows = []
    for suite in root.iter(suite_tag):
        for case in suite.findall(case_tag):
            suite_name = suite.get("name", "")
            name = case.get("label" if legacy else "name", "")
            if not name or not suite_name:
                raise ValueError("testcase and owning suite must have names")
            if legacy:
                for field in ("errors", "failures", "skip"):
                    if int(case.get(field, "0") or 0) < 0:
                        raise ValueError("negative xUnit status count")
            status = qspec_xunit_status(case) if legacy else case_status(case)
            counts[suite_name, name] += 1
            occurrence = counts[suite_name, name]
            diagnostics = [
                {"kind": child.tag, "message": child.get("message", ""),
                 "text": "".join(child.itertext())}
                for child in case if child.tag in {"failure", "error", "skipped", "sysout", "system-out", "system-err"}
            ]
            rows.append({"suite": suite_name, "name": name, "occurrence": occurrence,
                         "status": status, "diagnostics": diagnostics})
    if not rows:
        raise ValueError("report contains no testcases")
    if len(rows) != len(list(root.iter(case_tag))):
        raise ValueError("testcases outside a named owning suite")
    return rows


def fields(obj: Any, allowed: set[str], where: str) -> None:
    if not isinstance(obj, dict) or set(obj) - allowed:
        raise ValueError(f"{where}: expected object with fields {sorted(allowed)}")


def environment(value: Any) -> dict[str, str | None]:
    if not isinstance(value, dict) or any(
        not isinstance(k, str) or not k or "=" in k or "\0" in k
        or (v is not None and (not isinstance(v, str) or "\0" in v))
        for k, v in value.items()
    ):
        raise ValueError("env must map variable names to strings or null (unset)")
    return value


def validate_config(config: Any, base: Path) -> dict[str, Any]:
    fields(config, {"schemaVersion", "cwd", "env", "timeoutSeconds", "upstream", "resq", "expectedDifferences"}, "config")
    if type(config.get("schemaVersion")) is not int or config["schemaVersion"] != 1:
        raise ValueError("schemaVersion must be 1")
    timeout = config.get("timeoutSeconds", 300)
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("timeoutSeconds must be positive and finite")
    environment(config.get("env", {}))
    result = dict(config, timeoutSeconds=timeout)
    for label in ("upstream", "resq"):
        runner = config.get(label)
        fields(runner, {"command", "cwd", "env", "report"}, label)
        argv = runner.get("command")
        if not isinstance(argv, list) or not argv or any(not isinstance(v, str) or "\0" in v for v in argv) or not argv[0]:
            raise ValueError(f"{label}.command must be a nonempty argv array")
        report = runner.get("report", "stdout")
        if report not in ("stdout", "file"):
            raise ValueError(f"{label}.report must be stdout or file")
        if report == "file" and not any("{report}" in arg for arg in argv):
            raise ValueError(f"{label}: file reports require a {{report}} command argument")
        cwd = runner.get("cwd", config.get("cwd", "."))
        if not isinstance(cwd, str) or not cwd:
            raise ValueError("cwd must be a nonempty path string")
        cwd = (base / cwd).resolve()
        if not cwd.is_dir():
            raise ValueError(f"{label}: cwd does not exist: {cwd}")
        result[label] = dict(runner, cwd=str(cwd), env=environment(runner.get("env", {})), report=report)
    expected = config.get("expectedDifferences", [])
    if not isinstance(expected, list):
        raise ValueError("expectedDifferences must be an array")
    seen = set()
    for entry in expected:
        fields(entry, {"suite", "name", "occurrence", "upstream", "resq", "reason"}, "allowance")
        if any(not isinstance(entry.get(k), str) or not entry[k].strip() for k in ("suite", "name", "reason")):
            raise ValueError("allowances require suite, name and a nonempty reason")
        n = entry.get("occurrence", 1)
        if type(n) is not int or n < 1:
            raise ValueError("occurrence must be a positive integer")
        if any(not isinstance(entry.get(k), str) or entry[k] not in STATUSES for k in ("upstream", "resq")) or entry["upstream"] == entry["resq"]:
            raise ValueError("allowances require two different recognized statuses")
        key = identity(entry["suite"], entry["name"], n)
        if key in seen:
            raise ValueError("duplicate allowance identity")
        seen.add(key)
    result["expectedDifferences"] = expected
    return result


def overlay(base: dict[str, str], changes: dict[str, str | None]) -> dict[str, str]:
    result = dict(base)
    for key, value in changes.items():
        if value is None:
            result.pop(key, None)
        else:
            result[key] = value
    return result


def execute(label: str, runner: dict[str, Any], env: dict[str, str], timeout: float, output: Path) -> dict[str, Any]:
    report = output / f"{label}.xml"
    argv = [arg.replace("{report}", str(report)) for arg in runner["command"]]
    result: dict[str, Any] = {"command": argv, "cwd": runner["cwd"], "reportSource": runner["report"],
                              "exitCode": None, "problems": [], "tests": []}
    started = time.monotonic()
    with (output / f"{label}.stdout").open("wb") as stdout, (output / f"{label}.stderr").open("wb") as stderr:
        try:
            completed = run_bounded(argv, cwd=runner["cwd"], env=overlay(env, runner["env"]),
                                    timeout=timeout, stdout=stdout, stderr=stderr)
            result["exitCode"] = completed.returncode
        except subprocess.TimeoutExpired:
            result["problems"].append(f"timeout after {timeout} seconds")
        except OSError as exc:
            result["problems"].append(f"could not execute: {exc}")
    result["durationSeconds"] = round(time.monotonic() - started, 6)
    source = output / f"{label}.stdout" if runner["report"] == "stdout" else report
    try:
        if source.is_symlink():
            raise ValueError("report must not be a symlink")
        result["tests"] = read_report(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError, ET.ParseError) as exc:
        result["problems"].append(f"unreadable report: {exc}")
    code = result["exitCode"]
    if code is not None:
        failed = any(t["status"] in {"fail", "error"} for t in result["tests"])
        if code < 0:
            result["problems"].append(f"terminated by signal {-code}")
        elif result["tests"] and ((code != 0) != failed):
            result["problems"].append(f"exit {code} contradicts testcase failures={failed}")
    result["counts"] = dict(Counter(t["status"] for t in result["tests"]))
    return result


def comparison(upstream: list[dict[str, Any]], resq: list[dict[str, Any]], expected: list[dict[str, Any]]) -> dict[str, Any]:
    def mapping(rows: list[dict[str, Any]]) -> dict[str, str]:
        return {identity(r["suite"], r["name"], r["occurrence"]): r["status"] for r in rows}
    listed = [dict(test=identity(e["suite"], e["name"], e.get("occurrence", 1)),
                   upstream=e["upstream"], resq=e["resq"]) for e in expected]
    unexpected, stale = compare(mapping(upstream), mapping(resq), listed)
    def unpack(row: dict[str, str]) -> dict[str, Any]:
        suite, name, occurrence = json.loads(row["test"])
        return dict(suite=suite, name=name, occurrence=occurrence, upstream=row["upstream"], resq=row["resq"])
    stale_keys = {row["test"] for row in stale}
    accepted = [e for e in expected if identity(e["suite"], e["name"], e.get("occurrence", 1)) not in stale_keys]
    return {"unexpectedDifferences": [unpack(r) for r in unexpected],
            "staleAllowances": [unpack(r) for r in stale], "acceptedDifferences": accepted}


def run(config_path: Path, output: Path) -> int:
    raw = config_path.read_bytes()
    config = validate_config(json.loads(raw), config_path.resolve().parent)
    output = output.resolve()
    # A new evidence directory prevents stale XML from surviving a crashed runner.
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    env = overlay(dict(os.environ), config.get("env", {}))
    runs = {label: execute(label, config[label], env, config["timeoutSeconds"], output)
            for label in ("upstream", "resq")}
    problems = [f"{label}: {p}" for label, r in runs.items() for p in r["problems"]]
    differences = comparison(runs["upstream"]["tests"], runs["resq"]["tests"], config["expectedDifferences"])
    code = 2 if problems else 1 if differences["unexpectedDifferences"] or differences["staleAllowances"] else 0
    evidence = {"schemaVersion": 1, "kind": "resq-qspec-parity", "configSha256": hashlib.sha256(raw).hexdigest(),
                "parity": code == 0, "suitesGreen": not problems and all(
                    r["counts"].get("pass", 0) > 0 and not any(r["counts"].get(s, 0) for s in ("fail", "error"))
                    for r in runs.values()),
                "exitCode": code, "problems": problems, "runs": runs, **differences,
                "environmentOverrideNames": {"shared": sorted(config.get("env", {})),
                    **{label: sorted(config[label]["env"]) for label in runs}}}
    evidence["artifacts"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted(output.iterdir()) if p.is_file() and not p.is_symlink()}
    (output / "parity.json").write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    lines = [f"Parity: {'PASS' if code == 0 else 'FAIL'}; suites green: {evidence['suitesGreen']}"]
    lines += [f"{label}: {len(r['tests'])} tests, exit {r['exitCode']}, {r['counts']}" for label, r in runs.items()]
    lines += problems
    for field in ("unexpectedDifferences", "staleAllowances", "acceptedDifferences"):
        lines += [f"{field}: {json.dumps(row, ensure_ascii=False)}" for row in differences[field]]
    lines.append(f"Evidence: {output / 'parity.json'}")
    text = "\n".join(lines) + "\n"
    (output / "summary.txt").write_text(text, encoding="utf-8")
    print(text, end="")
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="JSON command/config file; relative cwd paths resolve beside it")
    parser.add_argument("--out-dir", type=Path, required=True, help="new evidence directory (must not exist)")
    args = parser.parse_args()
    try:
        return run(args.config, args.out_dir)
    except (OSError, ValueError) as exc:
        print(f"parity configuration/output error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
