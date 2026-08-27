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
