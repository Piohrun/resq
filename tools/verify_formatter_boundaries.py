#!/usr/bin/env python3
"""Reject console-width-dependent q formatters outside the console reporter."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOKENS = (".Q.s1", "-3!")
ALLOWLIST = {Path("lib/output/text.q")}


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    column: int
    token: str


def code_lines(source: str) -> list[str]:
    """Return q source with comments blanked while retaining string literals."""
    output: list[str] = []
    block_comment = False
    for raw in source.splitlines():
        stripped = raw.strip()
        if block_comment:
            output.append("")
            if stripped == "\\":
                block_comment = False
            continue
        if stripped == "/":
            block_comment = True
            output.append("")
            continue

        quoted = False
        escaped = False
        end = len(raw)
        for index, char in enumerate(raw):
            if escaped:
                escaped = False
                continue
            if quoted and char == "\\":
                escaped = True
                continue
            if char == '"':
                quoted = not quoted
                continue
            if char == "/" and not quoted:
                # q comments start only at line start or after whitespace; a
                # "/" glued to code is an iterator (each/, +/, (f/)) and the
                # rest of the line is still code that must be scanned.
                if index == 0 or raw[index - 1] in " \t":
                    end = index
                    break
        output.append(raw[:end])
    return output


def scan_text(path: Path, source: str) -> list[Violation]:
    violations: list[Violation] = []
    for line_number, line in enumerate(code_lines(source), start=1):
        for token in TOKENS:
            start = 0
            while True:
                column = line.find(token, start)
                if column < 0:
                    break
                violations.append(Violation(path, line_number, column + 1, token))
                start = column + len(token)
    return violations


def production_q_files(root: Path = ROOT) -> list[Path]:
    return [root / "resq.q", *sorted((root / "lib").rglob("*.q"))]


def check(root: Path = ROOT) -> list[Violation]:
    violations: list[Violation] = []
    for path in production_q_files(root):
        relative = path.relative_to(root)
        if relative in ALLOWLIST:
            continue
        violations.extend(scan_text(relative, path.read_text(encoding="utf-8")))
    return violations


def main() -> int:
    violations = check()
    if violations:
        for violation in violations:
            print(
                f"{violation.path}:{violation.line}:{violation.column}: "
                f"forbidden geometry-dependent formatter {violation.token}",
                file=sys.stderr,
            )
        print(
            "formatter boundary verification failed: use canonical bytes for identity/equality, "
            "renderValueFull for evidence, or renderValueBounded in the console reporter",
            file=sys.stderr,
        )
        return 1
    print("formatter boundary verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
