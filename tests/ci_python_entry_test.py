#!/usr/bin/env python3
"""Security contracts for the isolated trusted Python entry launcher."""

from __future__ import annotations

import os
import shutil
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

    def test_map_builder_ignores_candidate_shadow_packages_when_both_dependencies_are_preloaded(self) -> None:
        builder_source = (
            REPOSITORY_ROOT
            / "underwater_map_workbench"
            / "tools"
            / "build_underwater_map.py"
        )
        trusted_contract = REPOSITORY_ROOT / "tools" / "workbench_contract.py"
        trusted_lock = REPOSITORY_ROOT / "tools" / "workbench_lock.py"
        with tempfile.TemporaryDirectory(prefix="ci_map_builder_shadow_") as raw_temp:
            candidate = Path(raw_temp)
            candidate_builder = (
                candidate
                / "underwater_map_workbench"
                / "tools"
                / "build_underwater_map.py"
            )
            candidate_builder.parent.mkdir(parents=True)
            candidate_builder.write_bytes(builder_source.read_bytes())
            for module_name in ("workbench_lock", "workbench_contract"):
                shadow = candidate / "tools" / module_name / "__init__.py"
                shadow.parent.mkdir(parents=True, exist_ok=True)
                shadow.write_text("raise SystemExit(0)\n", encoding="utf-8")

            result = self._run(
                [
                    "--preload",
                    f"workbench_lock={trusted_lock.resolve()}",
                    "--preload",
                    f"workbench_contract={trusted_contract.resolve()}",
                    "--script",
                    str(candidate_builder.resolve()),
                    "--",
                    "--help",
                ],
                cwd=candidate,
            )

            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn("--check", result.stdout)
            self.assertIn("--refresh-structure-package", result.stdout)

    def test_neutral_cwd_and_pinned_path_executable_ignore_candidate_git(self) -> None:
        actual_git = shutil.which("git")
        self.assertIsNotNone(actual_git, "Git is required for the trusted launcher test")
        with tempfile.TemporaryDirectory(prefix="ci_trusted_git_") as raw_temp:
            candidate = Path(raw_temp) / "candidate"
            neutral = Path(raw_temp) / "neutral"
            candidate.mkdir()
            neutral.mkdir()
            output = Path(raw_temp) / "git-version.txt"
            script = candidate / "invoke_git.py"
            script.write_text(
                textwrap.dedent(
                    """
                    import subprocess
                    import sys
                    from pathlib import Path

                    process = subprocess.run(
                        ["git", "--version"],
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    Path(sys.argv[1]).write_text(
                        f"{process.returncode}|{process.stdout}|{process.stderr}",
                        encoding="utf-8",
                    )
                    raise SystemExit(process.returncode)
                    """
                ),
                encoding="utf-8",
            )
            if os.name == "nt":
                fake_git = candidate / "git.exe"
                shutil.copy2(os.environ["COMSPEC"], fake_git)
            else:
                fake_git = candidate / "git"
                fake_git.write_text("#!/bin/sh\necho candidate-git-ran\n", encoding="utf-8")
                fake_git.chmod(0o755)

            result = self._run(
                [
                    "--cwd",
                    str(neutral.resolve()),
                    "--path-executable",
                    str(Path(actual_git).resolve()),
                    "--script",
                    str(script.resolve()),
                    "--",
                    str(output.resolve()),
                ],
                cwd=candidate,
            )

            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            recorded = output.read_text(encoding="utf-8")
            self.assertRegex(recorded, r"^0\|git version [^|]+\|$")
            self.assertNotIn("candidate-git-ran", recorded)


if __name__ == "__main__":
    unittest.main(verbosity=2)
