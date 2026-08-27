#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = REPO_ROOT / "tools" / "ci_branch_owner.py"
SPEC = importlib.util.spec_from_file_location("ci_branch_owner", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
CI_BRANCH_OWNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_BRANCH_OWNER)


class BranchOwnerResolutionTest(unittest.TestCase):
    def test_maps_every_registered_owner_branch(self) -> None:
        cases = {
            "codex/root/async-ci": "root",
            "codex/map/authority-refresh": "map",
            "codex/diver/professional-105x60": "diver",
            "codex/integration/production-acceptance": "integration",
            "codex/structure-tower_prototype_01/visual-redraw":
                "structure:tower_prototype_01",
        }
        for branch, owner in cases.items():
            with self.subTest(branch=branch):
                self.assertEqual(CI_BRANCH_OWNER.resolve_owner(branch), owner)

    def test_rejects_unknown_ambiguous_or_multi_segment_branches(self) -> None:
        invalid = (
            "main",
            "feature/root-task",
            "codex/unknown/task",
            "codex/structure-/task",
            "codex/root/one/two",
            "codex/root/Task With Spaces",
            "codex//task",
        )
        for branch in invalid:
            with self.subTest(branch=branch):
                with self.assertRaises(CI_BRANCH_OWNER.BranchOwnerError):
                    CI_BRANCH_OWNER.resolve_owner(branch)


class BranchDiffValidationTest(unittest.TestCase):
    def test_state_uses_exact_head_base_and_merge_base(self) -> None:
        values = {
            ("rev-parse", "--verify", "HEAD^{commit}"): "1" * 40,
            ("rev-parse", "--verify", "origin/main^{commit}"): "2" * 40,
            ("merge-base", "1" * 40, "2" * 40): "3" * 40,
            ("merge-base", "--is-ancestor", "3" * 40, "1" * 40): "",
        }

        def fake_git(_repository: Path, *arguments: str) -> str:
            return values[arguments]

        with mock.patch.object(CI_BRANCH_OWNER, "_git", side_effect=fake_git):
            state = CI_BRANCH_OWNER.resolve_validation_state(
                REPO_ROOT, "codex/diver/task", "origin/main"
            )
        self.assertEqual(state["owner"], "diver")
        self.assertEqual(state["merge_base"], "3" * 40)

    def test_validator_receives_merge_base_not_clean_worktree_default(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            tools = root / "tools"
            tools.mkdir()
            (tools / "workbench_contract.py").write_text("# fixture\n", encoding="utf-8")
            state = {
                "branch": "codex/map/task",
                "owner": "map",
                "head": "1" * 40,
                "base_ref": "origin/main",
                "base": "2" * 40,
                "merge_base": "3" * 40,
            }
            completed = subprocess.CompletedProcess([], 0)
            with (
                mock.patch.object(
                    CI_BRANCH_OWNER,
                    "resolve_validation_state",
                    return_value=state,
                ),
                mock.patch.object(
                    CI_BRANCH_OWNER.subprocess,
                    "run",
                    return_value=completed,
                ) as run,
            ):
                result = CI_BRANCH_OWNER.validate_branch_diff(
                    root, "codex/map/task", "origin/main"
                )
            self.assertEqual(result, state)
            command = run.call_args.args[0]
            self.assertIn("--diff", command)
            self.assertEqual(command[command.index("--base") + 1], "3" * 40)
            self.assertEqual(command[command.index("--owner") + 1], "map")

    def test_nonzero_owner_validator_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            tools = root / "tools"
            tools.mkdir()
            (tools / "workbench_contract.py").write_text("# fixture\n", encoding="utf-8")
            state = {
                "branch": "codex/root/task",
                "owner": "root",
                "head": "1" * 40,
                "base_ref": "origin/main",
                "base": "2" * 40,
                "merge_base": "3" * 40,
            }
            with (
                mock.patch.object(
                    CI_BRANCH_OWNER,
                    "resolve_validation_state",
                    return_value=state,
                ),
                mock.patch.object(
                    CI_BRANCH_OWNER.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 1),
                ),
                self.assertRaises(CI_BRANCH_OWNER.BranchOwnerError),
            ):
                CI_BRANCH_OWNER.validate_branch_diff(
                    root, "codex/root/task", "origin/main"
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
