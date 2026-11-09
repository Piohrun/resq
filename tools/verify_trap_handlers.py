#!/usr/bin/env python3
"""Reject trap handlers that take more than the error argument.

q calls the handler of `@[f;x;h]` and `.[f;x;h]` with the error alone. A
handler written as `{[args;err] ...}` is therefore projected rather than run:
it returns a function, and whatever the caller does with that value next
(`not written`, `$[moved;...]`) signals 'type. In resQ 2.2.0 this turned every
failed state write into a failed run. A handler that needs more context must
be projected at the call site: `{[path;err] ...}[path]`.

The same shape in the amend forms `@[d;i;f]` / `.[d;i;f]` is equally wrong,
since amend also calls `f` with one argument.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from verify_formatter_boundaries import code_lines, production_q_files  # noqa: E402

LAMBDA = re.compile(r"\{\[\s*([A-Za-z_][\w.]*(?:\s*;\s*[A-Za-z_][\w.]*)+)\s*\]")
OPENERS = "([{"
CLOSERS = ")]}"


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    params: str


def mask_strings(line: str) -> str:
    """Blank string-literal contents so brackets inside them are not matched."""
    out: list[str] = []
    quoted = False
    escaped = False
    for char in line:
        if quoted:
            if escaped:
                escaped = False
                out.append(" ")
            elif char == "\\":
                escaped = True
                out.append(" ")
            elif char == '"':
                quoted = False
                out.append(char)
            else:
                out.append(" ")
        else:
            if char == '"':
                quoted = True
            out.append(char)
    return "".join(out)


def enclosing_opener(text: str, start: int) -> int | None:
    """Index of the unmatched opener that contains position `start`."""
    depth = 0
    for index in range(start - 1, -1, -1):
        char = text[index]
        if char in CLOSERS:
            depth += 1
        elif char in OPENERS:
            if depth == 0:
                return index
            depth -= 1
    return None


def matching_close(text: str, start: int) -> int | None:
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char in OPENERS:
            depth += 1
        elif char in CLOSERS:
            depth -= 1
            if depth == 0:
                return index
    return None


def top_level_separators(text: str, opener: int, close: int) -> int:
    depth = 0
    count = 0
    for char in text[opener + 1:close]:
        if char in OPENERS:
            depth += 1
        elif char in CLOSERS:
            depth -= 1
        elif char == ";" and depth == 0:
            count += 1
    return count


def scan_text(path: Path, source: str) -> list[Violation]:
    text = "\n".join(mask_strings(line) for line in code_lines(source))
    violations: list[Violation] = []
    for match in LAMBDA.finditer(text):
        start = match.start()
        opener = enclosing_opener(text, start)
        if opener is None or text[opener] != "[" or opener == 0 or text[opener - 1] not in "@.":
            continue
        lambda_end = matching_close(text, start)
        if lambda_end is None:
            continue
        after = lambda_end + 1
        if text[after:after + 1] == "[":
            continue  # projected at the call site
        while after < len(text) and text[after] in " \t\r\n":
            after += 1
        if text[after:after + 1] != "]":
            continue  # not the final argument
        bracket_end = matching_close(text, opener)
        if bracket_end is None or top_level_separators(text, opener, bracket_end) != 2:
            continue  # only the three-argument trap/amend forms
        line = text.count("\n", 0, start) + 1
        params = re.sub(r"\s+", "", match.group(1))
        violations.append(Violation(path, line, params))
    return violations


def check(root: Path = ROOT) -> list[Violation]:
    violations: list[Violation] = []
    for path in production_q_files(root):
        violations.extend(scan_text(path.relative_to(root), path.read_text(encoding="utf-8")))
    return violations


def main() -> int:
    violations = check()
    for item in violations:
        print(f"{item.path}:{item.line}: unprojected handler {{[{item.params}]...}}", file=sys.stderr)
    if violations:
        return 1
    print("trap handler check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
