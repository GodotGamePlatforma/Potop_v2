#!/usr/bin/env python3
"""Freeze or verify an immutable agent hand-off directory.

The producer keeps editing its mutable staging directory.  ``freeze`` copies one
stable revision to a new sibling directory, writes the receipt last, and then
publishes the directory with one rename.  It never overwrites an existing hand-
off or any active project file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable

from workbench_lock import InterprocessWorkspaceLock, lock_name_for_path


RECEIPT_NAME = "FROZEN_RECEIPT.json"
RECEIPT_SCHEMA_VERSION = 1
EXCLUDED_DIRECTORY_NAMES = {
    ".git",
    ".godot",
    ".pytest_cache",
    "__pycache__",
    "tmp",
}


class FreezeError(RuntimeError):
    """Raised when a revision cannot be proven stable and complete."""


@dataclass(frozen=True)
class FileRecord:
    path: str
    size: int
    sha256: str

    def as_dict(self) -> dict[str, object]:
        return {
            "path": self.path,
            "size": self.size,
            "sha256": self.sha256,
        }


def _is_excluded_part(part: str) -> bool:
    return part in EXCLUDED_DIRECTORY_NAMES or (
        part.startswith(".") and ".tmp-" in part
    )


def inventory_tree(root: Path) -> tuple[FileRecord, ...]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise FreezeError(f"Revision root is not a directory: {root}")
    records: list[FileRecord] = []
    for directory, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        directory_path = Path(directory)
        directory_names[:] = sorted(
            name
            for name in directory_names
            if not _is_excluded_part(name)
        )
        for directory_name in directory_names:
            child = directory_path / directory_name
            if child.is_symlink():
                raise FreezeError(f"Symlinked directories are not allowed: {child}")
        for file_name in sorted(file_names):
            if file_name == RECEIPT_NAME:
                continue
            file_path = directory_path / file_name
            if file_path.is_symlink():
                raise FreezeError(f"Symlinked files are not allowed: {file_path}")
            relative = PurePosixPath(file_path.relative_to(root).as_posix())
            if any(_is_excluded_part(part) for part in relative.parts):
                continue
            raw = file_path.read_bytes()
            records.append(
                FileRecord(
                    path=relative.as_posix(),
                    size=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest(),
                )
            )
    records.sort(key=lambda record: record.path)
    return tuple(records)


def tree_sha256(records: Iterable[FileRecord]) -> str:
    digest = hashlib.sha256()
    for record in records:
        digest.update(record.path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(record.size).encode("ascii"))
        digest.update(b"\0")
        digest.update(record.sha256.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def _safe_distinct_paths(source: Path, target: Path) -> tuple[Path, Path]:
    source = source.resolve(strict=True)
    target = target.resolve(strict=False)
    if not source.is_dir():
        raise FreezeError(f"Source is not a directory: {source}")
    if target.exists():
        raise FreezeError(f"Frozen target already exists and is immutable: {target}")
    if source == target or target.is_relative_to(source):
        raise FreezeError("Frozen target must not be the source or its child.")
    target.parent.mkdir(parents=True, exist_ok=True)
    return source, target


def freeze_revision(source: Path, target: Path, owner: str) -> dict[str, object]:
    source, target = _safe_distinct_paths(source, target)
    lock_name = lock_name_for_path("freeze-revision", target)
    with InterprocessWorkspaceLock(target.parent, lock_name):
        before = inventory_tree(source)
        if not before:
            raise FreezeError("Cannot freeze an empty revision.")
        temporary = Path(
            tempfile.mkdtemp(prefix=f".{target.name}.tmp-", dir=target.parent)
        )
        committed = False
        try:
            for record in before:
                source_path = source / Path(record.path)
                destination_path = temporary / Path(record.path)
                destination_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_path, destination_path)

            after = inventory_tree(source)
            copied = inventory_tree(temporary)
            if before != after or after != copied:
                raise FreezeError(
                    "Revision changed while it was copied; no FROZEN hand-off "
                    "was published. Retry a short snapshot window."
                )
            receipt = {
                "schema_version": RECEIPT_SCHEMA_VERSION,
                "status": "FROZEN",
                "owner": owner,
                "revision": target.name,
                "tree_sha256": tree_sha256(copied),
                "file_count": len(copied),
                "files": [record.as_dict() for record in copied],
            }
            (temporary / RECEIPT_NAME).write_text(
                json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            os.replace(temporary, target)
            committed = True
            return receipt
        finally:
            if not committed and temporary.exists():
                shutil.rmtree(temporary)


def verify_revision(target: Path) -> dict[str, object]:
    target = target.resolve(strict=True)
    receipt_path = target / RECEIPT_NAME
    if not receipt_path.is_file():
        raise FreezeError(f"Frozen receipt is missing: {receipt_path}")
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FreezeError(f"Frozen receipt is invalid: {error}") from error
    required_keys = {
        "schema_version",
        "status",
        "owner",
        "revision",
        "tree_sha256",
        "file_count",
        "files",
    }
    if not isinstance(receipt, dict) or set(receipt) != required_keys:
        raise FreezeError("Frozen receipt has an invalid exact key set.")
    if (
        receipt["schema_version"] != RECEIPT_SCHEMA_VERSION
        or receipt["status"] != "FROZEN"
        or receipt["revision"] != target.name
    ):
        raise FreezeError("Frozen receipt identity/status is invalid.")
    raw_files = receipt["files"]
    if not isinstance(raw_files, list):
        raise FreezeError("Frozen receipt files must be a list.")
    try:
        expected = tuple(
            FileRecord(
                path=str(record["path"]),
                size=int(record["size"]),
                sha256=str(record["sha256"]),
            )
            for record in raw_files
        )
    except (KeyError, TypeError, ValueError) as error:
        raise FreezeError("Frozen receipt contains an invalid file record.") from error
    actual = inventory_tree(target)
    if expected != actual:
        raise FreezeError("Frozen revision file set or SHA-256 does not match receipt.")
    actual_tree_sha = tree_sha256(actual)
    if receipt["file_count"] != len(actual) or receipt["tree_sha256"] != actual_tree_sha:
        raise FreezeError("Frozen revision tree digest/count does not match receipt.")
    return receipt


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    freeze = subcommands.add_parser("freeze", help="publish one immutable hand-off")
    freeze.add_argument("--source", type=Path, required=True)
    freeze.add_argument("--target", type=Path, required=True)
    freeze.add_argument(
        "--owner",
        default=os.environ.get("CODEX_THREAD_ID", "external"),
    )
    verify = subcommands.add_parser("verify", help="verify one FROZEN hand-off")
    verify.add_argument("--target", type=Path, required=True)
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        receipt = (
            freeze_revision(args.source, args.target, args.owner)
            if args.command == "freeze"
            else verify_revision(args.target)
        )
    except (OSError, FreezeError) as error:
        print(f"workbench revision error: {error}", file=os.sys.stderr)
        return 1
    print(
        f"{receipt['status']} {receipt['revision']} "
        f"({receipt['file_count']} files, {receipt['tree_sha256']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
