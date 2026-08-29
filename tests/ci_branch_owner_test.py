#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import subprocess
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


HEAD_SHA = "1" * 40
BASE_SHA = "2" * 40
OTHER_SHA = "3" * 40


class BranchOwnerResolutionTest(unittest.TestCase):
    def test_maps_every_registered_owner_branch(self) -> None:
        cases = {
            "codex/root/async-ci": "root",
            "codex/base/settlement-ui": "base",
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


class BranchStateValidationTest(unittest.TestCase):
    @staticmethod
    def _git_values(merge_base: str = BASE_SHA) -> dict[tuple[str, ...], str]:
        return {
            ("rev-parse", "--verify", "HEAD^{commit}"): HEAD_SHA,
            ("rev-parse", "--verify", f"{BASE_SHA}^{{commit}}"): BASE_SHA,
            ("merge-base", HEAD_SHA, BASE_SHA): merge_base,
        }

    def test_state_binds_exact_head_base_and_required_ancestry(self) -> None:
        values = self._git_values()

        def fake_git(_repository: Path, *arguments: str) -> str:
            return values[arguments]

        with mock.patch.object(CI_BRANCH_OWNER, "_git", side_effect=fake_git):
            state = CI_BRANCH_OWNER.resolve_validation_state(
                REPO_ROOT,
                "codex/diver/task",
                BASE_SHA,
                expected_head=HEAD_SHA,
                expected_base=BASE_SHA,
            )
        self.assertEqual(state["owner"], "diver")
        self.assertEqual(state["head"], HEAD_SHA)
        self.assertEqual(state["base"], BASE_SHA)
        self.assertEqual(state["merge_base"], BASE_SHA)

    def test_rejects_head_or_base_identity_mismatch(self) -> None:
        values = self._git_values()

        def fake_git(_repository: Path, *arguments: str) -> str:
            return values[arguments]

        for label, expected_head, expected_base in (
            ("head", OTHER_SHA, BASE_SHA),
            ("base", HEAD_SHA, OTHER_SHA),
        ):
            with self.subTest(label=label):
                with (
                    mock.patch.object(CI_BRANCH_OWNER, "_git", side_effect=fake_git),
                    self.assertRaises(CI_BRANCH_OWNER.BranchOwnerError),
                ):
                    CI_BRANCH_OWNER.resolve_validation_state(
                        REPO_ROOT,
                        "codex/root/task",
                        BASE_SHA,
                        expected_head=expected_head,
                        expected_base=expected_base,
                    )

    def test_rejects_candidate_that_does_not_contain_current_base(self) -> None:
        values = self._git_values(merge_base=OTHER_SHA)

        def fake_git(_repository: Path, *arguments: str) -> str:
            return values[arguments]

        with (
            mock.patch.object(CI_BRANCH_OWNER, "_git", side_effect=fake_git),
            self.assertRaisesRegex(
                CI_BRANCH_OWNER.BranchOwnerError,
                "does not contain the required base",
            ),
        ):
            CI_BRANCH_OWNER.resolve_validation_state(
                REPO_ROOT,
                "codex/root/task",
                BASE_SHA,
                expected_head=HEAD_SHA,
                expected_base=BASE_SHA,
            )

    def test_rejects_short_uppercase_or_git_returned_noncanonical_sha(self) -> None:
        invalid = ("a" * 39, "A" * 40, "refs/heads/main", "")
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(CI_BRANCH_OWNER.BranchOwnerError):
                    CI_BRANCH_OWNER.resolve_validation_state(
                        REPO_ROOT,
                        "codex/root/task",
                        BASE_SHA,
                        expected_head=value,
                        expected_base=BASE_SHA,
                    )

        values = self._git_values()
        values[("rev-parse", "--verify", "HEAD^{commit}")] = "A" * 40

        def fake_git(_repository: Path, *arguments: str) -> str:
            return values[arguments]

        with (
            mock.patch.object(CI_BRANCH_OWNER, "_git", side_effect=fake_git),
            self.assertRaises(CI_BRANCH_OWNER.BranchOwnerError),
        ):
            CI_BRANCH_OWNER.resolve_validation_state(
                REPO_ROOT,
                "codex/root/task",
                BASE_SHA,
            )


class BranchDiffValidationTest(unittest.TestCase):
    @staticmethod
    def _state() -> dict[str, str]:
        return {
            "branch": "codex/map/task",
            "owner": "map",
            "head": HEAD_SHA,
            "base_ref": BASE_SHA,
            "base": BASE_SHA,
            "merge_base": BASE_SHA,
        }

    @staticmethod
    def _fixture_paths(temporary_directory: str) -> tuple[Path, Path]:
        temporary_root = Path(temporary_directory)
        candidate = temporary_root / "candidate"
        candidate.mkdir()
        trusted_tool = temporary_root / "trusted" / "tools" / "workbench_contract.py"
        trusted_tool.parent.mkdir(parents=True)
        trusted_tool.write_text("# trusted fixture\n", encoding="utf-8")
        trusted_tool.with_name("workbench_lock.py").write_text(
            "# trusted lock fixture\n", encoding="utf-8"
        )
        return candidate, trusted_tool

    def test_trusted_validator_receives_exact_external_contract_tool(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            candidate, trusted_tool = self._fixture_paths(temporary_directory)
            state = self._state()
            completed = subprocess.CompletedProcess([], 0)
            with (
                mock.patch.object(
                    CI_BRANCH_OWNER,
                    "resolve_validation_state",
                    side_effect=(state, state),
                ) as resolve,
                mock.patch.object(
                    CI_BRANCH_OWNER.subprocess,
                    "run",
                    return_value=completed,
                ) as run,
            ):
                result = CI_BRANCH_OWNER.validate_branch_diff(
                    candidate,
                    state["branch"],
                    BASE_SHA,
                    expected_head=HEAD_SHA,
                    expected_base=BASE_SHA,
                    contract_tool=trusted_tool,
                )
            self.assertEqual(resolve.call_count, 2)
            self.assertEqual(result["validation_mode"], "trusted")
            self.assertEqual(result["contract_tool"], str(trusted_tool.resolve()))
            command = run.call_args.args[0]
            self.assertEqual(command[1:3], ["-I", "-B"])
            self.assertEqual(
                command[command.index("--script") + 1], str(trusted_tool.resolve())
            )
            self.assertEqual(
                command[command.index("--preload") + 1],
                f"workbench_lock={trusted_tool.with_name('workbench_lock.py').resolve()}",
            )
            self.assertEqual(command[command.index("--repo") + 1], str(candidate.resolve()))
            self.assertEqual(command[command.index("--base") + 1], BASE_SHA)
            self.assertEqual(command[command.index("--owner") + 1], "map")

    def test_trusted_tuple_is_all_or_nothing(self) -> None:
        cases = (
            {"expected_head": HEAD_SHA},
            {"expected_base": BASE_SHA},
            {"contract_tool": REPO_ROOT / "tools" / "workbench_contract.py"},
            {"expected_head": HEAD_SHA, "expected_base": BASE_SHA},
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                with self.assertRaisesRegex(
                    CI_BRANCH_OWNER.BranchOwnerError,
                    "requires --expected-head",
                ):
                    CI_BRANCH_OWNER.validate_branch_diff(
                        REPO_ROOT,
                        "codex/root/task",
                        BASE_SHA,
                        **arguments,
                    )

    def test_rejects_relative_or_candidate_owned_contract_tool(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            candidate = Path(temporary_directory) / "candidate"
            local_tool = candidate / "tools" / "workbench_contract.py"
            local_tool.parent.mkdir(parents=True)
            local_tool.write_text("# candidate fixture\n", encoding="utf-8")
            state = self._state()
            for label, tool in (
                ("relative", Path("trusted/workbench_contract.py")),
                ("candidate", local_tool),
            ):
                with self.subTest(label=label):
                    with (
                        mock.patch.object(
                            CI_BRANCH_OWNER,
                            "resolve_validation_state",
                            return_value=state,
                        ),
                        self.assertRaises(CI_BRANCH_OWNER.BranchOwnerError),
                    ):
                        CI_BRANCH_OWNER.validate_branch_diff(
                            candidate,
                            state["branch"],
                            BASE_SHA,
                            expected_head=HEAD_SHA,
                            expected_base=BASE_SHA,
                            contract_tool=tool,
                        )

    def test_nonzero_owner_validator_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            candidate, trusted_tool = self._fixture_paths(temporary_directory)
            state = self._state()
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
                    candidate,
                    state["branch"],
                    BASE_SHA,
                    expected_head=HEAD_SHA,
                    expected_base=BASE_SHA,
                    contract_tool=trusted_tool,
                )

    def test_rejects_repository_identity_change_during_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            candidate, trusted_tool = self._fixture_paths(temporary_directory)
            before = self._state()
            after = {**before, "head": OTHER_SHA}
            with (
                mock.patch.object(
                    CI_BRANCH_OWNER,
                    "resolve_validation_state",
                    side_effect=(before, after),
                ),
                mock.patch.object(
                    CI_BRANCH_OWNER.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 0),
                ),
                self.assertRaisesRegex(
                    CI_BRANCH_OWNER.BranchOwnerError,
                    "identity changed",
                ),
            ):
                CI_BRANCH_OWNER.validate_branch_diff(
                    candidate,
                    before["branch"],
                    BASE_SHA,
                    expected_head=HEAD_SHA,
                    expected_base=BASE_SHA,
                    contract_tool=trusted_tool,
                )

    def test_local_feedback_mode_preserves_fast_branch_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            candidate = Path(temporary_directory) / "candidate"
            local_tool = candidate / "tools" / "workbench_contract.py"
            local_tool.parent.mkdir(parents=True)
            local_tool.write_text("# local fixture\n", encoding="utf-8")
            local_tool.with_name("workbench_lock.py").write_text(
                "# local lock fixture\n", encoding="utf-8"
            )
            state = self._state()
            with (
                mock.patch.object(
                    CI_BRANCH_OWNER,
                    "resolve_validation_state",
                    side_effect=(state, state),
                ),
                mock.patch.object(
                    CI_BRANCH_OWNER.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 0),
                ) as run,
            ):
                result = CI_BRANCH_OWNER.validate_branch_diff(
                    candidate,
                    state["branch"],
                    BASE_SHA,
                )
            self.assertEqual(result["validation_mode"], "local-feedback")
            command = run.call_args.args[0]
            self.assertEqual(command[1:3], ["-I", "-B"])
            self.assertEqual(
                command[command.index("--script") + 1], str(local_tool.resolve())
            )

    def test_local_feedback_mode_may_validate_from_an_older_merge_base(self) -> None:
        values = {
            ("rev-parse", "--verify", "HEAD^{commit}"): HEAD_SHA,
            ("rev-parse", "--verify", f"{BASE_SHA}^{{commit}}"): BASE_SHA,
            ("merge-base", HEAD_SHA, BASE_SHA): OTHER_SHA,
        }

        def fake_git(_repository: Path, *arguments: str) -> str:
            return values[arguments]

        with mock.patch.object(CI_BRANCH_OWNER, "_git", side_effect=fake_git):
            state = CI_BRANCH_OWNER.resolve_validation_state(
                REPO_ROOT,
                "codex/root/task",
                BASE_SHA,
            )
        self.assertEqual(state["merge_base"], OTHER_SHA)


if __name__ == "__main__":
    unittest.main(verbosity=2)
