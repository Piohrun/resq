#!/usr/bin/env python3
"""Execute every README q fence and sandbox-run every shell fence.

q examples exercise the real framework with a tiny documented-example prelude.
Shell examples include installation and full-suite commands, so they execute
against command-recording shims: this validates shell parsing, continuations,
and command invocation without cloning, writing to a user's home, or recursively
running the release suite from its own documentation test.

The shims record what they were given. Every `resq` and `qspec` command the
README shows is then put through resQ's own command-line parser, so an option
that does not exist, or has been renamed, fails here; and a path into the
installed resQ (~/.local/share/resq/...) has to exist in this checkout.
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
        "printf '%s\\n' \"$0 $*\" >> \"$RESQ_DOC_COMMAND_LOG\"\n"
        # Each argument as it was given, quoting and all.
        "{ printf 'CMD %s\\n' \"${0##*/}\"; for a in \"$@\"; do printf 'ARG %s\\n' \"$a\"; done; "
        "printf 'END\\n'; } >> \"$RESQ_DOC_ARGV_LOG\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def recorded_commands(log: Path) -> list[tuple[str, list[str]]]:
    commands: list[tuple[str, list[str]]] = []
    name, args = "", []
    if not log.exists():
        return commands
    for line in log.read_text(encoding="utf-8").splitlines():
        if line.startswith("CMD "):
            name, args = line[4:], []
        elif line.startswith("ARG "):
            args.append(line[4:])
        elif line == "END":
            commands.append((name, args))
    return commands


# q's own single-letter options; bin/resq passes them to q, with their value.
Q_OPTIONS = set("bcCeEglLmopPrsStTuUwWz")


def launcher_argv(name: str, args: list[str]) -> list[str]:
    """What bin/resq or bin/qspec hands resQ's parser for these arguments."""
    out: list[str] = []
    skip_value = False
    for index, arg in enumerate(args):
        if skip_value:
            skip_value = False
            continue
        if arg in ("-args", "--args"):
            out.extend(args[index:])
            break
        if arg == "-h":
            out.append("--help")
        elif arg == "-v":
            out.append("--version")
        elif arg == "--":
            out.append("-paths")
        elif arg == "-q":
            continue
        elif len(arg) == 2 and arg[0] == "-" and arg[1] in Q_OPTIONS:
            skip_value = index + 1 < len(args) and not args[index + 1].startswith("-")
        else:
            out.append(arg)
    if name == "qspec":
        out = ["test", *out, "-qspec-compat", "-qspec-discovery"]
    return out


def q_string(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + escaped + '"'


def check_commands(commands: list[tuple[str, list[str]]], home: Path, q_executable: str) -> int:
    """Parse each documented command as resQ would; check bundled paths exist."""
    checked = [(name, args) for name, args in commands if name in ("resq", "qspec")]
    if not checked:
        raise RuntimeError("README shows no resq or qspec command")
    install = home / ".local/share/resq"
    for _, args in checked:
        for arg in args:
            if arg.startswith(str(install) + "/"):
                inside = ROOT / Path(arg).relative_to(install)
                if not inside.exists():
                    raise RuntimeError(f"README names {arg}, but {inside.relative_to(ROOT)} does not exist")
    lines = [f'system "l {str(ROOT / "lib/init.q")}";', "bad:();"]
    for name, args in checked:
        argv = launcher_argv(name, args)
        items = "; ".join(q_string(a) for a in argv) if argv else ""
        literal = f"enlist {items}" if len(argv) == 1 else f"({items})"
        shown = q_string(" ".join([name, *args]))
        lines.append(
            f"r: @[.tst.parseCLI; {literal}; {{[e] `error!enlist e}}]; "
            f"if[count r`error; bad,: enlist {shown}, \": \", r`error];"
        )
    lines.append('if[count bad; -2 each bad; exit 1];')
    lines.append("exit 0;")
    with tempfile.TemporaryDirectory(prefix="resq-readme-cli-") as raw:
        script = Path(raw) / "parse.q"
        script.write_text("\n".join(lines) + "\n", encoding="utf-8")
        completed = subprocess.run(
            [q_executable, str(script), "-q"], cwd=ROOT, text=True,
            stdin=subprocess.DEVNULL, capture_output=True, check=False,
            timeout=Q_TIMEOUT_SECONDS,
        )
    if completed.returncode != 0:
        raise RuntimeError("README commands resQ does not accept:\n" + completed.stderr + completed.stdout)
    return len(checked)


def execute_shell_examples(q_executable: str = "q") -> tuple[int, int]:
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
        argv_log = work / "argv.log"
        environment = dict(os.environ)
        environment.update(
            HOME=str(work / "home"),
            PATH=f"{shims}{os.pathsep}{environment.get('PATH', '')}",
            RESQ_DOC_COMMAND_LOG=str(log),
            RESQ_DOC_ARGV_LOG=str(argv_log),
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
        parsed = check_commands(recorded_commands(argv_log), work / "home", q_executable)
    return len(blocks), parsed


def verify(q_executable: str = "q") -> tuple[int, int]:
    discovered = examples()
    if not discovered:
        raise RuntimeError("README contains no executable q/bash fences")
    q_count = execute_q_examples(q_executable)
    shell_count, parsed = execute_shell_examples(q_executable)
    return q_count, shell_count, parsed


if __name__ == "__main__":
    q_count, shell_count, parsed = verify(os.environ.get("QBIN", "q"))
    print(f"README examples passed: {q_count} q fences, {shell_count} shell fences, "
          f"{parsed} resq/qspec commands accepted by the parser")
