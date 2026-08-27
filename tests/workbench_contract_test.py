#!/usr/bin/env python3
"""Unit tests for machine-readable workbench ownership checks."""

from __future__ import annotations

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import workbench_contract as contract  # noqa: E402


def _git(repository: Path, *arguments: str) -> str:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repository}",
            "-C",
            str(repository),
            *arguments,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"git {' '.join(arguments)} failed ({result.returncode}): {result.stderr}"
        )
    return result.stdout.strip()


def _git_bytes(repository: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repository}",
            "-C",
            str(repository),
            *arguments,
        ],
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"git {' '.join(arguments)} failed ({result.returncode}): "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )
    return result.stdout


def _new_repository(parent: Path) -> Path:
    repository = parent / "repository"
    repository.mkdir()
    subprocess.run(
        ["git", "init", "-q", str(repository)],
        check=True,
        capture_output=True,
    )
    _git(repository, "config", "user.email", "contract-test@example.invalid")
    _git(repository, "config", "user.name", "Contract Test")
    _git(repository, "config", "core.autocrlf", "false")
    (repository / ".gitignore").write_bytes(b"*.ignored\n")
    (repository / "tracked.txt").write_bytes(b"baseline\n")
    _git(repository, "add", ".gitignore", "tracked.txt")
    _git(repository, "commit", "-q", "-m", "baseline")
    return repository


def _commit_all(repository: Path, message: str) -> None:
    _git(repository, "add", "-A")
    _git(repository, "commit", "-q", "-m", message)


def _add_structure_package(
    repository: Path,
    structure_id: str,
    *,
    registered: bool,
) -> None:
    package = (
        repository
        / "underwater_map_workbench"
        / "structures"
        / structure_id
    )
    package.mkdir(parents=True)
    (package / "AGENTS.md").write_text("package agent\n", encoding="utf-8")
    (package / "README.md").write_text("package readme\n", encoding="utf-8")
    (package / "structure_manifest.json").write_text("{}\n", encoding="utf-8")
    instances = []
    if registered:
        instances.append(
            {
                "id": structure_id,
                "package": {
                    "path": f"structures/{structure_id}/structure_manifest.json"
                },
            }
        )
    map_manifest = repository / "underwater_map_workbench" / "map_manifest.json"
    map_manifest.write_text(
        json.dumps({"structures": {"instances": instances}}) + "\n",
        encoding="utf-8",
    )
    _commit_all(repository, f"add {structure_id}")


def _publication_candidate(parent: Path) -> dict[str, object]:
    repository = _new_repository(parent)
    source = repository / "source"
    generated = repository / "generated"
    source.mkdir()
    generated.mkdir()
    (repository / ".gitattributes").write_bytes(
        b"* text=auto eol=lf\n"
        b"generated/two.bin filter=lfs diff=lfs merge=lfs -text\n"
    )
    (source / "input.txt").write_bytes(b"input\n")
    (generated / "one.bin").write_bytes(b"one")
    (generated / "two.bin").write_bytes(b"two")
    (repository / ".gitignore").write_bytes(
        b"*.ignored\ngenerated/extra.bin\n"
    )
    _commit_all(repository, "publication candidate")

    input_list = parent / "inputs.list"
    output_list = parent / "outputs.list"
    receipt = parent / "publication_receipt.json"
    input_list.write_text("source/input.txt\n", encoding="utf-8")
    output_list.write_text(
        "generated/one.bin\ngenerated/two.bin\n",
        encoding="utf-8",
    )
    return {
        "repository": repository,
        "input_list": input_list,
        "output_list": output_list,
        "receipt": receipt,
        "input_roots": ("source",),
        "output_roots": ("generated",),
    }


def _create_receipt(candidate: dict[str, object]) -> dict[str, object]:
    return contract.create_publication_receipt(
        candidate["repository"],
        input_list=candidate["input_list"],
        output_list=candidate["output_list"],
        input_roots=candidate["input_roots"],
        output_roots=candidate["output_roots"],
        receipt_path=candidate["receipt"],
    )


def _assignment_candidate(
    parent: Path,
    *,
    task_id: str = "task-root-a",
    thread_id: str = "thread-root-a",
    write_set_text: str = "tracked.txt\n",
) -> dict[str, object]:
    candidate = _publication_candidate(parent)
    receipt = _create_receipt(candidate)
    repository = candidate["repository"]
    run_receipt = parent / f"{task_id}-run.json"
    run_receipt.write_text(
        json.dumps(
            {
                "head": receipt["head"],
                "tree": receipt["tree"],
                "suite_mode": "full",
                "target_scope": "full",
                "overall": "PASS",
                "fail_count": 0,
                "skip_count": 0,
                "blocking_failure_count": 0,
            }
        )
        + "\n",
        encoding="utf-8",
    )
    write_set = parent / f"{task_id}-write-set.txt"
    write_set.write_text(write_set_text, encoding="utf-8")
    _git(repository, "update-ref", contract.LAST_GREEN_REF, str(receipt["head"]))
    now = datetime(2026, 8, 27, 8, 0, tzinfo=timezone.utc)
    return {
        **candidate,
        "task_id": task_id,
        "thread_id": thread_id,
        "owner": "root",
        "brief": f"Implement {task_id}",
        "destination": repository,
        "common_git_dir": contract.git_common_dir(repository),
        "branch": _git(repository, "branch", "--show-current"),
        "head": receipt["head"],
        "tree": receipt["tree"],
        "write_set_path": write_set,
        "candidate_receipt": candidate["receipt"],
        "run_receipt": run_receipt,
        "ack_deadline": now + timedelta(minutes=5),
        "now": now,
    }


class WorkbenchOwnershipTest(unittest.TestCase):
    def test_owner_classification_and_generated_boundary(self) -> None:
        cases = {
            "scripts/diving/DiveController.gd": "root",
            "underwater_map_workbench/map_manifest.json": "map",
            "diver_workbench/runtime/Diver.tscn": "diver",
            "underwater_map_workbench/structures/tower_a/runtime/controller.gd": (
                "structure:tower_a"
            ),
            "underwater_map_workbench/structures/tower_a/generated/structure.tscn": (
                "map"
            ),
        }
        for path, expected_owner in cases.items():
            with self.subTest(path=path):
                self.assertEqual(contract.owner_for_path(path), expected_owner)

    def test_play_alias_is_not_an_owner(self) -> None:
        with self.assertRaisesRegex(contract.ContractError, "Owner must be"):
            contract.normalize_owner("play")

    def test_structure_cannot_write_another_structure_or_generated(self) -> None:
        violations = contract.validate_paths(
            "structure:tower_a",
            [
                "underwater_map_workbench/structures/tower_a/runtime/controller.gd",
                "underwater_map_workbench/structures/tower_a/generated/structure.tscn",
                "underwater_map_workbench/structures/tower_b/runtime/controller.gd",
            ],
        )
        self.assertEqual(
            [(item.path, item.actual_owner) for item in violations],
            [
                (
                    "underwater_map_workbench/structures/tower_a/generated/structure.tscn",
                    "map",
                ),
                (
                    "underwater_map_workbench/structures/tower_b/runtime/controller.gd",
                    "structure:tower_b",
                ),
            ],
        )

    def test_integration_may_validate_cross_owner_write_set(self) -> None:
        self.assertEqual(
            contract.validate_paths(
                "integration",
                [
                    "scripts/data/DiveSessionState.gd",
                    "diver_workbench/runtime/Diver.tscn",
                    "underwater_map_workbench/map_manifest.json",
                ],
            ),
            (),
        )


class WorkbenchGitStateTest(unittest.TestCase):
    def test_validate_diff_accepts_clean_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = _new_repository(Path(temporary))
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = contract.main(
                    [
                        "--repo",
                        str(repository),
                        "validate",
                        "--owner",
                        "root",
                        "--diff",
                    ]
                )

            self.assertEqual(exit_code, 0, stderr.getvalue())
            self.assertEqual(stdout.getvalue().strip(), "PASS owner=root paths=0")

    def test_validate_without_selector_still_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = _new_repository(Path(temporary))
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = contract.main(
                    [
                        "--repo",
                        str(repository),
                        "validate",
                        "--owner",
                        "root",
                    ]
                )

            self.assertEqual(exit_code, 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn(
                "validate requires --path, --write-set, --diff or --base",
                stderr.getvalue(),
            )

    def test_inventory_includes_tracked_and_nonignored_untracked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = _new_repository(Path(temporary))
            (repository / "new.txt").write_text("new\n", encoding="utf-8")
            (repository / "hidden.ignored").write_text("ignored\n", encoding="utf-8")

            inventory = contract.inventory_paths(repository)

            self.assertIn("tracked.txt", inventory)
            self.assertIn("new.txt", inventory)
            self.assertNotIn("hidden.ignored", inventory)

    def test_changed_paths_include_tracked_staged_and_untracked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = _new_repository(Path(temporary))
            (repository / "tracked.txt").write_text("changed\n", encoding="utf-8")
            (repository / "staged.txt").write_text("staged\n", encoding="utf-8")
            (repository / "untracked.txt").write_text("untracked\n", encoding="utf-8")
            _git(repository, "add", "staged.txt")

            self.assertEqual(
                contract.changed_paths(repository),
                ("staged.txt", "tracked.txt", "untracked.txt"),
            )

    def test_structure_doctor_rejects_typo_and_requires_explicit_staging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = _new_repository(Path(temporary))
            missing = contract.doctor_report(
                repository,
                owner="structure:tower_typo",
                intent="author",
            )
            self.assertFalse(missing.ready)
            self.assertEqual(missing.structure_status, "missing")

            _add_structure_package(repository, "tower_staging", registered=False)
            implicit = contract.doctor_report(
                repository,
                owner="structure:tower_staging",
                intent="author",
            )
            self.assertFalse(implicit.ready)
            self.assertEqual(implicit.structure_status, "staging")

            explicit = contract.doctor_report(
                repository,
                owner="structure:tower_staging",
                intent="author",
                allow_staging=True,
            )
            self.assertTrue(explicit.ready)
            self.assertEqual(explicit.structure_status, "staging")

            staging_publish = contract.doctor_report(
                repository,
                owner="structure:tower_staging",
                intent="publish",
                allow_staging=True,
            )
            self.assertFalse(staging_publish.ready)
            self.assertTrue(
                any("requires owner=integration" in reason for reason in staging_publish.reasons)
            )

    def test_structure_doctor_accepts_complete_registered_package(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = _new_repository(Path(temporary))
            _add_structure_package(repository, "tower_registered", registered=True)

            report = contract.doctor_report(
                repository,
                owner="structure:tower_registered",
                intent="author",
            )

            self.assertTrue(report.ready)
            self.assertEqual(report.structure_status, "registered")

    def test_doctor_rejects_dirty_integration_and_publish(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            clean_without_receipt = contract.doctor_report(
                repository,
                owner="integration",
                intent="publish",
            )
            self.assertFalse(clean_without_receipt.ready)
            self.assertTrue(
                any(
                    "requires an explicit verified publication receipt" in reason
                    for reason in clean_without_receipt.reasons
                )
            )

            _create_receipt(candidate)
            clean = contract.doctor_report(
                repository,
                owner="integration",
                intent="publish",
                receipt_path=candidate["receipt"],
            )
            self.assertTrue(clean.ready)
            self.assertTrue(clean.publication_receipt_verified)

            (repository / "tracked.txt").write_text("dirty\n", encoding="utf-8")
            for intent in ("integration", "publish"):
                with self.subTest(intent=intent):
                    report = contract.doctor_report(
                        repository,
                        owner="integration",
                        intent=intent,
                    )
                    self.assertFalse(report.ready)
                    self.assertIn("tracked.txt", report.dirty_paths)
                    self.assertTrue(
                        any("clean source worktree" in reason for reason in report.reasons)
                    )

            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
                io.StringIO()
            ):
                exit_code = contract.main(
                    [
                        "--repo",
                        str(repository),
                        "doctor",
                        "--owner",
                        "integration",
                        "--intent",
                        "publish",
                    ]
                )
            self.assertEqual(exit_code, 2)

    def test_publication_lock_is_shared_by_linked_worktrees(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            repository = _new_repository(temporary_path)
            linked = temporary_path / "linked"
            _git(repository, "worktree", "add", "--detach", "-q", str(linked), "HEAD")
            try:
                self.assertEqual(
                    contract.git_common_dir(repository),
                    contract.git_common_dir(linked),
                )
                self.assertEqual(
                    contract.publication_lock_path(repository),
                    contract.publication_lock_path(linked),
                )
            finally:
                _git(repository, "worktree", "remove", "--force", str(linked))


class PublicationReceiptTest(unittest.TestCase):
    def test_receipt_verifies_clean_closed_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            self.assertEqual(
                _git(repository, "status", "--porcelain"),
                "",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            self.assertEqual(
                (repository / "source" / "input.txt").read_bytes(),
                _git_bytes(repository, "show", "HEAD:source/input.txt"),
            )
            self.assertIn(
                "filter: lfs",
                _git(
                    repository,
                    "check-attr",
                    "filter",
                    "--",
                    "generated/two.bin",
                ),
            )
            self.assertNotEqual(
                (repository / "generated" / "two.bin").read_bytes(),
                _git_bytes(repository, "show", "HEAD:generated/two.bin"),
            )
            created = _create_receipt(candidate)

            verified = contract.verify_publication_receipt(
                repository, candidate["receipt"]
            )

            self.assertEqual(created["head"], verified["head"])
            self.assertEqual(created["tree"], verified["tree"])
            self.assertEqual(created["status"], "PUBLICATION_READY")

    def test_receipt_creation_rejects_clean_filter_crlf_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            (repository / "source" / "input.txt").write_bytes(b"input\r\n")
            _git(repository, "add", "source/input.txt")

            self.assertEqual(
                _git(repository, "status", "--porcelain"),
                "",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            with self.assertRaisesRegex(
                contract.ContractError,
                "clean-filter drift: source/input.txt",
            ):
                _create_receipt(candidate)

    def test_receipt_creation_rejects_clean_filter_mixed_eol_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            input_path = repository / "source" / "input.txt"
            input_path.write_bytes(b"first\nsecond\n")
            _commit_all(repository, "mixed eol baseline")
            input_path.write_bytes(b"first\r\nsecond\n")
            _git(repository, "add", "source/input.txt")

            self.assertEqual(
                _git(repository, "status", "--porcelain"),
                "",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            self.assertIn(
                "w/mixed",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            with self.assertRaisesRegex(
                contract.ContractError,
                "clean-filter drift: source/input.txt",
            ):
                _create_receipt(candidate)

    def test_receipt_verification_rejects_clean_filter_crlf_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            _create_receipt(candidate)
            repository = candidate["repository"]
            (repository / "source" / "input.txt").write_bytes(b"input\r\n")
            _git(repository, "add", "source/input.txt")

            self.assertEqual(_git(repository, "status", "--porcelain"), "")
            with self.assertRaisesRegex(
                contract.ContractError,
                "clean-filter drift: source/input.txt",
            ):
                contract.verify_publication_receipt(
                    repository, candidate["receipt"]
                )

    def test_receipt_rejects_output_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            _create_receipt(candidate)
            repository = candidate["repository"]
            (repository / "generated" / "one.bin").write_bytes(b"mutated")

            with self.assertRaisesRegex(
                contract.ContractError,
                "clean candidate worktree",
            ):
                contract.verify_publication_receipt(repository, candidate["receipt"])

    def test_receipt_rejects_sha_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            _create_receipt(candidate)
            receipt_path = candidate["receipt"]
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            receipt["outputs"][0]["sha256"] = "0" * 64
            receipt_path.write_text(json.dumps(receipt) + "\n", encoding="utf-8")

            with self.assertRaisesRegex(
                contract.ContractError,
                "output file content changed",
            ):
                contract.verify_publication_receipt(
                    candidate["repository"], receipt_path
                )

    def test_receipt_rejects_extra_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            _create_receipt(candidate)
            repository = candidate["repository"]
            (repository / "generated" / "extra.bin").write_bytes(b"extra")

            with self.assertRaisesRegex(
                contract.ContractError,
                "output set changed",
            ):
                contract.verify_publication_receipt(repository, candidate["receipt"])

    def test_receipt_rejects_omitted_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            _create_receipt(candidate)
            receipt_path = candidate["receipt"]
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            receipt["outputs"] = receipt["outputs"][:-1]
            receipt_path.write_text(json.dumps(receipt) + "\n", encoding="utf-8")

            with self.assertRaisesRegex(
                contract.ContractError,
                "output set changed",
            ):
                contract.verify_publication_receipt(
                    candidate["repository"], receipt_path
                )

    def test_receipt_creation_rejects_dirty_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            (repository / "source" / "input.txt").write_text(
                "dirty\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                contract.ContractError,
                "clean candidate worktree",
            ):
                _create_receipt(candidate)

    def test_receipt_creation_rejects_omitted_output_from_explicit_list(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            output_list = candidate["output_list"]
            output_list.write_text("generated/one.bin\n", encoding="utf-8")

            with self.assertRaisesRegex(
                contract.ContractError,
                "output list is not closed",
            ):
                _create_receipt(candidate)


class LastGreenRefTest(unittest.TestCase):
    def test_last_green_ref_is_shared_by_linked_worktrees(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            candidate = _publication_candidate(parent)
            repository = candidate["repository"]
            head = _git(repository, "rev-parse", "HEAD")
            linked = parent / "linked"
            _git(repository, "worktree", "add", "--detach", str(linked), head)

            _git(repository, "update-ref", contract.LAST_GREEN_REF, head)

            self.assertEqual(contract.last_green_head(repository), head)
            self.assertEqual(contract.last_green_head(linked), head)

    def test_resolve_requires_existing_matching_ref(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            receipt = _create_receipt(candidate)
            repository = candidate["repository"]

            with self.assertRaisesRegex(contract.ContractError, "ref is missing"):
                contract.resolve_last_green(
                    repository,
                    candidate_receipt=candidate["receipt"],
                    run_receipt=Path(temporary) / "unused-run.json",
                )

            parent = _git(repository, "rev-parse", "HEAD^")
            _git(repository, "update-ref", contract.LAST_GREEN_REF, parent)
            with self.assertRaisesRegex(contract.ContractError, "differs from"):
                contract.resolve_last_green(
                    repository,
                    candidate_receipt=candidate["receipt"],
                    run_receipt=Path(temporary) / "unused-run.json",
                )
            self.assertNotEqual(receipt["head"], parent)

    def test_symbolic_last_green_ref_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            branch = _git(repository, "branch", "--show-current")
            _git(
                repository,
                "symbolic-ref",
                contract.LAST_GREEN_REF,
                f"refs/heads/{branch}",
            )

            with self.assertRaisesRegex(contract.ContractError, "symbolic ref"):
                contract.last_green_head(repository)

    def test_promote_and_resolve_verified_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            receipt = _create_receipt(candidate)
            repository = candidate["repository"]
            run_receipt = Path(temporary) / "run.json"

            with mock.patch.object(
                contract, "_verify_full_run_receipt", return_value=None
            ) as verifier:
                promoted = contract.promote_last_green(
                    repository,
                    candidate_receipt=candidate["receipt"],
                    run_receipt=run_receipt,
                    expected_old=None,
                )
                resolved = contract.resolve_last_green(
                    repository,
                    candidate_receipt=candidate["receipt"],
                    run_receipt=run_receipt,
                )

            self.assertEqual(promoted["status"], "PROMOTED")
            self.assertEqual(promoted["head"], receipt["head"])
            self.assertEqual(resolved["head"], receipt["head"])
            self.assertEqual(contract.last_green_head(repository), receipt["head"])
            self.assertEqual(verifier.call_count, 2)

    def test_failed_run_evidence_cannot_move_ref(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            candidate = _publication_candidate(parent)
            first_receipt = _create_receipt(candidate)
            repository = candidate["repository"]
            _git(
                repository,
                "update-ref",
                contract.LAST_GREEN_REF,
                str(first_receipt["head"]),
            )

            (repository / "source" / "input.txt").write_bytes(b"next\n")
            _commit_all(repository, "next candidate")
            candidate["receipt"] = parent / "publication_receipt_next.json"
            next_receipt = _create_receipt(candidate)

            with mock.patch.object(
                contract,
                "_verify_full_run_receipt",
                side_effect=contract.ContractError("full run is not PASS"),
            ):
                with self.assertRaisesRegex(contract.ContractError, "not PASS"):
                    contract.promote_last_green(
                        repository,
                        candidate_receipt=candidate["receipt"],
                        run_receipt=parent / "failed-run.json",
                        expected_old=str(first_receipt["head"]),
                    )

            self.assertNotEqual(first_receipt["head"], next_receipt["head"])
            self.assertEqual(
                contract.last_green_head(repository), first_receipt["head"]
            )

    def test_stale_compare_and_swap_does_not_verify_or_move(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            receipt = _create_receipt(candidate)
            repository = candidate["repository"]
            _git(
                repository,
                "update-ref",
                contract.LAST_GREEN_REF,
                str(receipt["head"]),
            )

            stale = _git(repository, "rev-parse", "HEAD^")
            with mock.patch.object(
                contract, "_verify_full_run_receipt", return_value=None
            ) as verifier:
                with self.assertRaisesRegex(
                    contract.ContractError, "compare-and-swap mismatch"
                ):
                    contract.promote_last_green(
                        repository,
                        candidate_receipt=candidate["receipt"],
                        run_receipt=Path(temporary) / "run.json",
                        expected_old=stale,
                    )

            verifier.assert_not_called()
            self.assertEqual(contract.last_green_head(repository), receipt["head"])

    def test_non_fast_forward_candidate_cannot_move_ref(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            _create_receipt(candidate)
            repository = candidate["repository"]
            tree = _git(repository, "rev-parse", "HEAD^{tree}")
            unrelated = _git(repository, "commit-tree", tree, "-m", "unrelated")
            _git(repository, "update-ref", contract.LAST_GREEN_REF, unrelated)

            with mock.patch.object(
                contract, "_verify_full_run_receipt", return_value=None
            ) as verifier:
                with self.assertRaisesRegex(contract.ContractError, "fast-forward"):
                    contract.promote_last_green(
                        repository,
                        candidate_receipt=candidate["receipt"],
                        run_receipt=Path(temporary) / "run.json",
                        expected_old=unrelated,
                    )

            verifier.assert_not_called()
            self.assertEqual(contract.last_green_head(repository), unrelated)


class AgentAssignmentTest(unittest.TestCase):
    def _create(self, fixture: dict[str, object]) -> dict[str, object]:
        return contract.create_assignment(
            fixture["repository"],
            task_id=fixture["task_id"],
            thread_id=fixture["thread_id"],
            owner=fixture["owner"],
            brief=fixture["brief"],
            destination=fixture["destination"],
            common_git_dir=fixture["common_git_dir"],
            branch=fixture["branch"],
            head=fixture["head"],
            tree=fixture["tree"],
            write_set_path=fixture["write_set_path"],
            candidate_receipt=fixture["candidate_receipt"],
            run_receipt=fixture["run_receipt"],
            ack_deadline=fixture["ack_deadline"],
            now=fixture["now"],
        )

    def _ack(
        self,
        fixture: dict[str, object],
        status: dict[str, object],
        **overrides: object,
    ) -> dict[str, object]:
        assignment = status["assignment"]
        arguments = {
            "task_id": fixture["task_id"],
            "assignment_id": assignment["assignment_id"],
            "thread_id": fixture["thread_id"],
            "owner": fixture["owner"],
            "write_set_path": fixture["write_set_path"],
            "now": fixture["now"] + timedelta(seconds=30),
        }
        arguments.update(overrides)
        return contract.acknowledge_assignment(fixture["repository"], **arguments)

    def test_lifecycle_ack_validate_close_and_retention_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = _assignment_candidate(Path(temporary))
            created = self._create(fixture)
            assignment = created["assignment"]

            self.assertTrue(created["created"])
            self.assertEqual(created["state"], contract.ASSIGNMENT_WAITING)
            bundle = Path(created["bundle"])
            self.assertTrue(bundle.is_relative_to(contract.assignment_store(fixture["repository"])))
            self.assertEqual(bundle.parent.name, assignment["task_id_sha256"])
            self.assertEqual(bundle.name, assignment["assignment_id"])
            self.assertEqual(
                tuple(assignment["write_set"]),
                ("tracked.txt",),
            )
            by_task = contract.assignment_status(
                fixture["repository"],
                task_id=fixture["task_id"],
                now=fixture["now"],
            )
            self.assertEqual(by_task["bundle"], created["bundle"])

            acknowledged = self._ack(fixture, created)
            self.assertTrue(acknowledged["created"])
            self.assertEqual(acknowledged["state"], contract.ASSIGNMENT_RUNNING)
            verified, outside = contract.validate_assignment_context(
                fixture["repository"],
                assignment_id=assignment["assignment_id"],
                task_id=fixture["task_id"],
                thread_id=fixture["thread_id"],
                owner="root",
                paths=("tracked.txt",),
                now=fixture["now"] + timedelta(minutes=1),
            )
            self.assertEqual(verified["state"], contract.ASSIGNMENT_RUNNING)
            self.assertEqual(outside, ())

            closed = contract.close_assignment(
                fixture["repository"],
                task_id=fixture["task_id"],
                assignment_id=assignment["assignment_id"],
                thread_id=fixture["thread_id"],
                reason="handoff complete",
                now=fixture["now"] + timedelta(days=2),
            )
            self.assertEqual(closed["state"], contract.ASSIGNMENT_CLOSED)
            plan = contract.assignment_gc_plan(
                fixture["repository"],
                retention_days=7,
                now=fixture["now"] + timedelta(days=10),
            )
            self.assertEqual(plan["mode"], "PLAN_ONLY")
            self.assertEqual(plan["eligible_count"], 1)
            self.assertTrue(bundle.exists(), "retention planning must never delete")

    def test_ack_rejects_wrong_context_dirty_and_outside_write_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            fixture = _assignment_candidate(parent)
            created = self._create(fixture)
            assignment_id = created["assignment"]["assignment_id"]

            with self.assertRaisesRegex(contract.ContractError, "thread_id"):
                self._ack(fixture, created, thread_id="wrong-thread")
            with self.assertRaisesRegex(contract.ContractError, "does not exist"):
                self._ack(fixture, created, task_id="wrong-task")
            with self.assertRaisesRegex(contract.ContractError, "owner"):
                self._ack(fixture, created, owner="integration")
            wrong_write_set = parent / "wrong-write-set.txt"
            wrong_write_set.write_text("outside.txt\n", encoding="utf-8")
            with self.assertRaisesRegex(contract.ContractError, "write_set"):
                self._ack(fixture, created, write_set_path=wrong_write_set)

            repository = fixture["repository"]
            (repository / "tracked.txt").write_text("dirty\n", encoding="utf-8")
            with self.assertRaisesRegex(contract.ContractError, "clean destination"):
                self._ack(fixture, created)
            (repository / "tracked.txt").write_text("baseline\n", encoding="utf-8")

            original_branch = fixture["branch"]
            _git(repository, "checkout", "-q", "-b", "wrong-assignment-branch")
            with self.assertRaisesRegex(contract.ContractError, "branch"):
                self._ack(fixture, created)
            _git(repository, "checkout", "-q", str(original_branch))

            _git(repository, "commit", "--allow-empty", "-q", "-m", "wrong head")
            with self.assertRaisesRegex(contract.ContractError, "head"):
                self._ack(fixture, created)
            _git(repository, "reset", "--hard", str(fixture["head"]))

            linked = parent / "wrong-cwd"
            _git(repository, "worktree", "add", "--detach", "-q", str(linked), str(fixture["head"]))
            try:
                with self.assertRaisesRegex(contract.ContractError, "destination"):
                    contract.acknowledge_assignment(
                        linked,
                        task_id=fixture["task_id"],
                        assignment_id=assignment_id,
                        thread_id=fixture["thread_id"],
                        owner="root",
                        write_set_path=fixture["write_set_path"],
                        now=fixture["now"] + timedelta(seconds=30),
                    )
            finally:
                _git(repository, "worktree", "remove", "--force", str(linked))

            acknowledged = self._ack(fixture, created)
            _, outside = contract.validate_assignment_context(
                repository,
                assignment_id=assignment_id,
                task_id=fixture["task_id"],
                thread_id=fixture["thread_id"],
                owner="root",
                paths=("tracked.txt", "outside.txt"),
                now=fixture["now"] + timedelta(minutes=1),
            )
            self.assertEqual(acknowledged["state"], contract.ASSIGNMENT_RUNNING)
            self.assertEqual(outside, ("outside.txt",))

    def test_timeout_redispatch_keeps_same_task_thread_and_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = _assignment_candidate(Path(temporary))
            created = self._create(fixture)
            assignment = created["assignment"]
            timed_out_at = fixture["ack_deadline"] + timedelta(seconds=1)
            status = contract.assignment_status(
                fixture["repository"],
                task_id=fixture["task_id"],
                assignment_id=assignment["assignment_id"],
                now=timed_out_at,
            )
            self.assertEqual(status["state"], contract.ASSIGNMENT_TIMEOUT)
            with self.assertRaisesRegex(contract.ContractError, "redispatch"):
                self._ack(fixture, created, now=timed_out_at)
            with self.assertRaisesRegex(contract.ContractError, "original thread_id"):
                contract.redispatch_assignment(
                    fixture["repository"],
                    task_id=fixture["task_id"],
                    assignment_id=assignment["assignment_id"],
                    thread_id="second-author",
                    reason="timeout",
                    ack_deadline=timed_out_at + timedelta(minutes=5),
                    now=timed_out_at,
                )

            redispatched = contract.redispatch_assignment(
                fixture["repository"],
                task_id=fixture["task_id"],
                assignment_id=assignment["assignment_id"],
                thread_id=fixture["thread_id"],
                reason="retry same task",
                ack_deadline=timed_out_at + timedelta(minutes=5),
                now=timed_out_at,
            )
            self.assertEqual(redispatched["state"], contract.ASSIGNMENT_WAITING)
            self.assertEqual(redispatched["bundle"], created["bundle"])
            self.assertEqual(redispatched["assignment"]["thread_id"], fixture["thread_id"])
            acknowledged = self._ack(
                fixture,
                created,
                now=timed_out_at + timedelta(minutes=1),
            )
            self.assertEqual(acknowledged["state"], contract.ASSIGNMENT_RUNNING)

    def test_duplicate_and_overlapping_assignments_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            first = _assignment_candidate(parent, task_id="first")
            created = self._create(first)
            duplicate = self._create(first)
            self.assertFalse(duplicate["created"])
            self.assertEqual(duplicate["bundle"], created["bundle"])

            second_write_set = parent / "second-write-set.txt"
            second_write_set.write_text("tracked.txt\n", encoding="utf-8")
            with self.assertRaisesRegex(contract.ContractError, "overlaps"):
                contract.create_assignment(
                    first["repository"],
                    task_id="second",
                    thread_id="thread-second",
                    owner="root",
                    brief="overlap",
                    destination=first["destination"],
                    common_git_dir=first["common_git_dir"],
                    branch=first["branch"],
                    head=first["head"],
                    tree=first["tree"],
                    write_set_path=second_write_set,
                    candidate_receipt=first["candidate_receipt"],
                    run_receipt=first["run_receipt"],
                    ack_deadline=first["ack_deadline"],
                    now=first["now"] + timedelta(seconds=1),
                )
            self.assertEqual(created["state"], contract.ASSIGNMENT_WAITING)

    def test_cross_owner_write_set_and_tamper_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            fixture = _assignment_candidate(
                parent,
                write_set_text="diver_workbench/runtime/Diver.tscn\n",
            )
            with self.assertRaisesRegex(contract.ContractError, "owner boundary"):
                self._create(fixture)

            valid_parent = parent / "valid"
            valid_parent.mkdir()
            valid = _assignment_candidate(
                valid_parent,
                task_id="valid-task",
            )
            created = self._create(valid)
            assignment_path = Path(created["bundle"]) / "assignment.json"
            record = json.loads(assignment_path.read_text(encoding="utf-8"))
            record["brief"] = "tampered"
            assignment_path.write_text(json.dumps(record) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(contract.ContractError, "digest"):
                contract.assignment_status(
                    valid["repository"],
                    task_id=valid["task_id"],
                    assignment_id=created["assignment"]["assignment_id"],
                    now=valid["now"],
                )

            ack_parent = parent / "ack-tamper"
            ack_parent.mkdir()
            ack_fixture = _assignment_candidate(
                ack_parent,
                task_id="ack-tamper-task",
            )
            ack_created = self._create(ack_fixture)
            self._ack(ack_fixture, ack_created)
            ack_path = Path(ack_created["bundle"]) / "ack.json"
            ack_record = json.loads(ack_path.read_text(encoding="utf-8"))
            ack_record["owner"] = "integration"
            ack_path.write_text(json.dumps(ack_record) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(contract.ContractError, "digest"):
                contract.assignment_status(
                    ack_fixture["repository"],
                    task_id=ack_fixture["task_id"],
                    assignment_id=ack_created["assignment"]["assignment_id"],
                    now=ack_fixture["now"] + timedelta(minutes=1),
                )

    def test_assignment_rejects_non_integer_run_counts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = _assignment_candidate(Path(temporary))
            run_receipt = json.loads(
                fixture["run_receipt"].read_text(encoding="utf-8")
            )
            run_receipt["fail_count"] = "zero"
            fixture["run_receipt"].write_text(
                json.dumps(run_receipt) + "\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(contract.ContractError, "run fail_count"):
                self._create(fixture)

    def test_cli_validate_assignment_diff_fails_outside_closed_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = _assignment_candidate(Path(temporary))
            created = self._create(fixture)
            self._ack(fixture, created)
            repository = fixture["repository"]
            (repository / "outside.txt").write_text("outside\n", encoding="utf-8")
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = contract.main(
                    [
                        "--repo",
                        str(repository),
                        "validate",
                        "--owner",
                        "root",
                        "--assignment",
                        str(created["assignment"]["assignment_id"]),
                        "--task-id",
                        str(fixture["task_id"]),
                        "--thread-id",
                        str(fixture["thread_id"]),
                        "--diff",
                    ]
                )
            self.assertEqual(exit_code, 2)
            self.assertIn("OUTSIDE_ASSIGNMENT\toutside.txt", stderr.getvalue())

    def test_process_races_create_one_bundle_and_one_ack_event(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = _assignment_candidate(Path(temporary), task_id="race-task")
            deadline = (
                datetime.now(timezone.utc) + timedelta(minutes=10)
            ).replace(microsecond=0).isoformat().replace("+00:00", "Z")
            tool = PROJECT_ROOT / "tools" / "workbench_contract.py"
            create_command = [
                sys.executable,
                "-B",
                str(tool),
                "--repo",
                str(fixture["repository"]),
                "assignment",
                "create",
                "--task-id",
                str(fixture["task_id"]),
                "--thread-id",
                str(fixture["thread_id"]),
                "--owner",
                "root",
                "--brief",
                str(fixture["brief"]),
                "--destination",
                str(fixture["destination"]),
                "--common-dir",
                str(fixture["common_git_dir"]),
                "--branch",
                str(fixture["branch"]),
                "--head",
                str(fixture["head"]),
                "--tree",
                str(fixture["tree"]),
                "--write-set",
                str(fixture["write_set_path"]),
                "--candidate-receipt",
                str(fixture["candidate_receipt"]),
                "--run-receipt",
                str(fixture["run_receipt"]),
                "--ack-deadline",
                deadline,
                "--json",
            ]
            creators = [
                subprocess.Popen(create_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                for _ in range(2)
            ]
            create_results = [process.communicate(timeout=30) for process in creators]
            task_directory = (
                contract.assignment_store(fixture["repository"])
                / contract._assignment_task_hash(str(fixture["task_id"]))
            )
            bundles = [path for path in task_directory.iterdir() if not path.name.startswith(".")]
            self.assertEqual(len(bundles), 1, create_results)
            assignment = json.loads(
                (bundles[0] / "assignment.json").read_text(encoding="utf-8")
            )
            created_true = sum(
                b'"created": true' in stdout for stdout, _stderr in create_results
            )
            self.assertEqual(created_true, 1, create_results)

            ack_command = [
                sys.executable,
                "-B",
                str(tool),
                "--repo",
                str(fixture["repository"]),
                "assignment",
                "ack",
                "--task-id",
                str(fixture["task_id"]),
                "--assignment-id",
                str(assignment["assignment_id"]),
                "--thread-id",
                str(fixture["thread_id"]),
                "--owner",
                "root",
                "--write-set",
                str(fixture["write_set_path"]),
                "--json",
            ]
            acknowledgers = [
                subprocess.Popen(ack_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                for _ in range(2)
            ]
            ack_results = [process.communicate(timeout=30) for process in acknowledgers]
            self.assertTrue((bundles[0] / "ack.json").is_file(), ack_results)
            ack_created_true = sum(
                b'"created": true' in stdout for stdout, _stderr in ack_results
            )
            self.assertEqual(ack_created_true, 1, ack_results)


class TrackedEolCheckTest(unittest.TestCase):
    def test_eol_check_accepts_dirty_lf_and_hydrated_lfs_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            (repository / "source" / "input.txt").write_bytes(
                b"ordinary dirty authoring\n"
            )

            self.assertNotEqual(_git(repository, "status", "--porcelain"), "")
            self.assertIn(
                "w/lf",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            self.assertNotEqual(
                (repository / "generated" / "two.bin").read_bytes(),
                _git_bytes(repository, "show", "HEAD:generated/two.bin"),
            )
            self.assertGreater(contract.assert_tracked_lf_eol(repository), 0)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = contract.main(
                    ["--repo", str(repository), "eol-check"]
                )
            self.assertEqual(exit_code, 0, stderr.getvalue())
            self.assertIn("PASS tracked_eol_lf=", stdout.getvalue())

    def test_eol_check_rejects_crlf_in_dirty_authoring_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            (repository / "source" / "input.txt").write_bytes(b"dirty\r\n")

            self.assertIn(
                "w/crlf",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            with self.assertRaisesRegex(
                contract.ContractError,
                r"source/input\.txt \(w/crlf\)",
            ):
                contract.assert_tracked_lf_eol(repository)

            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = contract.main(
                    ["--repo", str(repository), "eol-check"]
                )
            self.assertEqual(exit_code, 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("source/input.txt (w/crlf)", stderr.getvalue())

    def test_eol_check_rejects_mixed_eol_in_dirty_authoring_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = _publication_candidate(Path(temporary))
            repository = candidate["repository"]
            (repository / "source" / "input.txt").write_bytes(
                b"first\r\nsecond\n"
            )

            self.assertIn(
                "w/mixed",
                _git(repository, "ls-files", "--eol", "source/input.txt"),
            )
            with self.assertRaisesRegex(
                contract.ContractError,
                r"source/input\.txt \(w/mixed\)",
            ):
                contract.assert_tracked_lf_eol(repository)


if __name__ == "__main__":
    unittest.main(verbosity=2)
