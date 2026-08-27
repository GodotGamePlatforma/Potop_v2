#!/usr/bin/env python3
"""Tests for the trusted automatic-integration protected-path admission gate."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "tools" / "ci_protected_paths.py"
SPEC = importlib.util.spec_from_file_location("ci_protected_paths", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load {MODULE_PATH}")
CI_PROTECTED_PATHS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_PROTECTED_PATHS)


class ProtectedPathMatcherTest(unittest.TestCase):
    def test_matches_every_control_plane_surface(self) -> None:
        protected = (
            ".github/workflows/integration.yml",
            ".github",
            ".githooks/pre-push",
            ".gitattributes",
            ".gitignore",
            ".gitmodules",
            ".lfsconfig",
            "AGENTS.md",
            ".ai/DECISIONS.md",
            "tools/ci_branch_owner.py",
            "tools/ci_nested/evidence.json",
            "tools/workbench_contract.py",
            "tools/workbench_lock.py",
            "tools/setup_agent_worktree.ps1",
            "tools/freeze_workbench_revision.py",
            "tools/install_agent_git_hooks.ps1",
            "tests/ci_branch_owner_test.py",
            "tests/ci_nested/fixture.txt",
            "tests/agent_integration_workflow_test.py",
            "tests/run_all_tests.ps1",
            "tests/runner_isolation_test.ps1",
            "tests/workbench_contract_test.py",
            "tests/workbench_lock_test.py",
            "tests/setup_agent_worktree_test.ps1",
            "tests/freeze_workbench_revision_test.py",
            "tests/pre_push_guard_test.ps1",
            "tests/map_atomic_write_test.py",
            "tests/parallel_worktree_godot_test.ps1",
            "underwater_map_workbench/tools/build_underwater_map.py",
        )
        for path in protected:
            with self.subTest(path=path):
                self.assertTrue(CI_PROTECTED_PATHS.is_protected_path(path))

    def test_does_not_expand_protection_to_similar_unrelated_paths(self) -> None:
        unprotected = (
            "docs/AGENTS.md",
            ".ai/PROJECT_CONTEXT.md",
            ".github-not/workflow.yml",
            ".githooks.txt",
            "tools/cipher.py",
            "tools/ci.py",
            "tests/circus_test.py",
            "tests/agent_integration_workflow_test.py.fixture",
            "underwater_map_workbench/tools/build_other_map.py",
            "game/scripts/feature.gd",
        )
        result = CI_PROTECTED_PATHS.validate_paths(unprotected)
        self.assertEqual(result["path_count"], len(unprotected))

    def test_normalizes_separators_dots_repetition_and_case(self) -> None:
        variants = (
            "./.GITHUB//workflows\\gate.yml",
            ".\\.githooks\\pre-push",
            "TOOLS\\CI_BRANCH_OWNER.PY",
            "tests//./CI_SHARD_TEST.PY",
            "agents.MD",
        )
        for path in variants:
            with self.subTest(path=path):
                self.assertTrue(CI_PROTECTED_PATHS.is_protected_path(path))

    def test_rejects_traversal_absolute_control_and_ambiguous_paths(self) -> None:
        invalid = (
            "../.github/workflow.yml",
            "docs/../.github/workflow.yml",
            "/.github/workflow.yml",
            "C:\\.github\\workflow.yml",
            "\\\\server\\share\\AGENTS.md",
            "",
            ".",
            " docs/file.txt",
            "docs/file.txt ",
            "docs/line\nfeed.txt",
            "docs/nul\0path.txt",
        )
        for path in invalid:
            with self.subTest(path=path):
                with self.assertRaises(CI_PROTECTED_PATHS.ProtectedPathError):
                    CI_PROTECTED_PATHS.normalize_repo_path(path)


class NulDiffParserTest(unittest.TestCase):
    def test_parses_nul_name_only_stream_and_enforces_limit(self) -> None:
        self.assertEqual(
            CI_PROTECTED_PATHS.parse_name_only_z(b"src/a.gd\0docs/b.txt\0"),
            ("src/a.gd", "docs/b.txt"),
        )
        accepted = (f"docs/file-{index}.txt" for index in range(3000))
        self.assertEqual(
            CI_PROTECTED_PATHS.validate_paths(accepted)["path_count"],
            3000,
        )
        rejected = (f"docs/file-{index}.txt" for index in range(3001))
        with self.assertRaisesRegex(
            CI_PROTECTED_PATHS.ProtectedPathError,
            "3000-path",
        ):
            CI_PROTECTED_PATHS.validate_paths(rejected)

    def test_name_only_stream_fails_closed_on_bad_framing_or_encoding(self) -> None:
        invalid = (
            b"docs/a.txt",
            b"docs/a.txt\0\0",
            b"docs/a.txt\0\xff\0",
        )
        for payload in invalid:
            with self.subTest(payload=payload):
                with self.assertRaises(CI_PROTECTED_PATHS.ProtectedPathError):
                    CI_PROTECTED_PATHS.parse_name_only_z(payload)

    def test_name_status_parser_preserves_both_rename_paths(self) -> None:
        paths = CI_PROTECTED_PATHS.parse_name_status_z(
            b"M\0src/current.gd\0R100\0.github/old.yml\0docs/new.yml\0"
        )
        self.assertEqual(
            paths,
            ("src/current.gd", ".github/old.yml", "docs/new.yml"),
        )
        with self.assertRaisesRegex(
            CI_PROTECTED_PATHS.ProtectedPathError,
            "protected control-plane",
        ):
            CI_PROTECTED_PATHS.validate_paths(paths)

        reverse_paths = CI_PROTECTED_PATHS.parse_name_status_z(
            b"R087\0docs/old.yml\0.github/new.yml\0"
        )
        with self.assertRaises(CI_PROTECTED_PATHS.ProtectedPathError):
            CI_PROTECTED_PATHS.validate_paths(reverse_paths)

    def test_name_status_stream_rejects_malformed_records(self) -> None:
        invalid = (
            b"M\0docs/a.txt",
            b"Z\0docs/a.txt\0",
            b"R100\0docs/old.txt\0",
            b"R1000\0docs/old.txt\0docs/new.txt\0",
            b"M\0\0",
            b"M\0\xff\0",
        )
        for payload in invalid:
            with self.subTest(payload=payload):
                with self.assertRaises(CI_PROTECTED_PATHS.ProtectedPathError):
                    CI_PROTECTED_PATHS.parse_name_status_z(payload)


class DiffAdmissionTest(unittest.TestCase):
    @staticmethod
    def _git(repository: Path, *arguments: str) -> str:
        process = subprocess.run(
            ["git", "-C", str(repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return process.stdout.strip()

    def _commit(self, repository: Path, message: str) -> str:
        self._git(repository, "add", "--all")
        self._git(
            repository,
            "-c",
            "user.name=CI Protected Paths Test",
            "-c",
            "user.email=ci-protected-paths@example.invalid",
            "commit",
            "-m",
            message,
        )
        return self._git(repository, "rev-parse", "HEAD")

    def test_validate_diff_catches_protected_previous_rename_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory) / "candidate"
            repository.mkdir()
            self._git(repository, "init")
            self._git(repository, "config", "core.autocrlf", "false")
            protected = repository / ".github" / "legacy.yml"
            protected.parent.mkdir()
            protected.write_text("name: legacy\n", encoding="utf-8")
            source = repository / "src" / "feature.gd"
            source.parent.mkdir()
            source.write_text("extends Node\n", encoding="utf-8")
            base = self._commit(repository, "base")

            destination = repository / "docs" / "legacy.yml"
            destination.parent.mkdir()
            protected.rename(destination)
            renamed_head = self._commit(repository, "rename protected path")

            with self.assertRaisesRegex(
                CI_PROTECTED_PATHS.ProtectedPathError,
                r"\.github/legacy\.yml",
            ):
                CI_PROTECTED_PATHS.validate_diff(repository, base, renamed_head)

            source.write_text("extends Node\n# safe change\n", encoding="utf-8")
            safe_head = self._commit(repository, "safe change")
            result = CI_PROTECTED_PATHS.validate_diff(
                repository,
                renamed_head,
                safe_head,
            )
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(result["path_count"], 1)

            for invalid_sha in (safe_head[:-1], safe_head.upper()):
                with self.subTest(invalid_sha=invalid_sha):
                    with self.assertRaises(CI_PROTECTED_PATHS.ProtectedPathError):
                        CI_PROTECTED_PATHS.validate_diff(
                            repository,
                            renamed_head,
                            invalid_sha,
                        )

    def test_validate_diff_uses_nul_no_rename_bounded_git_command(self) -> None:
        base = "1" * 40
        head = "2" * 40
        repository = Path("candidate").resolve()
        with (
            mock.patch.object(
                CI_PROTECTED_PATHS,
                "_repository_root",
                return_value=repository,
            ),
            mock.patch.object(
                CI_PROTECTED_PATHS,
                "_resolve_exact_commit",
                side_effect=(base, head),
            ),
            mock.patch.object(
                CI_PROTECTED_PATHS,
                "_git_bytes",
                return_value=b"docs/readme.txt\0",
            ) as git_bytes,
        ):
            result = CI_PROTECTED_PATHS.validate_diff(repository, base, head)
        self.assertEqual(result["path_count"], 1)
        self.assertEqual(
            git_bytes.call_args.args[1:],
            (
                "diff",
                "--name-only",
                "--no-renames",
                "-z",
                base,
                head,
                "--",
            ),
        )


class CommandLineTest(unittest.TestCase):
    def test_explicit_path_and_name_status_file_commands(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = CI_PROTECTED_PATHS.main(
                ["validate-paths", "--path", "src/feature.gd"]
            )
        self.assertEqual(exit_code, 0)
        self.assertIn('"status":"PASS"', stdout.getvalue())

        with tempfile.TemporaryDirectory() as temporary_directory:
            source = Path(temporary_directory) / "diff.z"
            source.write_bytes(
                b"R100\0.github/previous.yml\0docs/current.yml\0"
            )
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                exit_code = CI_PROTECTED_PATHS.main(
                    ["validate-name-status", "--input", str(source)]
                )
        self.assertEqual(exit_code, 1)
        self.assertIn(".github/previous.yml", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
