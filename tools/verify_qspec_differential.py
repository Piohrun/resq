#!/usr/bin/env python3
"""Compare upstream qspec and bin/qspec testcase by testcase on pinned suites.

The self-suite checks resQ against resQ's own reading of qspec. This check
runs the real thing: unmodified upstream qspec (nugend/qspec on nugend/qutil)
and bin/qspec execute the same vendored third-party suites the way a CI script
calls them (`--junit <dir> > results.xml`). Every testcase must appear in both
reports under the same suite and name with the same verdict, except for the
differences the manifest lists with a reason. A listed difference that no
longer occurs also fails, so the manifest cannot go stale.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "pilots/qspec-differential.json"
VENDOR = ROOT / "pilots/vendor"
LICENCES = {"MIT"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def vendored_files(root: Path) -> list[str]:
    # .resq/ is resQ's own state directory; a manual run may leave one behind.
    return sorted(
        path.relative_to(root).as_posix() for path in root.rglob("*")
        if path.is_file() and ".resq" not in path.relative_to(root).parts
    )


def verify_vendor(project: dict[str, Any]) -> Path:
    name = project["name"]
    root = (ROOT / project["root"]).resolve()
    try:
        root.relative_to(VENDOR)
    except ValueError as exc:
        raise RuntimeError(f"{name}: vendor root escapes {VENDOR}") from exc
    if project.get("license") not in LICENCES or not (root / "LICENSE").is_file():
        raise RuntimeError(f"{name}: missing declared licence")
    commit = project.get("commit", "")
    if len(commit) != 40 or any(char not in "0123456789abcdef" for char in commit):
        raise RuntimeError(f"{name}: commit is not a pinned SHA")
    expected = project["files"]
    actual = vendored_files(root)
    if sorted(expected) != actual:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise RuntimeError(f"{name}: vendored file set drifted; missing={missing} extra={extra}")
    for relative, digest in expected.items():
        if sha256(root / relative) != digest:
            raise RuntimeError(f"{name}: vendored hash drift for {relative}")
    return root


def extract_xml(stdout: str) -> str:
    """The report starts at the XML declaration or root; qutil may print first."""
    starts = [index for index in (stdout.find("<?xml"), stdout.find("<testsuites")) if index >= 0]
    if not starts:
        raise RuntimeError("no JUnit XML on stdout")
    return stdout[min(starts):]


def case_status(case: ElementTree.Element) -> str:
    if case.find("error") is not None:
        return "error"
    if case.find("failure") is not None:
        return "fail"
    if case.find("skipped") is not None:
        return "skip"
    return "pass"


def verdicts(xml_text: str) -> dict[str, str]:
    """Map "suite :: testcase name" to its verdict; repeats get a #n suffix."""
    root = ElementTree.fromstring(xml_text)
    result: dict[str, str] = {}
    for suite in root.iter("testsuite"):
        for case in suite.findall("testcase"):
            key = f"{suite.get('name', '')} :: {case.get('name', '')}"
            occurrence = 1
            unique = key
            while unique in result:
                occurrence += 1
                unique = f"{key} #{occurrence}"
            result[unique] = case_status(case)
    return result


def compare(
    upstream: dict[str, str], resq: dict[str, str], expected: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """Return (unexpected differences, listed differences that did not occur)."""
    observed = {
        (test, upstream.get(test, "absent"), resq.get(test, "absent"))
        for test in set(upstream) | set(resq)
        if upstream.get(test, "absent") != resq.get(test, "absent")
    }
    listed = {(entry["test"], entry["upstream"], entry["resq"]) for entry in expected}
    unexpected = [
        {"test": test, "upstream": up, "resq": rq} for test, up, rq in sorted(observed - listed)
    ]
    stale = [
        {"test": test, "upstream": up, "resq": rq} for test, up, rq in sorted(listed - observed)
    ]
    return unexpected, stale


def write_harness(work: Path, qspec: Path, qutil: Path) -> tuple[Path, Path, Path]:
    """QPATH layout of a qutil install, upstream's spec.q entry, and a q.q stand-in."""
    qpath = work / "qpath"
    qpath.mkdir()
    (qpath / "bootstrap.q").symlink_to(qutil / "lib/bootstrap.q")
    (qpath / "qutil").symlink_to(qutil / "lib", target_is_directory=True)
    (qpath / "qspec").symlink_to(qspec / "lib", target_is_directory=True)
    upstream = work / "upstream_spec.q"
    upstream.write_text(
        f'.utl.QPATH:enlist hsym `$"{qpath}";\n'
        f'system "l {qpath}/bootstrap.q";\n'
        f'system "l {qspec}/app/spec.q";\n',
        encoding="utf-8",
    )
    # qutil's documented install loads its bootstrap from q.q; QINIT stands in.
    qinit = work / "qinit.q"
    qinit.write_text(
        "{\n"
        ' pathSep:$["w" ~ first string .z.o;";";":"];\n'
        " .utl.QPATH: hsym each `$pathSep vs getenv x;\n"
        " bootstrap: b first where not 0 = (count key@) each b:` sv' .utl.QPATH,'`bootstrap.q;\n"
        ' system "l ", 1 _ string bootstrap;\n'
        " }[`QPATH]\n",
        encoding="utf-8",
    )
    return qpath, upstream, qinit


def run(command: list[str], cwd: Path, environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, cwd=cwd, env=environment, text=True, capture_output=True,
        stdin=subprocess.DEVNULL, check=False, timeout=300,
    )


def run_case(
    case: dict[str, Any], project_dir: Path, q_executable: str,
    qpath: Path, upstream_spec: Path, qinit: Path, output: Path,
) -> dict[str, Any]:
    name = case["name"]
    args = list(case["args"])
    base = dict(os.environ)
    base["QPATH"] = str(qpath)
    base.pop("QINIT", None)
    upstream = run([q_executable, str(upstream_spec), "-q", *args], project_dir, base)
    resq_environment = dict(base, QINIT=str(qinit), QBIN=q_executable)
    resq = run([str(ROOT / "bin/qspec"), *args], project_dir, resq_environment)
    for label, completed in (("upstream", upstream), ("resq", resq)):
        (output / f"{name}.{label}.stdout").write_text(completed.stdout, encoding="utf-8")
        (output / f"{name}.{label}.stderr").write_text(completed.stderr, encoding="utf-8")
    try:
        upstream_verdicts = verdicts(extract_xml(upstream.stdout))
        resq_verdicts = verdicts(extract_xml(resq.stdout))
    except (RuntimeError, ElementTree.ParseError) as exc:
        raise RuntimeError(f"{name}: unreadable JUnit report: {exc}") from exc
    if not upstream_verdicts:
        raise RuntimeError(f"{name}: upstream qspec ran no tests; the harness is broken")
    unexpected, stale = compare(upstream_verdicts, resq_verdicts, case.get("expectedDifferences", []))
    resq_failed = any(status in {"fail", "error"} for status in resq_verdicts.values())
    problems: list[str] = []
    if (resq.returncode != 0) != resq_failed:
        problems.append(f"bin/qspec exited {resq.returncode} but its report says failed={resq_failed}")
    if not unexpected and not case.get("expectedDifferences") \
            and (upstream.returncode == 0) != (resq.returncode == 0):
        problems.append(f"exit status differs: upstream {upstream.returncode}, bin/qspec {resq.returncode}")
    problems += [f"unexpected difference: {entry}" for entry in unexpected]
    problems += [f"listed difference no longer occurs: {entry}" for entry in stale]
    return {
        "name": name,
        "project": case["project"],
        "args": args,
        "tests": len(upstream_verdicts),
        "upstreamExit": upstream.returncode,
        "resqExit": resq.returncode,
        "upstreamPassed": sum(status == "pass" for status in upstream_verdicts.values()),
        "resqPassed": sum(status == "pass" for status in resq_verdicts.values()),
        "listedDifferences": len(case.get("expectedDifferences", [])),
        "problems": problems,
    }


def verify(q_executable: str, out_dir: Path | None) -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1:
        raise RuntimeError("qspec differential manifest must be schema v1")
    projects = {project["name"]: project for project in manifest["projects"]}
    roots = {name: verify_vendor(project) for name, project in projects.items()}
    harness = manifest["harness"]
    with tempfile.TemporaryDirectory(prefix="resq-qspec-differential-") as directory:
        work = Path(directory)
        # Run on copies: both runners write state and fixtures into the cwd.
        copies = {}
        for name, root in roots.items():
            copies[name] = work / "corpus" / name
            shutil.copytree(root, copies[name], ignore=shutil.ignore_patterns(".resq"))
        qpath, upstream_spec, qinit = write_harness(
            work, copies[harness["qspec"]], copies[harness["qutil"]])
        output = out_dir.resolve() if out_dir is not None else work / "evidence"
        output.mkdir(parents=True, exist_ok=True)
        results = [
            run_case(case, copies[case["project"]], q_executable, qpath, upstream_spec, qinit, output)
            for case in manifest["cases"]
        ]
        evidence = {
            "schemaVersion": 1,
            "kind": "resq-qspec-differential-evidence",
            "q": q_executable,
            "cases": results,
        }
        (output / "qspec-differential-evidence.json").write_text(
            json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    failed = False
    for result in results:
        mark = "FAIL" if result["problems"] else "ok"
        print(
            f"{mark:4} {result['name']:<28} tests={result['tests']:<3} "
            f"passed upstream={result['upstreamPassed']} resQ={result['resqPassed']} "
            f"listed differences={result['listedDifferences']}"
        )
        for problem in result["problems"]:
            print(f"     {problem}")
        failed = failed or bool(result["problems"])
    if failed:
        return 1
    total = sum(result["tests"] for result in results)
    print(
        f"qspec differential passed: {len(results)} script-style runs, {total} testcases "
        "with identical names and verdicts apart from listed differences"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"), help="q executable")
    parser.add_argument("--out-dir", type=Path, help="keep reports and evidence here")
    args = parser.parse_args()
    try:
        return verify(args.q, args.out_dir)
    except (
        OSError, subprocess.SubprocessError, json.JSONDecodeError,
        KeyError, TypeError, ValueError, RuntimeError,
    ) as exc:
        print(f"qspec differential failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
