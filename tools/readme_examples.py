#!/usr/bin/env python3
"""Execute every README q fence and sandbox-run every shell fence.

q examples exercise the real framework with a tiny documented-example prelude.
Shell examples include installation and full-suite commands, so they execute
against command-recording shims: this validates shell parsing, continuations,
and command invocation without cloning, writing to a user's home, or recursively
running the release suite from its own documentation test.
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
FENCE = re.compile(r"^```([^\n]*)\n(.*?)^```\s*$", re.MULTILINE | re.DOTALL)
SUPPORTED_LANGUAGES = {"q", "bash"}
Q_TIMEOUT_SECONDS = 30
SHELL_TIMEOUT_SECONDS = 10


def examples() -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    for match in FENCE.finditer(README.read_text(encoding="utf-8")):
        language = match.group(1).strip()
        if language in SUPPORTED_LANGUAGES:
            found.append((language, match.group(2)))
    return found


def q_prelude() -> str:
    init = str(ROOT / "lib/init.q").replace("\\", "/")
    return (
        f'system "l {init}";\n'
        "sma:{[window;values] window mavg values};\n"
        "data:1000?100f;\n"
        ".myFunc:{[]42};\n"
    )


def execute_q_examples(q_executable: str = "q") -> int:
    blocks = [body for language, body in examples() if language == "q"]
    with tempfile.TemporaryDirectory(prefix="resq-readme-q-") as raw:
        work = Path(raw)
        for index, body in enumerate(blocks, start=1):
            script = work / f"example-{index}.q"
            script.write_text(q_prelude() + body + "\nexit 0;\n", encoding="utf-8")
            completed = subprocess.run(
                [q_executable, "-q", str(script)], cwd=ROOT, text=True,
                stdin=subprocess.DEVNULL, capture_output=True, check=False,
                timeout=Q_TIMEOUT_SECONDS,
            )
            if completed.returncode != 0:
                raise RuntimeError(
                    f"README q fence {index} exited {completed.returncode}\n"
                    f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
                )
    return len(blocks)


def _write_command_shim(path: Path) -> None:
    path.write_text(
        "#!/bin/sh\n"
        "printf '%s\\n' \"$0 $*\" >> \"$RESQ_DOC_COMMAND_LOG\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def execute_shell_examples() -> int:
    blocks = [body for language, body in examples() if language == "bash"]
    with tempfile.TemporaryDirectory(prefix="resq-readme-shell-") as raw:
        work = Path(raw)
        shims = work / "shims"
        shims.mkdir()
        for command in ("git", "ln", "resq", "qspec", "q", "mkdir", "cp"):
            _write_command_shim(shims / command)
        merge = work / "bin/resq-merge"
        merge.parent.mkdir()
        _write_command_shim(merge)

        log = work / "commands.log"
        environment = dict(os.environ)
        environment.update(
            HOME=str(work / "home"),
            PATH=f"{shims}{os.pathsep}{environment.get('PATH', '')}",
            RESQ_DOC_COMMAND_LOG=str(log),
        )
        for index, body in enumerate(blocks, start=1):
            before = len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0
            completed = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c", body], cwd=work,
                env=environment, text=True, stdin=subprocess.DEVNULL,
                capture_output=True, check=False, timeout=SHELL_TIMEOUT_SECONDS,
            )
            if completed.returncode != 0:
                raise RuntimeError(
                    f"README bash fence {index} exited {completed.returncode}\n"
                    f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
                )
            after = len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0
            if after <= before:
                raise RuntimeError(f"README bash fence {index} invoked no command")
    return len(blocks)


def verify(q_executable: str = "q") -> tuple[int, int]:
    discovered = examples()
    if not discovered:
        raise RuntimeError("README contains no executable q/bash fences")
    q_count = execute_q_examples(q_executable)
    shell_count = execute_shell_examples()
    return q_count, shell_count


if __name__ == "__main__":
    q_count, shell_count = verify(os.environ.get("QBIN", "q"))
    print(f"README examples passed: {q_count} q fences, {shell_count} shell fences")
