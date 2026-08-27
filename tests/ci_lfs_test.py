#!/usr/bin/env python3
"""Tests for deterministic and fail-closed Git LFS CI provenance."""

from __future__ import annotations

import contextlib
import copy
import hashlib
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

import ci_lfs  # noqa: E402


def _git(
    repository: Path,
    *arguments: str,
    allowed_returncodes: tuple[int, ...] = (0,),
) -> str:
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
    if result.returncode not in allowed_returncodes:
        raise AssertionError(
            f"git {' '.join(arguments)} failed ({result.returncode}): {result.stderr}"
        )
    return result.stdout.strip()


def _pointer(payload: bytes, *, oid: str | None = None, size: int | None = None) -> bytes:
    actual_oid = oid or hashlib.sha256(payload).hexdigest()
    actual_size = len(payload) if size is None else size
    return (
        "version https://git-lfs.github.com/spec/v1\n"
        f"oid sha256:{actual_oid}\n"
        f"size {actual_size}\n"
    ).encode("ascii")


def _new_repository(parent: Path) -> tuple[Path, dict[str, bytes], list[str]]:
    repository = parent / "repository"
    repository.mkdir()
    subprocess.run(
        ["git", "init", "-q", str(repository)],
        check=True,
        capture_output=True,
    )
    # Keep fixtures independent of a machine-wide Git LFS installation while
    # still exercising Git's cached filter=lfs attributes. Writing the exact
    # local fixture config once avoids seven process launches per repository.
    (repository / ".git" / "config").write_bytes(
        b"[core]\n"
        b"\tautocrlf = false\n"
        b"[user]\n"
        b"\temail = ci-lfs-test@example.invalid\n"
        b"\tname = CI LFS Test\n"
        b"[filter \"lfs\"]\n"
        b"\trequired = false\n"
        b"\tprocess =\n"
        b"\tclean =\n"
        b"\tsmudge =\n"
    )

    (repository / ".gitattributes").write_bytes(
        b"* text=auto eol=lf\n"
        b"*.bin filter=lfs diff=lfs merge=lfs -text\n"
    )
    (repository / "plain.txt").write_bytes(b"plain\n")
    first = b"first payload\x00with binary data\n"
    second = b"second payload\xff\x00\n"
    payloads = {
        hashlib.sha256(first).hexdigest(): first,
        hashlib.sha256(second).hexdigest(): second,
    }
    paths = ["assets/a.bin", "assets/nested/a-copy.bin", "assets/z.bin"]
    for path in paths:
        (repository / path).parent.mkdir(parents=True, exist_ok=True)
    (repository / paths[0]).write_bytes(_pointer(first))
    (repository / paths[1]).write_bytes(_pointer(first))
    (repository / paths[2]).write_bytes(_pointer(second))
    _git(repository, "add", "-A")
    _git(repository, "commit", "-q", "-m", "LFS pointers")
    return repository, payloads, paths


def _populate_store(store: Path, payloads: dict[str, bytes]) -> None:
    for oid, payload in payloads.items():
        target = store / oid[:2] / oid[2:4] / oid
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)


def _hydrate(repository: Path, payloads: dict[str, bytes], paths: list[str]) -> None:
    first_oid, second_oid = list(payloads)
    (repository / paths[0]).write_bytes(payloads[first_oid])
    (repository / paths[1]).write_bytes(payloads[first_oid])
    (repository / paths[2]).write_bytes(payloads[second_oid])


class CiLfsManifestTest(unittest.TestCase):
    def test_manifest_is_deterministic_deduplicated_and_exact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository, payloads, paths = _new_repository(root)

            first = ci_lfs.build_manifest(repository)
            second = ci_lfs.build_manifest(repository)

            self.assertEqual(first, second)
            self.assertEqual(first["schema"], ci_lfs.MANIFEST_SCHEMA)
            self.assertEqual(first["path_count"], 3)
            self.assertEqual(first["object_count"], 2)
            self.assertEqual(first["total_object_bytes"], sum(map(len, payloads.values())))
            self.assertEqual(
                [entry["path"] for entry in first["paths"]],
                sorted(paths),
            )
            self.assertEqual(
                [entry["oid_sha256"] for entry in first["objects"]],
                sorted(payloads),
            )
            self.assertRegex(str(first["object_set_digest"]), r"^[0-9a-f]{64}$")
            self.assertRegex(str(first["manifest_digest"]), r"^[0-9a-f]{64}$")
            self.assertEqual(first["git"]["head"], _git(repository, "rev-parse", "HEAD"))
            self.assertEqual(
                first["git"]["tree"],
                _git(repository, "rev-parse", "HEAD^{tree}"),
            )

            output_one = root / "one.json"
            output_two = root / "two.json"
            ci_lfs.write_manifest(output_one, first)
            ci_lfs.write_manifest(output_two, second)
            self.assertEqual(output_one.read_bytes(), output_two.read_bytes())
            self.assertEqual(ci_lfs.load_manifest(output_one), first)

            # Unstaged non-LFS worktree changes do not alter an exact-HEAD
            # manifest. Staged changes do, and therefore fail closed.
            (repository / "plain.txt").write_bytes(b"dirty but unstaged\n")
            self.assertEqual(ci_lfs.build_manifest(repository), first)
            _git(repository, "add", "plain.txt")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "index must match"):
                ci_lfs.build_manifest(repository)

    def test_filter_lfs_requires_a_canonical_pointer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, _payloads, paths = _new_repository(Path(temporary_directory))
            (repository / paths[0]).write_bytes(b"not a pointer\n")
            _git(repository, "add", paths[0])
            _git(repository, "commit", "-q", "-m", "invalid pointer")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "not an LFS v1 pointer"):
                ci_lfs.build_manifest(repository)

    def test_pointer_rejects_crlf_and_conflicting_oid_size(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, payloads, paths = _new_repository(Path(temporary_directory))
            oid = next(iter(payloads))
            (repository / paths[0]).write_bytes(_pointer(payloads[oid]).replace(b"\n", b"\r\n"))
            _git(repository, "add", paths[0])
            _git(repository, "commit", "-q", "-m", "CRLF pointer")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "Non-canonical"):
                ci_lfs.build_manifest(repository)

        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, payloads, paths = _new_repository(Path(temporary_directory))
            oid = next(iter(payloads))
            (repository / paths[2]).write_bytes(_pointer(b"unused", oid=oid, size=999))
            _git(repository, "add", paths[2])
            _git(repository, "commit", "-q", "-m", "conflicting size")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "conflicting sizes"):
                ci_lfs.build_manifest(repository)

    def test_pointer_size_limit_and_extensions_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, _payloads, paths = _new_repository(Path(temporary_directory))
            oversized = _pointer(b"unused")[:-1] + b" " * 950 + b"\n"
            self.assertGreaterEqual(len(oversized), ci_lfs.MAX_POINTER_BYTES)
            (repository / paths[0]).write_bytes(oversized)
            _git(repository, "add", paths[0])
            _git(repository, "commit", "-q", "-m", "oversized pointer")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "pointer size limit"):
                ci_lfs.build_manifest(repository)

        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, payloads, paths = _new_repository(Path(temporary_directory))
            payload = next(iter(payloads.values()))
            oid = hashlib.sha256(payload).hexdigest()
            extension_pointer = (
                "version https://git-lfs.github.com/spec/v1\n"
                f"ext-0-transform sha256:{oid}\n"
                f"oid sha256:{oid}\n"
                f"size {len(payload)}\n"
            ).encode("ascii")
            (repository / paths[0]).write_bytes(extension_pointer)
            _git(repository, "add", paths[0])
            _git(repository, "commit", "-q", "-m", "extension pointer")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "extensions are not supported"):
                ci_lfs.build_manifest(repository)

    def test_manifest_tampering_and_duplicate_json_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository, _payloads, _paths = _new_repository(root)
            manifest = ci_lfs.build_manifest(repository)
            tampered = copy.deepcopy(manifest)
            tampered["path_count"] = 999
            with self.assertRaises(ci_lfs.LfsContractError):
                ci_lfs.validate_manifest(tampered)

            duplicate = root / "duplicate.json"
            duplicate.write_text(
                '{"schema":"one","schema":"two"}\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "Duplicate JSON key"):
                ci_lfs.load_manifest(duplicate)


class CiLfsPayloadVerificationTest(unittest.TestCase):
    def test_cache_verification_hashes_size_and_optional_exact_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository, payloads, _paths = _new_repository(root)
            manifest = ci_lfs.build_manifest(repository)
            store = root / "object-store"
            store.mkdir()
            _populate_store(store, payloads)

            result = ci_lfs.verify_object_store(manifest, store, reject_extra=True)
            self.assertEqual(result["object_count"], 2)
            self.assertTrue(result["reject_extra"])

            extra = store / "tmp" / "untrusted.part"
            extra.parent.mkdir()
            extra.write_bytes(b"extra")
            ci_lfs.verify_object_store(manifest, store, reject_extra=False)
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "not exact"):
                ci_lfs.verify_object_store(manifest, store, reject_extra=True)
            extra.unlink()

            oid = next(iter(payloads))
            object_path = store / oid[:2] / oid[2:4] / oid
            original = object_path.read_bytes()
            object_path.write_bytes(b"X" * len(original))
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "SHA-256 mismatch"):
                ci_lfs.verify_object_store(manifest, store)
            object_path.write_bytes(original[:-1])
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "Size mismatch"):
                ci_lfs.verify_object_store(manifest, store)
            object_path.unlink()
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "Missing regular file"):
                ci_lfs.verify_object_store(manifest, store)

    def test_worktree_requires_every_hydrated_path_for_exact_head(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, payloads, paths = _new_repository(Path(temporary_directory))
            manifest = ci_lfs.build_manifest(repository)

            with self.assertRaises(ci_lfs.LfsContractError):
                ci_lfs.verify_worktree(repository, manifest)
            _hydrate(repository, payloads, paths)
            result = ci_lfs.verify_worktree(repository, manifest)
            self.assertEqual(result["path_count"], 3)
            self.assertEqual(result["total_path_bytes"], 2 * len(next(iter(payloads.values()))) + len(list(payloads.values())[1]))

            (repository / paths[1]).write_bytes(b"corrupted")
            with self.assertRaises(ci_lfs.LfsContractError):
                ci_lfs.verify_worktree(repository, manifest)

    def test_manifest_from_another_head_is_rejected_before_payload_use(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository, payloads, paths = _new_repository(Path(temporary_directory))
            manifest = ci_lfs.build_manifest(repository)
            _hydrate(repository, payloads, paths)
            (repository / "plain.txt").write_bytes(b"new revision\n")
            _git(repository, "add", "plain.txt")
            _git(repository, "commit", "-q", "-m", "new HEAD")
            with self.assertRaisesRegex(ci_lfs.LfsContractError, "does not describe"):
                ci_lfs.verify_worktree(repository, manifest)

    def test_default_store_uses_git_common_dir_for_linked_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository, _payloads, _paths = _new_repository(root)
            linked = root / "linked"
            _git(repository, "worktree", "add", "-q", "-b", "linked-test", str(linked), "HEAD")
            try:
                manifest = ci_lfs.build_manifest(linked)
                self.assertEqual(manifest["git"]["head"], _git(repository, "rev-parse", "HEAD"))
                common = Path(
                    _git(
                        linked,
                        "rev-parse",
                        "--path-format=absolute",
                        "--git-common-dir",
                    )
                ).resolve()
                self.assertEqual(
                    ci_lfs.default_object_store(linked),
                    (common / "lfs" / "objects").resolve(),
                )
            finally:
                _git(repository, "worktree", "remove", "--force", str(linked))

    def test_cli_roundtrip_emits_machine_readable_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repository, payloads, paths = _new_repository(root)
            manifest_path = root / "manifest.json"

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                exit_code = ci_lfs.main(
                    [
                        "manifest",
                        "--repo",
                        str(repository),
                        "--output",
                        str(manifest_path),
                    ]
                )
            self.assertEqual(exit_code, 0)
            self.assertEqual(json.loads(output.getvalue())["status"], "PASS")

            store = root / "cache"
            store.mkdir()
            _populate_store(store, payloads)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                exit_code = ci_lfs.main(
                    [
                        "verify-cache",
                        "--repo",
                        str(repository),
                        "--manifest",
                        str(manifest_path),
                        "--object-store",
                        str(store),
                        "--reject-extra",
                    ]
                )
            self.assertEqual(exit_code, 0)
            self.assertEqual(json.loads(output.getvalue())["operation"], "verify-cache")

            _hydrate(repository, payloads, paths)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                exit_code = ci_lfs.main(
                    [
                        "verify-worktree",
                        "--repo",
                        str(repository),
                        "--manifest",
                        str(manifest_path),
                    ]
                )
            self.assertEqual(exit_code, 0)
            self.assertEqual(json.loads(output.getvalue())["operation"], "verify-worktree")


if __name__ == "__main__":
    unittest.main()
