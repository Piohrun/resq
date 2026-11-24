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


def state_files(root: Path) -> dict[str, tuple[int, int]]:
    """Every file resQ keeps between runs under `root`, with size and mtime."""
    found: dict[str, tuple[int, int]] = {}
    state_dir = root / ".resq"
    if state_dir.is_dir():
        for path in sorted(state_dir.rglob("*")):
            if path.is_file():
                status = path.stat()
                found[str(path.relative_to(root))] = (status.st_size, status.st_mtime_ns)
    return found


def path_without(tools: set[str], destination: Path) -> str:
    """A PATH directory with every command of the current PATH except `tools`."""
    destination.mkdir()
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        if not directory or not os.path.isdir(directory):
            continue
        for entry in os.scandir(directory):
            link = destination / entry.name
            if entry.name in tools or link.is_symlink() or link.exists():
                continue
            try:
                link.symlink_to(entry.path)
            except OSError:
                continue
    return str(destination)


def run_checked(command: list[str], environment: dict[str, str], cwd: Path) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command, cwd=cwd, env=environment, text=True, capture_output=True,
        stdin=subprocess.DEVNULL, timeout=90, check=False,
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
            stdin=subprocess.DEVNULL,
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

        # signal cleanup: target only the launcher (not its process group) and
        # prove its INT/TERM traps forward, reap, clean private state, and return
        # conventional shell signal codes.
        pid_a = hostile_parent / "child a.pid"
        pid_b = hostile_parent / "child b.pid"
        pid_c = hostile_parent / "child c.pid"
        pid_d = hostile_parent / "child d.pid"
        hang_a = fixture_dir / "test hang a.q"
        hang_b = fixture_dir / "test hang b.q"
        hang_c = fixture_dir / "test hang c.q"
        hang_d = fixture_dir / "test hang d.q"
        write_hang(hang_a, pid_a, "interrupt a")
        write_hang(hang_b, pid_b, "interrupt b")
        # A second batch: a run that has been told to stop must not start it.
        write_hang(hang_c, pid_c, "interrupt c")
        write_hang(hang_d, pid_d, "interrupt d")
        signal_reports = hostile_parent / "signal reports"
        # A machine without setsid, pkill and pgrep: q then shares the
        # launcher's process group, and its children are in groups of their
        # own, out of reach of a signal sent to q.
        bare_environment = dict(environment)
        bare_environment["PATH"] = path_without(
            {"setsid", "pkill", "pgrep"}, hostile_parent / "bare path"
        )
        # A hangup reaches the launcher when a terminal or SSH session closes;
        # q runs in its own session and never sees it. bin/qspec --junit runs
        # the launcher as a child and has to pass every signal on.
        resq_launcher = [str(install / "bin/resq"), "test"]
        qspec_launcher = [str(install / "bin/qspec"), "--junit"]
        signal_cases = (
            (resq_launcher, signal.SIGINT, 130, environment),
            (resq_launcher, signal.SIGTERM, 143, environment),
            (resq_launcher, signal.SIGHUP, 129, environment),
            (qspec_launcher, signal.SIGINT, 130, environment),
            (qspec_launcher, signal.SIGTERM, 143, environment),
            (qspec_launcher, signal.SIGHUP, 129, environment),
            (resq_launcher, signal.SIGINT, 130, bare_environment),
            (resq_launcher, signal.SIGTERM, 143, bare_environment),
        )
        for launcher, signum, expected_status, case_environment in signal_cases:
            for pid_file in (pid_a, pid_b, pid_c, pid_d):
                pid_file.unlink(missing_ok=True)
            shutil.rmtree(signal_reports, ignore_errors=True)
            # bin/qspec --junit prints its report; an -outDir would bypass that path.
            report_flags = (
                ["-json", "-outDir", str(signal_reports)] if launcher is resq_launcher else []
            )
            state_before = state_files(hostile_parent)
            process = subprocess.Popen(
                [
                    *launcher, str(hang_a), str(hang_b), str(hang_c), str(hang_d),
                    "-isolate", "-isolateWorkers", "2", "-isolateTimeout", "300", "-quiet",
                    *report_flags,
                ],
                cwd=hostile_parent,
                env=case_environment,
                stdin=subprocess.DEVNULL,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                ready = wait_for(lambda: pid_a.is_file() and pid_b.is_file())
                if not ready:
                    raise RuntimeError("isolated children did not reach the signal fixture")
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
                os.kill(process.pid, signum)
                status = process.wait(timeout=15)
                if status != expected_status:
                    raise RuntimeError(
                        f"{Path(launcher[0]).name} signal {signum} returned {status}, "
                        f"expected {expected_status}"
                    )
                wait_for(lambda: not any(alive(pid) for pid in pids), seconds=5)
                survivors = [pid for pid in pids if alive(pid)]
                if survivors:
                    raise RuntimeError(f"signalled isolated children survived: {survivors!r}")
                if list(hostile_parent.glob("resq-run-guard.*")):
                    raise RuntimeError("launcher-owned scratch survived signal cleanup")
                if list(hostile_parent.glob("resq-qspec.*")):
                    raise RuntimeError("qspec report scratch survived signal cleanup")
                # The run was told to stop. It must not start the next batch,
                # and must not publish what it has: a report or a state file
                # from a run that was cut short is false evidence.
                time.sleep(1.5)
                late = [path for path in (pid_c, pid_d) if path.is_file()]
                late_alive = [path.name for path in late if alive(int(path.read_text().strip()))]
                if late_alive:
                    raise RuntimeError(
                        f"signal {signum}: children started after the signal are still running: "
                        f"{late_alive!r}"
                    )
                if late:
                    raise RuntimeError(
                        f"signal {signum}: a batch was started after the signal: "
                        f"{[path.name for path in late]!r}"
                    )
                written = sorted(path.name for path in signal_reports.glob("*")) if signal_reports.is_dir() else []
                if written:
                    raise RuntimeError(f"signal {signum}: an interrupted run wrote reports: {written!r}")
                if state_files(hostile_parent) != state_before:
                    raise RuntimeError(f"signal {signum}: an interrupted run changed its state files")
                output = process.stdout.read() if process.stdout is not None else ""
                # q ends at a hangup without a word; at INT and TERM it runs on,
                # so the run itself has to say why it stopped.
                if signum != signal.SIGHUP and "interrupted" not in output:
                    raise RuntimeError(
                        f"signal {signum}: the run did not say it was interrupted:\n{output[-2000:]}"
                    )
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
        "INT/TERM/HUP signal cleanup through bin/resq and bin/qspec --junit "
        "(also without setsid/pkill: no later batch, no report, no state change), "
        "conventional status, reaping, and cleanup"
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
