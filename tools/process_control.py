#!/usr/bin/env python3
"""Bound subprocesses and reap their complete process groups."""

from __future__ import annotations

import os
import signal
import subprocess
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import IO, Any


def _signal_group(process: subprocess.Popen[Any], sig: signal.Signals) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def run_bounded(
    command: Sequence[str], *, cwd: Path | str | None = None,
    env: Mapping[str, str] | None = None, timeout: float,
    kill_grace: float = 2.0, text: bool = True,
    stdin: int | IO[Any] | None = subprocess.DEVNULL,
    stdout: int | IO[Any] | None = None,
    stderr: int | IO[Any] | None = None,
) -> subprocess.CompletedProcess[Any]:
    """Run one command in a new session and kill all descendants on timeout."""
    if timeout <= 0 or kill_grace <= 0:
        raise ValueError("timeout and kill_grace must be positive")
    argv = [str(value) for value in command]
    process = subprocess.Popen(
        argv, cwd=cwd, env=env, text=text, stdin=stdin, stdout=stdout,
        stderr=stderr, start_new_session=True,
    )
    try:
        output, errors = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _signal_group(process, signal.SIGTERM)
        try:
            output, errors = process.communicate(timeout=kill_grace)
        except subprocess.TimeoutExpired:
            _signal_group(process, signal.SIGKILL)
            output, errors = process.communicate()
        raise subprocess.TimeoutExpired(
            argv, timeout, output=output, stderr=errors,
        ) from None
    return subprocess.CompletedProcess(argv, process.returncode, output, errors)
