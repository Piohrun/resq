#!/usr/bin/env python3
"""Exercise resQ's shell, path, temporary-file, and interruption boundaries."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_report import validate  # noqa: E402


def q_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def wait_for(predicate, seconds: float = 15.0) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def assert_private(path: Path) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o700:
        raise RuntimeError(f"temporary directory is {mode:o}, expected 700: {path}")


def write_pass(path: Path, label: str) -> None:
    path.write_text(
        f'.tst.desc["{label}"]{{ should["passes"]{{ 1 musteq 1 }}; }};\n',
        encoding="utf-8",
    )


def write_hang(path: Path, pid_path: Path, label: str) -> None:
    path.write_text(
        f'(hsym `$"{q_string(str(pid_path))}") 0: enlist string .z.i;\n'
        f'.tst.desc["{label}"]{{ should["hangs"]{{ while[1b;()] }}; }};\n',
        encoding="utf-8",
    )


def run_checked(command: list[str], environment: dict[str, str], cwd: Path) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command, cwd=cwd, env=environment, text=True, capture_output=True,
        timeout=90, check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command exited {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def verify(q_executable: str) -> None:
    hostile_parent = Path(tempfile.mkdtemp(prefix="resq hostile ' ; dollar $ ["))
    try:
        install = hostile_parent / "install link"
        install.symlink_to(ROOT, target_is_directory=True)
        q_log = hostile_parent / "q invocations.log"
        q_wrapper = hostile_parent / "q wrapper ' ; $.sh"
        q_wrapper.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$$\" >> \"$RESQ_Q_LOG\"\n"
            f'exec "{q_string(str(Path(q_executable).resolve()))}" "$@"\n',
            encoding="utf-8",
        )
        q_wrapper.chmod(0o700)
        fixture_dir = hostile_parent / "tests ' ; $ [dir]"
        fixture_dir.mkdir()
        fixture_a = fixture_dir / "test a.q"
        fixture_b = fixture_dir / "test b.q"
        write_pass(fixture_a, "hostile path a")
        write_pass(fixture_b, "hostile path b")
        report_dir = hostile_parent / "reports ' ; $ [dir]"
        injection_marker = hostile_parent / "MUST_NOT_EXIST"
        environment = dict(os.environ)
        environment.update(
            QBIN=str(q_wrapper), RESQ_Q_LOG=str(q_log), TMPDIR=str(hostile_parent)
        )

        # Symlinked install, explicit q binary, concurrent isolation, and every
        # machine reporter must all survive shell metacharacters in paths.
        run_checked(
            [
                str(install / "bin/resq"), "test", str(fixture_a), str(fixture_b),
                "-strict", "-isolate", "-isolateWorkers", "2", "-junit",
                "-xunit", "-json", "-outDir", str(report_dir), "-quiet",
            ],
            environment,
            hostile_parent,
        )
        report = json.loads((report_dir / "test-results.json").read_text(encoding="utf-8"))
        validate(report)
        if report["summary"]["passCount"] != 2:
            raise RuntimeError("hostile-path isolated run did not preserve both tests")
        ElementTree.parse(report_dir / "test-results.junit.xml")
        ElementTree.parse(report_dir / "test-results.xunit.xml")
        invocations = q_log.read_text(encoding="utf-8").splitlines()
        if len(invocations) < 3:
            raise RuntimeError("QBIN was not propagated from parent to isolated children")
        if injection_marker.exists():
            raise RuntimeError("hostile path text was evaluated by a shell")

        relative_report = "relative reports ' ; $ [dir]"
        run_checked(
            [
                str(install / "bin/resq"), "test", str(fixture_a), "-strict",
                "-json", "-outDir", relative_report, "-quiet",
            ],
            environment,
            hostile_parent,
        )
        relative_document = json.loads(
            (hostile_parent / relative_report / "test-results.json").read_text(encoding="utf-8")
        )
        validate(relative_document)

        blocked = hostile_parent / "artifact path is a file"
        blocked.write_text("not a directory", encoding="utf-8")
        failed_report = subprocess.run(
            [
                str(install / "bin/resq"), "test", str(fixture_a), "-strict",
                "-json", "-outDir", str(blocked), "-quiet",
            ],
            cwd=hostile_parent,
            env=environment,
            text=True,
            capture_output=True,
            timeout=90,
            check=False,
        )
        if failed_report.returncode == 0 or "REPORTER_FAILURE" not in (
            failed_report.stdout + failed_report.stderr
        ):
            raise RuntimeError("an unwritable artifact destination did not fail closed")

        # Direct q invocation is supported for embedded/noquit use and must
        # also load a framework whose path contains whitespace.
        run_checked(
            [q_executable, str(install / "resq.q"), "test", str(fixture_a), "-strict", "-quiet"],
            environment,
            hostile_parent,
        )

        # Start two unbounded children, inspect live permissions, then interrupt
        # the whole foreground group. No q child or launcher-owned scratch may
        # survive the interruption.
        pid_a = hostile_parent / "child a.pid"
        pid_b = hostile_parent / "child b.pid"
        hang_a = fixture_dir / "test hang a.q"
        hang_b = fixture_dir / "test hang b.q"
        write_hang(hang_a, pid_a, "interrupt a")
        write_hang(hang_b, pid_b, "interrupt b")
        process = subprocess.Popen(
            [
                str(install / "bin/resq"), "test", str(hang_a), str(hang_b),
                "-isolate", "-isolateWorkers", "2", "-isolateTimeout", "300", "-quiet",
            ],
            cwd=hostile_parent,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            ready = wait_for(lambda: pid_a.is_file() and pid_b.is_file())
            if not ready:
                raise RuntimeError("isolated children did not reach the interrupt fixture")
            guards = list(hostile_parent.glob("resq-run-guard.*"))
            if len(guards) != 1:
                raise RuntimeError(f"expected one live launcher guard, got {guards!r}")
            assert_private(guards[0])
            assert_private(guards[0] / "isolate")
            scratches = list((guards[0] / "isolate").glob("resq_isolate.*"))
            if len(scratches) != 2:
                raise RuntimeError(f"expected two live isolation scratches, got {scratches!r}")
            for scratch in scratches:
                assert_private(scratch)
            pids = [int(pid_a.read_text().strip()), int(pid_b.read_text().strip())]
            os.killpg(process.pid, signal.SIGINT)
            process.wait(timeout=15)
            wait_for(lambda: not any(alive(pid) for pid in pids), seconds=5)
            survivors = [pid for pid in pids if alive(pid)]
            if survivors:
                raise RuntimeError(f"interrupted isolated children survived: {survivors!r}")
            if list(hostile_parent.glob("resq-run-guard.*")):
                raise RuntimeError("launcher-owned scratch survived interruption")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            if process.stdout is not None:
                process.stdout.close()
    finally:
        shutil.rmtree(hostile_parent, ignore_errors=True)

    print(
        "hostile-environment verification passed: quoting, symlinked/spaced install, "
        "QBIN propagation, reporter anchoring/fail-closed writes, 0700 scratch, "
        "interrupt reaping, and cleanup"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--q", default="q", help="q executable (default: q)")
    args = parser.parse_args()
    try:
        verify(shutil.which(args.q) or args.q)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, ValueError, RuntimeError) as exc:
        print(f"hostile-environment verification failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
