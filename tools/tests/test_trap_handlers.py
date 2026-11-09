from __future__ import annotations

import unittest
from pathlib import Path

from tools.verify_trap_handlers import check, scan_text


def scan(source: str) -> list[str]:
    return [item.params for item in scan_text(Path("x.q"), source)]


class TrapHandlerContractTests(unittest.TestCase):
    def test_current_sources_pass(self) -> None:
        self.assertEqual([], check())

    def test_unprojected_two_argument_handler_is_rejected(self) -> None:
        source = "ok:.[{[p;t](hsym `$p) 0:enlist t;1b};(a;b);{[args;err]0b}];\n"
        self.assertEqual(["args;err"], scan(source))

    def test_multiline_handler_is_rejected(self) -> None:
        source = (
            "f:{[]\n"
            "    @[g;x;\n"
            "      {[file; e]\n"
            "        -1 e}]\n"
            " };\n"
        )
        self.assertEqual(["file;e"], scan(source))

    def test_projected_handler_is_accepted(self) -> None:
        self.assertEqual([], scan("@[g;x;{[name;e] -1 name,e}[name]];\n"))
        self.assertEqual([], scan(".[g;(a;b);{[args;err] -1 err}[(a;b);]];\n"))

    def test_single_argument_handler_is_accepted(self) -> None:
        self.assertEqual([], scan(".[g;(a;b);{[err]0b}];\n"))

    def test_other_bracket_calls_are_ignored(self) -> None:
        # .Q.trp passes (error; backtrace), and a lambda that is not the final
        # argument of a three-argument @[]/.[] is not a handler.
        self.assertEqual([], scan(".Q.trp[g;x;{[e;bt] -1 e}];\n"))
        self.assertEqual([], scan("@[d;i;{[a;b] a+b};y];\n"))
        self.assertEqual([], scan("{[a;b] a+b}'[x;y];\n"))

    def test_strings_and_comments_do_not_confuse_matching(self) -> None:
        self.assertEqual([], scan('-1 "@[f;x;{[a;b]0b}]";\n/ @[f;x;{[a;b]0b}]\n'))
        self.assertEqual(["a;b"], scan('@[f;"]";{[a;b]0b}];\n'))


if __name__ == "__main__":
    unittest.main()
