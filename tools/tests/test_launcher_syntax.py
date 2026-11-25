"""Each launcher's syntax is checked on its own.

`bash -n bin/resq bin/qspec bin/resq-merge` checks bin/resq only: the other
names become its arguments. CI ran exactly that.
"""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from tools.verify_static import LAUNCHERS, ROOT, check_launchers


class LauncherSyntaxTests(unittest.TestCase):
    def test_the_launchers_parse(self) -> None:
        self.assertEqual(check_launchers(), len(LAUNCHERS))

    def test_a_broken_launcher_after_the_first_is_found(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / "bin").mkdir()
            for name in LAUNCHERS:
                shutil.copy(ROOT / name, root / name)
            broken = root / LAUNCHERS[-1]
            broken.write_text(broken.read_text(encoding="utf-8") + "\nif then\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, LAUNCHERS[-1]):
                check_launchers(root)

    def test_the_release_gate_checks_each_launcher(self) -> None:
        # Its first step ran `bash -n bin/resq bin/qspec bin/resq-merge`.
        gate = (ROOT / "tools/verify_release_gate.py").read_text(encoding="utf-8")
        self.assertIn('"--launchers-only"', gate)
        self.assertNotIn('"bash", "-n"', gate)


if __name__ == "__main__":
    unittest.main()
