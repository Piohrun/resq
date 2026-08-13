#!/usr/bin/env python3
"""Verify resQ CLI verdict and -pass behavior with pipe and pseudo-TTY stdin."""

from __future__ import annotations

import argparse
import errno
import os
import pty
import select
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FRAMEWORK_MARKERS = (
    "Loading Test:",
    "RUN AUDIT",
    "SUMMARY",
    "All tests passed",
    "Tests FAILED",
    "Report written to",
    "FAILURE DIFF",
)
APPLICATION_MARKER = "RESQ_APPLICATION_OUTPUT"


def run_command(
    command: list[str], environment: dict[str, str], *, tty_stdin: bool,
) -> tuple[int, str]:
    if not tty_stdin:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=60,
        )
        return completed.returncode, completed.stdout

    master, slave = pty.openpty()
    process = subprocess.Popen(
        command,
        cwd=ROOT,
        env=environment,
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)
    chunks: list[bytes] = []
    deadline = time.monotonic() + 60
    try:
        while process.poll() is None or select.select([master], [], [], 0)[0]:
            if time.monotonic() >= deadline:
                process.kill()
                raise RuntimeError(f"pseudo-TTY command timed out: {command!r}")
            ready, _, _ = select.select([master], [], [], 0.1)
            if not ready:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            chunks.append(chunk)
        return process.wait(timeout=5), b"".join(chunks).decode("utf-8", "replace").replace("\r", "")
    finally:
        os.close(master)


def assert_pass_contract(output: str, label: str) -> None:
    if APPLICATION_MARKER not in output:
        raise AssertionError(f"{label}: application/test output was suppressed\n{output}")
    leaked = [marker for marker in FRAMEWORK_MARKERS if marker in output]
    if leaked:
        raise AssertionError(f"{label}: resQ framework chatter leaked: {leaked}\n{output}")
    if "KDB+" in output:
        raise AssertionError(f"{label}: q quiet-startup banner leaked\n{output}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--q", default=os.environ.get("QBIN", "q"))
    args = parser.parse_args()
    environment = dict(os.environ)
    environment["QBIN"] = args.q

    with tempfile.TemporaryDirectory(prefix="resq-cli-terminal-") as raw:
        work = Path(raw)
        passing = work / "test_terminal_pass.q"
        failing = work / "test_terminal_fail.q"
        passing.write_text(
            f'-1 "{APPLICATION_MARKER}";\n'
            '.tst.desc["terminal contract"]{ should["passes"]{ 1 musteq 1; }; };\n',
            encoding="utf-8",
        )
        failing.write_text(
            f'-1 "{APPLICATION_MARKER}";\n'
            '.tst.desc["terminal contract"]{ should["fails"]{ 1 musteq 2; }; };\n',
            encoding="utf-8",
        )

        observed: dict[tuple[str, bool], int] = {}
        for fixture, expected in ((passing, 0), (failing, 1)):
            for tty_stdin in (False, True):
                mode = "tty" if tty_stdin else "redirected"
                out_dir = work / f"{fixture.stem}-{mode}"
                command = [
                    str(ROOT / "bin/resq"), "test", str(fixture), "-pass", "-json",
                    "-outDir", str(out_dir),
                ]
                code, output = run_command(command, environment, tty_stdin=tty_stdin)
                label = f"{fixture.name}/{mode}"
                if code != expected:
                    raise AssertionError(f"{label}: expected exit {expected}, got {code}\n{output}")
                assert_pass_contract(output, label)
                if (out_dir / "test-results.json").exists():
                    raise AssertionError(f"{label}: -pass wrote a JSON report")
                observed[(fixture.name, tty_stdin)] = code

        for fixture in (passing, failing):
            if observed[(fixture.name, False)] != observed[(fixture.name, True)]:
                raise AssertionError(f"{fixture.name}: TTY changed the exit code")

        code, output = run_command(
            [str(ROOT / "bin/resq"), "test", str(passing)],
            environment,
            tty_stdin=False,
        )
        if code != 0 or APPLICATION_MARKER not in output or "SUMMARY" not in output:
            raise AssertionError(f"normal output did not retain application and framework output\n{output}")

    print("resQ CLI terminal verification passed: TTY/non-TTY exits match and -pass suppresses only framework chatter")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
