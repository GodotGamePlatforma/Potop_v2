#!/usr/bin/env python3
"""Security contracts for the isolated trusted Python entry launcher."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = REPOSITORY_ROOT / "tools" / "ci_python_entry.py"


class IsolatedPythonEntryTest(unittest.TestCase):
    def _run(self, arguments: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
        environment = dict(os.environ)
        environment["PYTHONPATH"] = str(cwd)
        return subprocess.run(
            [sys.executable, "-I", "-B", str(LAUNCHER), *arguments],
            cwd=cwd,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_candidate_startup_and_shadow_modules_are_not_imported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ci_python_entry_") as raw_temp:
            root = Path(raw_temp)
            marker = root / "startup-ran.txt"
            output = root / "result.txt"
            helper = root / "exact_helper.py"
            script = root / "entry.py"
            (root / "sitecustomize.py").write_text(
                f"from pathlib import Path\nPath({str(marker)!r}).write_text('bad')\n",
                encoding="utf-8",
            )
            (root / "json.py").write_text(
                "raise RuntimeError('candidate json shadow imported')\n",
                encoding="utf-8",
            )
            helper.write_text("VALUE = 'exact-helper'\n", encoding="utf-8")
            script.write_text(
                textwrap.dedent(
                    """
                    import json
                    import sys
                    import exact_helper
                    from pathlib import Path

                    Path(sys.argv[1]).write_text(
                        exact_helper.VALUE + "|" + str(Path(json.__file__).resolve()),
                        encoding="utf-8",
                    )
                    """
                ),
                encoding="utf-8",
            )

            result = self._run(
                [
                    "--preload",
                    f"exact_helper={helper.resolve()}",
                    "--script",
                    str(script.resolve()),
                    "--",
                    str(output.resolve()),
                ],
                cwd=root,
            )

            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertFalse(marker.exists(), "sitecustomize executed before the launcher")
            value, json_path = output.read_text(encoding="utf-8").split("|", 1)
            self.assertEqual("exact-helper", value)
            self.assertNotEqual((root / "json.py").resolve(), Path(json_path))

    def test_launcher_rejects_missing_isolated_mode_and_relative_paths(self) -> None:
        non_isolated = subprocess.run(
            [sys.executable, "-B", str(LAUNCHER), "--script", str(LAUNCHER)],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(2, non_isolated.returncode)
        self.assertIn("requires python -I -B", non_isolated.stderr)

        with tempfile.TemporaryDirectory(prefix="ci_python_entry_relative_") as raw_temp:
            result = self._run(["--script", "relative.py"], cwd=Path(raw_temp))
        self.assertEqual(2, result.returncode)
        self.assertIn("absolute path", result.stderr)

    def test_real_contract_runs_with_exact_preloaded_lock(self) -> None:
        contract = REPOSITORY_ROOT / "tools" / "workbench_contract.py"
        lock = REPOSITORY_ROOT / "tools" / "workbench_lock.py"
        result = self._run(
            [
                "--preload",
                f"workbench_lock={lock.resolve()}",
                "--script",
                str(contract.resolve()),
                "--",
                "--help",
            ],
            cwd=REPOSITORY_ROOT,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("ownership", result.stdout.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
