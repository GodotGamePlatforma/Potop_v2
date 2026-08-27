#!/usr/bin/env python3
"""Machine-readable ownership checks for concurrent repository work.

The module deliberately separates *file ownership* from the integration role.
An integration agent may compose files owned by several domains, but authoring
agents are accepted only when every declared or detected write belongs to their
single domain.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable, Sequence

from workbench_lock import InterprocessWorkspaceLock


OWNER_ROOT = "root"
OWNER_MAP = "map"
OWNER_DIVER = "diver"
OWNER_INTEGRATION = "integration"
STRUCTURE_OWNER_PATTERN = re.compile(r"structure:([a-z][a-z0-9_]*)\Z")
STRUCTURE_ID_PATTERN = re.compile(r"[a-z][a-z0-9_]*\Z")
LOCK_NAME_PATTERN = re.compile(r"[a-z0-9][a-z0-9._-]{0,95}\Z")
DEFAULT_PUBLICATION_LOCK = "integration-publish"
LAST_GREEN_REF = "refs/last-green/integration"
PUBLICATION_RECEIPT_SCHEMA_VERSION = 1
PUBLICATION_RECEIPT_STATUS = "PUBLICATION_READY"


class ContractError(RuntimeError):
    """Raised when repository state cannot satisfy the ownership contract."""


@dataclass(frozen=True)
class OwnershipViolation:
    path: str
    requested_owner: str
    actual_owner: str


@dataclass(frozen=True)
class PublicationFileRecord:
    path: str
    size: int
    sha256: str


@dataclass(frozen=True)
class DoctorReport:
    worktree: str
    branch: str
    head: str
    git_common_dir: str
    publication_lock: str
    owner: str
    intent: str
    inventory_count: int
    dirty_paths: tuple[str, ...]
    violations: tuple[OwnershipViolation, ...]
    structure_status: str | None
    publication_receipt: str | None
    publication_receipt_verified: bool
    ready: bool
    reasons: tuple[str, ...]


def _find_git_boundary(start: str | Path) -> Path:
    candidate = Path(start).resolve(strict=False)
    if candidate.is_file():
        candidate = candidate.parent
    for directory in (candidate, *candidate.parents):
        if (directory / ".git").exists():
            return directory
    raise ContractError(f"No Git worktree found at or above: {candidate}")


def _run_git(
    repository: str | Path,
    *arguments: str,
    check: bool = True,
    input_data: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    boundary = _find_git_boundary(repository)
    command = [
        "git",
        "-c",
        f"safe.directory={boundary}",
        "-C",
        str(boundary),
        *arguments,
    ]
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        input=input_data,
    )
    if check and result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ContractError(
            f"Git command failed ({result.returncode}): {' '.join(command)}"
            + (f"\n{detail}" if detail else "")
        )
    return result


def repository_root(start: str | Path = ".") -> Path:
    boundary = _find_git_boundary(start)
    raw = _run_git(boundary, "rev-parse", "--show-toplevel").stdout
    return Path(os.fsdecode(raw).strip()).resolve(strict=True)


def git_common_dir(repository: str | Path = ".") -> Path:
    root = repository_root(repository)
    raw = os.fsdecode(
        _run_git(root, "rev-parse", "--git-common-dir").stdout
    ).strip()
    common = Path(raw)
    if not common.is_absolute():
        common = root / common
    return common.resolve(strict=False)


def publication_lock(
    repository: str | Path = ".",
    name: str = DEFAULT_PUBLICATION_LOCK,
) -> InterprocessWorkspaceLock:
    """Return one lock shared by every worktree of the same repository."""

    if LOCK_NAME_PATTERN.fullmatch(name) is None:
        raise ContractError(
            "Publication lock name must contain only lowercase a-z, 0-9, "
            "'.', '_' or '-'."
        )
    common = git_common_dir(repository)
    return InterprocessWorkspaceLock(common, name)


def publication_lock_path(
    repository: str | Path = ".",
    name: str = DEFAULT_PUBLICATION_LOCK,
) -> Path:
    return publication_lock(repository, name).path


def _decode_nul_paths(payload: bytes) -> tuple[str, ...]:
    result: list[str] = []
    for raw_path in payload.split(b"\0"):
        if not raw_path:
            continue
        result.append(normalize_repo_path(os.fsdecode(raw_path)))
    return tuple(result)


def normalize_repo_path(path: str | os.PathLike[str]) -> str:
    raw = os.fspath(path).strip().replace("\\", "/")
    if not raw or raw.startswith("/") or re.match(r"^[A-Za-z]:", raw):
        raise ContractError(f"Write path must be repository-relative: {path}")
    if "\0" in raw:
        raise ContractError("Write path cannot contain NUL.")
    parts = PurePosixPath(raw).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise ContractError(f"Unsafe repository-relative path: {path}")
    return PurePosixPath(*parts).as_posix()


def normalize_owner(owner: str) -> str:
    normalized = owner.strip().lower()
    if normalized in {OWNER_ROOT, OWNER_MAP, OWNER_DIVER, OWNER_INTEGRATION}:
        return normalized
    match = STRUCTURE_OWNER_PATTERN.fullmatch(normalized)
    if match is not None:
        return f"structure:{match.group(1)}"
    raise ContractError(
        "Owner must be root, map, diver, integration or structure:<id>."
    )


def owner_for_path(path: str | os.PathLike[str]) -> str:
    normalized = normalize_repo_path(path)
    parts = PurePosixPath(normalized).parts
    if parts[0] == "diver_workbench":
        return OWNER_DIVER
    if parts[0] != "underwater_map_workbench":
        return OWNER_ROOT
    if len(parts) >= 3 and parts[1] == "structures":
        structure_id = parts[2]
        if STRUCTURE_ID_PATTERN.fullmatch(structure_id) is not None:
            if len(parts) >= 4 and parts[3] == "generated":
                return OWNER_MAP
            return f"structure:{structure_id}"
    return OWNER_MAP


def owner_allows(owner: str, path: str | os.PathLike[str]) -> bool:
    normalized_owner = normalize_owner(owner)
    return normalized_owner == OWNER_INTEGRATION or owner_for_path(path) == normalized_owner


def validate_paths(
    owner: str,
    paths: Iterable[str | os.PathLike[str]],
) -> tuple[OwnershipViolation, ...]:
    normalized_owner = normalize_owner(owner)
    violations: list[OwnershipViolation] = []
    for path in sorted({normalize_repo_path(value) for value in paths}):
        actual_owner = owner_for_path(path)
        if normalized_owner != OWNER_INTEGRATION and actual_owner != normalized_owner:
            violations.append(
                OwnershipViolation(
                    path=path,
                    requested_owner=normalized_owner,
                    actual_owner=actual_owner,
                )
            )
    return tuple(violations)


def inventory_paths(repository: str | Path = ".") -> tuple[str, ...]:
    """Return tracked plus nonignored untracked files from Git's authority."""

    root = repository_root(repository)
    payload = _run_git(
        root,
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "-z",
    ).stdout
    return tuple(sorted(set(_decode_nul_paths(payload))))


def _untracked_paths(repository: Path) -> tuple[str, ...]:
    return _decode_nul_paths(
        _run_git(
            repository,
            "ls-files",
            "--others",
            "--exclude-standard",
            "-z",
        ).stdout
    )


def _tracked_paths(repository: Path) -> tuple[str, ...]:
    return _decode_nul_paths(
        _run_git(repository, "ls-files", "--cached", "-z").stdout
    )


def _tracked_git_attributes(
    repository: Path,
    paths: Iterable[str],
) -> dict[str, dict[str, str]]:
    normalized_paths = tuple(sorted({normalize_repo_path(path) for path in paths}))
    if not normalized_paths:
        return {}
    standard_input = b"".join(
        os.fsencode(path) + b"\0" for path in normalized_paths
    )
    payload = _run_git(
        repository,
        "check-attr",
        "--cached",
        "-z",
        "--stdin",
        "text",
        "eol",
        "filter",
        input_data=standard_input,
    ).stdout
    fields = payload.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    if len(fields) % 3 != 0:
        raise ContractError("Git returned malformed check-attr output.")

    expected_attributes = {"text", "eol", "filter"}
    result: dict[str, dict[str, str]] = {}
    for offset in range(0, len(fields), 3):
        path = normalize_repo_path(os.fsdecode(fields[offset]))
        attribute = fields[offset + 1].decode("ascii", errors="strict")
        value = os.fsdecode(fields[offset + 2])
        if path not in normalized_paths or attribute not in expected_attributes:
            raise ContractError("Git returned unexpected check-attr output.")
        values = result.setdefault(path, {})
        if attribute in values:
            raise ContractError("Git returned duplicate check-attr output.")
        values[attribute] = value

    if set(result) != set(normalized_paths) or any(
        set(values) != expected_attributes for values in result.values()
    ):
        raise ContractError("Git check-attr output is incomplete.")
    return result


def _index_entries(repository: Path) -> dict[str, tuple[str, str]]:
    payload = _run_git(repository, "ls-files", "--stage", "-z").stdout
    result: dict[str, tuple[str, str]] = {}
    for raw_record in payload.split(b"\0"):
        if not raw_record:
            continue
        try:
            metadata, raw_path = raw_record.split(b"\t", 1)
            mode, object_id, stage = metadata.split(b" ")
        except ValueError as error:
            raise ContractError("Git returned malformed index metadata.") from error
        path = normalize_repo_path(os.fsdecode(raw_path))
        if stage != b"0" or path in result:
            raise ContractError(
                f"Publication candidate has unresolved index stages: {path}"
            )
        result[path] = (
            mode.decode("ascii", errors="strict"),
            object_id.decode("ascii", errors="strict"),
        )
    return result


def _head_tree_entries(repository: Path) -> dict[str, tuple[str, str, str]]:
    payload = _run_git(
        repository,
        "ls-tree",
        "-r",
        "-z",
        "--full-tree",
        "HEAD",
    ).stdout
    result: dict[str, tuple[str, str, str]] = {}
    for raw_record in payload.split(b"\0"):
        if not raw_record:
            continue
        try:
            metadata, raw_path = raw_record.split(b"\t", 1)
            mode, object_type, object_id = metadata.split(b" ")
        except ValueError as error:
            raise ContractError("Git returned malformed HEAD tree metadata.") from error
        path = normalize_repo_path(os.fsdecode(raw_path))
        if path in result:
            raise ContractError(f"Git returned duplicate HEAD tree path: {path}")
        result[path] = (
            mode.decode("ascii", errors="strict"),
            object_type.decode("ascii", errors="strict"),
            object_id.decode("ascii", errors="strict"),
        )
    return result


def _working_tree_raw_blob_ids(
    repository: Path,
    paths: Iterable[str],
) -> dict[str, str]:
    normalized_paths = tuple(sorted({normalize_repo_path(path) for path in paths}))
    result: dict[str, str] = {}
    chunk: list[str] = []
    chunk_length = 0

    def flush() -> None:
        nonlocal chunk, chunk_length
        if not chunk:
            return
        payload = _run_git(
            repository,
            "hash-object",
            "--no-filters",
            "--",
            *chunk,
        ).stdout
        object_ids = payload.decode("ascii", errors="strict").splitlines()
        if len(object_ids) != len(chunk):
            raise ContractError("Git hash-object returned an incomplete raw-byte set.")
        result.update(zip(chunk, object_ids, strict=True))
        chunk = []
        chunk_length = 0

    for path in normalized_paths:
        # Keep command lines comfortably below Windows' process limit while
        # preserving argv-safe handling of every repository-relative path.
        path_length = len(os.fsencode(path)) + 1
        if chunk and (len(chunk) >= 128 or chunk_length + path_length > 12_000):
            flush()
        chunk.append(path)
        chunk_length += path_length
    flush()
    return result


def _assert_tracked_text_bytes_reproducible(repository: Path) -> None:
    """Reject clean-filter-only equality that cannot reproduce raw worktree bytes."""

    tracked_paths = _tracked_paths(repository)
    attributes = _tracked_git_attributes(repository, tracked_paths)
    index_entries = _index_entries(repository)
    head_entries = _head_tree_entries(repository)
    protected: list[tuple[str, str]] = []
    for path in tracked_paths:
        values = attributes[path]
        if values["filter"].lower() == "lfs" or values["text"] == "unset":
            # Git LFS intentionally has a pointer in Git and a payload in the
            # worktree. Comparing those as ordinary text would reject every
            # valid hydrated checkout.
            continue
        is_text = values["text"] not in {"unset", "unspecified"} or values["eol"] == "lf"
        if not is_text:
            continue
        index_entry = index_entries.get(path)
        head_entry = head_entries.get(path)
        if index_entry is None or head_entry is None:
            raise ContractError(
                f"Tracked publication path is absent from HEAD/index: {path}"
            )
        index_mode, index_object = index_entry
        head_mode, head_type, head_object = head_entry
        if not index_mode.startswith("100") or head_type != "blob":
            # A submodule or symlink is not a tracked text file payload.
            continue
        if index_mode != head_mode or index_object != head_object:
            raise ContractError(
                f"Tracked text path differs between exact HEAD and index: {path}"
            )
        protected.append((path, index_object))

    working_objects = _working_tree_raw_blob_ids(
        repository,
        (path for path, _ in protected),
    )
    mismatched = [
        path
        for path, object_id in protected
        if working_objects[path] != object_id
    ]
    if mismatched:
        raise ContractError(
            "Publication requires raw bytes of tracked text files to match "
            "their exact HEAD/index blobs; clean-filter drift: "
            + ", ".join(mismatched)
        )


def assert_tracked_text_bytes_reproducible(
    repository: str | Path = ".",
) -> None:
    """Public fail-closed check reusable by candidate builders and runners."""

    root = repository_root(repository)
    _assert_tracked_text_bytes_reproducible(root)


def _tracked_worktree_eol_states(repository: Path) -> dict[str, str]:
    """Return Git's working-tree EOL classification for every tracked path."""

    payload = _run_git(
        repository,
        "ls-files",
        "--eol",
        "-z",
        "--",
    ).stdout
    result: dict[str, str] = {}
    for raw_record in payload.split(b"\0"):
        if not raw_record:
            continue
        try:
            metadata, raw_path = raw_record.split(b"\t", 1)
        except ValueError as error:
            raise ContractError("Git returned malformed ls-files --eol output.") from error
        worktree_states = [
            token.decode("ascii", errors="strict")
            for token in metadata.split()
            if token.startswith(b"w/")
        ]
        if len(worktree_states) != 1:
            raise ContractError("Git returned malformed ls-files --eol metadata.")
        path = normalize_repo_path(os.fsdecode(raw_path))
        if path in result:
            raise ContractError(f"Git returned duplicate EOL metadata: {path}")
        result[path] = worktree_states[0]

    tracked_paths = set(_tracked_paths(repository))
    if set(result) != tracked_paths:
        missing = sorted(tracked_paths - set(result))
        unexpected = sorted(set(result) - tracked_paths)
        details: list[str] = []
        if missing:
            details.append("missing=" + ", ".join(missing))
        if unexpected:
            details.append("unexpected=" + ", ".join(unexpected))
        raise ContractError(
            "Git ls-files --eol output is incomplete: " + "; ".join(details)
        )
    return result


def assert_tracked_lf_eol(repository: str | Path = ".") -> int:
    """Reject CRLF/mixed worktree bytes for tracked files governed by eol=lf.

    Unlike the immutable publication check above, this format-only gate permits
    ordinary dirty authoring changes. The returned count is the number of
    tracked, non-LFS paths whose cached Git attributes require ``eol=lf``.
    """

    root = repository_root(repository)
    tracked_paths = _tracked_paths(root)
    attributes = _tracked_git_attributes(root, tracked_paths)
    worktree_states = _tracked_worktree_eol_states(root)
    checked = 0
    violations: list[tuple[str, str]] = []
    for path in tracked_paths:
        values = attributes[path]
        if values["eol"].lower() != "lf":
            continue
        if values["filter"].lower() == "lfs" or values["text"] == "unset":
            continue
        checked += 1
        state = worktree_states[path]
        if state in {"w/crlf", "w/mixed"}:
            violations.append((path, state))

    if violations:
        raise ContractError(
            "Tracked files governed by eol=lf must use LF worktree bytes; "
            "invalid EOL: "
            + ", ".join(f"{path} ({state})" for path, state in violations)
        )
    return checked


def changed_paths(
    repository: str | Path = ".",
    base: str | None = None,
) -> tuple[str, ...]:
    """Return committed/worktree changes and nonignored untracked paths."""

    root = repository_root(repository)
    paths: set[str] = set(_untracked_paths(root))
    if base:
        payload = _run_git(
            root,
            "diff",
            "--name-only",
            "--no-renames",
            "-z",
            base,
            "--",
        ).stdout
        paths.update(_decode_nul_paths(payload))
    else:
        for arguments in (
            ("diff", "--name-only", "--no-renames", "-z", "--"),
            ("diff", "--cached", "--name-only", "--no-renames", "-z", "--"),
        ):
            paths.update(_decode_nul_paths(_run_git(root, *arguments).stdout))
    return tuple(sorted(paths))


def read_write_set(path: str | Path) -> tuple[str, ...]:
    source = Path(path)
    try:
        raw = source.read_bytes()
    except OSError as error:
        raise ContractError(f"Cannot read write-set {source}: {error}") from error
    if b"\0" in raw:
        return _decode_nul_paths(raw)
    result: list[str] = []
    for line in raw.decode("utf-8").splitlines():
        candidate = line.strip()
        if not candidate or candidate.startswith("#"):
            continue
        result.append(normalize_repo_path(candidate))
    return tuple(result)


def _structure_package_status(
    repository: Path,
    structure_id: str,
) -> tuple[str, tuple[str, ...]]:
    package_path = (
        repository
        / "underwater_map_workbench"
        / "structures"
        / structure_id
    )
    if not package_path.is_dir():
        return (
            "missing",
            (f"structure package directory does not exist: {package_path}",),
        )

    required_files = ("AGENTS.md", "README.md", "structure_manifest.json")
    missing_files = tuple(
        name for name in required_files if not (package_path / name).is_file()
    )
    reasons: list[str] = []
    if missing_files:
        reasons.append(
            "structure package is incomplete; missing " + ", ".join(missing_files)
        )
    else:
        try:
            manifest = json.loads(
                (package_path / "structure_manifest.json").read_text(
                    encoding="utf-8"
                )
            )
            if not isinstance(manifest, dict):
                reasons.append("structure_manifest.json must contain an object")
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            reasons.append(f"structure_manifest.json is invalid: {error}")

    map_manifest_path = repository / "underwater_map_workbench" / "map_manifest.json"
    if not map_manifest_path.is_file():
        return ("staging", tuple(reasons))
    try:
        map_manifest = json.loads(map_manifest_path.read_text(encoding="utf-8"))
        instances = map_manifest["structures"]["instances"]
        if not isinstance(instances, list):
            raise TypeError("structures.instances must be a list")
    except (
        OSError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        KeyError,
        TypeError,
    ) as error:
        reasons.append(f"map structure registry is invalid: {error}")
        return ("invalid_registration", tuple(reasons))

    matches = [
        record
        for record in instances
        if isinstance(record, dict) and record.get("id") == structure_id
    ]
    if not matches:
        return ("staging", tuple(reasons))
    expected_path = f"structures/{structure_id}/structure_manifest.json"
    if len(matches) != 1:
        reasons.append(
            f"structure registry contains {len(matches)} records for {structure_id}"
        )
        return ("invalid_registration", tuple(reasons))
    package = matches[0].get("package")
    if not isinstance(package, dict) or package.get("path") != expected_path:
        reasons.append(
            f"registered structure package must use path {expected_path}"
        )
        return ("invalid_registration", tuple(reasons))
    return ("registered", tuple(reasons))


def _repo_file(repository: Path, path: str) -> Path:
    normalized = normalize_repo_path(path)
    candidate = repository.joinpath(*PurePosixPath(normalized).parts)
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as error:
        raise ContractError(f"Publication path does not exist: {normalized}") from error
    if not resolved.is_relative_to(repository):
        raise ContractError(f"Publication path escapes worktree: {normalized}")
    if candidate.is_symlink() or not resolved.is_file():
        raise ContractError(f"Publication path must be a regular file: {normalized}")
    return resolved


def _closed_root_inventory(
    repository: Path,
    roots: Iterable[str | os.PathLike[str]],
    label: str,
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    normalized_roots = tuple(
        sorted({normalize_repo_path(root) for root in roots})
    )
    if not normalized_roots:
        raise ContractError(f"Publication {label} roots cannot be empty.")
    files: set[str] = set()
    for root_path in normalized_roots:
        filesystem_root = repository.joinpath(*PurePosixPath(root_path).parts)
        try:
            resolved_root = filesystem_root.resolve(strict=True)
        except OSError as error:
            raise ContractError(
                f"Publication {label} root does not exist: {root_path}"
            ) from error
        if not resolved_root.is_relative_to(repository):
            raise ContractError(
                f"Publication {label} root escapes worktree: {root_path}"
            )
        if filesystem_root.is_symlink():
            raise ContractError(
                f"Publication {label} root cannot be a symlink: {root_path}"
            )
        candidates = [filesystem_root] if filesystem_root.is_file() else filesystem_root.rglob("*")
        for candidate in candidates:
            if candidate.is_symlink():
                raise ContractError(
                    f"Publication {label} root contains a symlink: {candidate}"
                )
            if not candidate.is_file():
                continue
            relative = candidate.relative_to(repository).as_posix()
            files.add(normalize_repo_path(relative))
    if not files:
        raise ContractError(f"Publication {label} roots contain no files.")
    return normalized_roots, tuple(sorted(files))


def _closed_list(path: str | Path, label: str) -> tuple[str, ...]:
    records = read_write_set(path)
    if not records:
        raise ContractError(f"Publication {label} list cannot be empty.")
    if len(set(records)) != len(records):
        raise ContractError(f"Publication {label} list contains duplicates.")
    return tuple(sorted(records))


def _publication_records(
    repository: Path,
    paths: Iterable[str],
) -> tuple[PublicationFileRecord, ...]:
    records: list[PublicationFileRecord] = []
    for path in sorted(paths):
        filesystem_path = _repo_file(repository, path)
        raw = filesystem_path.read_bytes()
        records.append(
            PublicationFileRecord(
                path=path,
                size=len(raw),
                sha256=hashlib.sha256(raw).hexdigest(),
            )
        )
    return tuple(records)


def _records_digest(records: Iterable[PublicationFileRecord]) -> str:
    digest = hashlib.sha256()
    for record in records:
        digest.update(record.path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(record.size).encode("ascii"))
        digest.update(b"\0")
        digest.update(record.sha256.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def _receipt_target(repository: Path, receipt_path: str | Path) -> Path:
    target = Path(receipt_path).resolve(strict=False)
    if target == repository or target.is_relative_to(repository):
        raise ContractError(
            "Publication receipt must be outside the candidate worktree so "
            "creating it cannot dirty the candidate."
        )
    return target


def _assert_clean_publication_candidate(repository: Path) -> None:
    dirty = changed_paths(repository)
    if dirty:
        raise ContractError(
            "Publication requires a clean candidate worktree; dirty paths: "
            + ", ".join(dirty)
        )


def _assert_publication_paths_tracked(
    repository: Path,
    inputs: Iterable[str],
    outputs: Iterable[str],
) -> None:
    tracked = set(_tracked_paths(repository))
    missing = sorted((set(inputs) | set(outputs)).difference(tracked))
    if missing:
        raise ContractError(
            "Publication files must be tracked by HEAD so the receipt can "
            "reproduce the immutable candidate worktree: " + ", ".join(missing)
        )


def create_publication_receipt(
    repository: str | Path,
    *,
    input_list: str | Path,
    output_list: str | Path,
    input_roots: Iterable[str | os.PathLike[str]],
    output_roots: Iterable[str | os.PathLike[str]],
    receipt_path: str | Path,
) -> dict[str, object]:
    root = repository_root(repository)
    target = _receipt_target(root, receipt_path)
    with publication_lock(root):
        _assert_clean_publication_candidate(root)
        _assert_tracked_text_bytes_reproducible(root)
        if target.exists():
            raise ContractError(
                f"Publication receipt already exists and is immutable: {target}"
            )
        declared_inputs = _closed_list(input_list, "input")
        declared_outputs = _closed_list(output_list, "output")
        normalized_input_roots, actual_inputs = _closed_root_inventory(
            root, input_roots, "input"
        )
        normalized_output_roots, actual_outputs = _closed_root_inventory(
            root, output_roots, "output"
        )
        if declared_inputs != actual_inputs:
            raise ContractError(
                "Publication input list is not closed over its roots: "
                f"declared={declared_inputs}, actual={actual_inputs}"
            )
        if declared_outputs != actual_outputs:
            raise ContractError(
                "Publication output list is not closed over its roots: "
                f"declared={declared_outputs}, actual={actual_outputs}"
            )
        overlap = sorted(set(actual_inputs).intersection(actual_outputs))
        if overlap:
            raise ContractError(
                "Publication inputs and outputs must be disjoint: " + ", ".join(overlap)
            )
        _assert_publication_paths_tracked(root, actual_inputs, actual_outputs)
        inputs = _publication_records(root, actual_inputs)
        outputs = _publication_records(root, actual_outputs)
        receipt: dict[str, object] = {
            "schema_version": PUBLICATION_RECEIPT_SCHEMA_VERSION,
            "status": PUBLICATION_RECEIPT_STATUS,
            "head": _git_text(root, "rev-parse", "HEAD"),
            "tree": _git_text(root, "rev-parse", "HEAD^{tree}"),
            "branch": _branch_name(root),
            "input_roots": normalized_input_roots,
            "output_roots": normalized_output_roots,
            "inputs": [asdict(record) for record in inputs],
            "outputs": [asdict(record) for record in outputs],
            "input_digest": _records_digest(inputs),
            "output_digest": _records_digest(outputs),
        }
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            dir=target.parent,
            prefix=f".{target.name}.",
            suffix=".tmp",
        )
        temporary_path = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
                json.dump(receipt, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_path, target)
        finally:
            temporary_path.unlink(missing_ok=True)
        return receipt


def _receipt_records(value: object, label: str) -> tuple[PublicationFileRecord, ...]:
    if not isinstance(value, list) or not value:
        raise ContractError(f"Publication receipt {label} must be a nonempty list.")
    records: list[PublicationFileRecord] = []
    for raw_record in value:
        if not isinstance(raw_record, dict) or set(raw_record) != {
            "path",
            "size",
            "sha256",
        }:
            raise ContractError(
                f"Publication receipt {label} contains an invalid record."
            )
        try:
            record = PublicationFileRecord(
                path=normalize_repo_path(str(raw_record["path"])),
                size=int(raw_record["size"]),
                sha256=str(raw_record["sha256"]),
            )
        except (TypeError, ValueError) as error:
            raise ContractError(
                f"Publication receipt {label} contains an invalid record."
            ) from error
        if record.size < 0 or re.fullmatch(r"[0-9a-f]{64}", record.sha256) is None:
            raise ContractError(
                f"Publication receipt {label} contains an invalid size/SHA."
            )
        records.append(record)
    if tuple(sorted(record.path for record in records)) != tuple(
        record.path for record in records
    ) or len({record.path for record in records}) != len(records):
        raise ContractError(
            f"Publication receipt {label} must be sorted and contain unique paths."
        )
    return tuple(records)


def verify_publication_receipt(
    repository: str | Path,
    receipt_path: str | Path,
) -> dict[str, object]:
    root = repository_root(repository)
    target = _receipt_target(root, receipt_path)
    with publication_lock(root):
        _assert_clean_publication_candidate(root)
        _assert_tracked_text_bytes_reproducible(root)
        try:
            receipt = json.loads(target.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ContractError(f"Publication receipt is unreadable: {error}") from error
        required_keys = {
            "schema_version",
            "status",
            "head",
            "tree",
            "branch",
            "input_roots",
            "output_roots",
            "inputs",
            "outputs",
            "input_digest",
            "output_digest",
        }
        if not isinstance(receipt, dict) or set(receipt) != required_keys:
            raise ContractError("Publication receipt has an invalid exact key set.")
        if (
            receipt["schema_version"] != PUBLICATION_RECEIPT_SCHEMA_VERSION
            or receipt["status"] != PUBLICATION_RECEIPT_STATUS
        ):
            raise ContractError("Publication receipt schema/status is invalid.")
        current_head = _git_text(root, "rev-parse", "HEAD")
        current_tree = _git_text(root, "rev-parse", "HEAD^{tree}")
        if receipt["head"] != current_head or receipt["tree"] != current_tree:
            raise ContractError(
                "Publication receipt HEAD/tree does not match the candidate."
            )
        input_roots, actual_input_paths = _closed_root_inventory(
            root, receipt["input_roots"], "input"
        )
        output_roots, actual_output_paths = _closed_root_inventory(
            root, receipt["output_roots"], "output"
        )
        if tuple(receipt["input_roots"]) != input_roots:
            raise ContractError("Publication receipt input roots are not canonical.")
        if tuple(receipt["output_roots"]) != output_roots:
            raise ContractError("Publication receipt output roots are not canonical.")
        expected_inputs = _receipt_records(receipt["inputs"], "inputs")
        expected_outputs = _receipt_records(receipt["outputs"], "outputs")
        if tuple(record.path for record in expected_inputs) != actual_input_paths:
            raise ContractError(
                "Publication input set changed (extra or omitted file)."
            )
        if tuple(record.path for record in expected_outputs) != actual_output_paths:
            raise ContractError(
                "Publication output set changed (extra or omitted file)."
            )
        _assert_publication_paths_tracked(
            root,
            actual_input_paths,
            actual_output_paths,
        )
        actual_inputs = _publication_records(root, actual_input_paths)
        actual_outputs = _publication_records(root, actual_output_paths)
        if expected_inputs != actual_inputs:
            raise ContractError("Publication input file content changed.")
        if expected_outputs != actual_outputs:
            raise ContractError("Publication output file content changed.")
        if receipt["input_digest"] != _records_digest(actual_inputs):
            raise ContractError("Publication input digest is invalid.")
        if receipt["output_digest"] != _records_digest(actual_outputs):
            raise ContractError("Publication output digest is invalid.")
        return receipt


def _publication_receipt_header(
    repository: Path,
    receipt_path: str | Path,
) -> dict[str, object]:
    target = _receipt_target(repository, receipt_path)
    try:
        receipt = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError(f"Publication receipt is unreadable: {error}") from error
    if not isinstance(receipt, dict):
        raise ContractError("Publication receipt must contain an object.")
    if (
        receipt.get("schema_version") != PUBLICATION_RECEIPT_SCHEMA_VERSION
        or receipt.get("status") != PUBLICATION_RECEIPT_STATUS
        or re.fullmatch(r"[0-9a-f]{40,64}", str(receipt.get("head", ""))) is None
        or re.fullmatch(r"[0-9a-f]{40,64}", str(receipt.get("tree", ""))) is None
    ):
        raise ContractError("Publication receipt has no valid candidate HEAD/tree.")
    return receipt


def last_green_head(repository: str | Path = ".") -> str | None:
    """Return the direct commit stored in the shared authoritative LKG ref."""

    root = repository_root(repository)
    symbolic = _run_git(
        root,
        "symbolic-ref",
        "--quiet",
        LAST_GREEN_REF,
        check=False,
    )
    if symbolic.returncode == 0:
        target = os.fsdecode(symbolic.stdout).strip()
        raise ContractError(
            f"{LAST_GREEN_REF} must be a direct ref, not a symbolic ref to {target}."
        )
    if symbolic.returncode not in {1, 128}:
        detail = symbolic.stderr.decode("utf-8", errors="replace").strip()
        raise ContractError(f"Cannot inspect {LAST_GREEN_REF}: {detail}")
    result = _run_git(
        root,
        "rev-parse",
        "--verify",
        "--quiet",
        LAST_GREEN_REF,
        check=False,
    )
    if result.returncode == 1:
        return None
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ContractError(f"Cannot read {LAST_GREEN_REF}: {detail}")
    object_id = os.fsdecode(result.stdout).strip()
    if re.fullmatch(r"[0-9a-f]{40,64}", object_id) is None:
        raise ContractError(f"{LAST_GREEN_REF} contains an invalid object ID.")
    object_type = _git_text(root, "cat-file", "-t", object_id)
    if object_type != "commit":
        raise ContractError(
            f"{LAST_GREEN_REF} must point directly to a commit, not {object_type}."
        )
    return object_id


def _verify_full_run_receipt(
    repository: Path,
    candidate_receipt: str | Path,
    run_receipt: str | Path,
) -> None:
    runner = repository / "tests" / "run_all_tests.ps1"
    if not runner.is_file():
        raise ContractError(f"Candidate has no run receipt verifier: {runner}")
    powershell = next(
        (
            executable
            for name in ("pwsh", "powershell.exe", "powershell")
            if (executable := shutil.which(name)) is not None
        ),
        None,
    )
    if powershell is None:
        raise ContractError("PowerShell is required to verify the full run receipt.")
    command = [
        powershell,
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(runner),
        "-VerifyRunReceipt",
        str(Path(run_receipt).resolve(strict=False)),
        "-CandidateReceipt",
        str(Path(candidate_receipt).resolve(strict=False)),
    ]
    try:
        result = subprocess.run(
            command,
            cwd=repository,
            check=False,
            capture_output=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired as error:
        raise ContractError(
            "Full run receipt verification timed out after 180 seconds."
        ) from error
    if result.returncode != 0:
        detail = (
            result.stdout.decode("utf-8", errors="replace")
            + "\n"
            + result.stderr.decode("utf-8", errors="replace")
        ).strip()
        raise ContractError(
            f"Full run receipt verification failed ({result.returncode}): {detail}"
        )


def resolve_last_green(
    repository: str | Path,
    *,
    candidate_receipt: str | Path,
    run_receipt: str | Path,
) -> dict[str, str]:
    """Resolve one verified immutable baseline from the shared LKG ref."""

    root = repository_root(repository)
    header = _publication_receipt_header(root, candidate_receipt)
    expected_head = str(header["head"])
    before = last_green_head(root)
    if before is None:
        raise ContractError(
            f"Authoritative last-green ref is missing: {LAST_GREEN_REF}"
        )
    if before != expected_head:
        raise ContractError(
            f"Candidate HEAD {expected_head} differs from {LAST_GREEN_REF} {before}."
        )

    _verify_full_run_receipt(root, candidate_receipt, run_receipt)
    receipt = verify_publication_receipt(root, candidate_receipt)
    current_head = _git_text(root, "rev-parse", "HEAD")
    current_tree = _git_text(root, "rev-parse", "HEAD^{tree}")
    after = last_green_head(root)
    if (
        receipt["head"] != current_head
        or receipt["tree"] != current_tree
        or before != after
        or after != current_head
    ):
        raise ContractError(
            "Candidate HEAD, run receipt and authoritative last-green ref did "
            "not remain identical during resolution."
        )
    return {"ref": LAST_GREEN_REF, "head": current_head, "tree": current_tree}


def _zero_object_id(repository: Path) -> str:
    object_format = _git_text(repository, "rev-parse", "--show-object-format")
    if object_format == "sha1":
        return "0" * 40
    if object_format == "sha256":
        return "0" * 64
    raise ContractError(f"Unsupported Git object format: {object_format}")


def promote_last_green(
    repository: str | Path,
    *,
    candidate_receipt: str | Path,
    run_receipt: str | Path,
    expected_old: str | None,
) -> dict[str, str]:
    """Promote a full-suite PASS candidate through Git's atomic ref CAS."""

    root = repository_root(repository)
    header = _publication_receipt_header(root, candidate_receipt)
    candidate_head = str(header["head"])
    candidate_tree = str(header["tree"])
    current_head = _git_text(root, "rev-parse", "HEAD")
    current_tree = _git_text(root, "rev-parse", "HEAD^{tree}")
    if candidate_head != current_head or candidate_tree != current_tree:
        raise ContractError("LKG promotion must run from the exact candidate HEAD/tree.")

    before = last_green_head(root)
    if expected_old is None:
        if before is not None:
            raise ContractError(
                f"Expected {LAST_GREEN_REF} to be missing, but it is {before}."
            )
    else:
        if re.fullmatch(r"[0-9a-f]{40,64}", expected_old) is None:
            raise ContractError("--expected-old must be a lowercase Git object ID or 'missing'.")
        expected_commit = _git_text(root, "rev-parse", f"{expected_old}^{{commit}}")
        if expected_commit != expected_old:
            raise ContractError("--expected-old must identify a commit directly.")
        if before != expected_old:
            raise ContractError(
                f"LKG compare-and-swap mismatch: expected {expected_old}, actual {before}."
            )
        ancestor = _run_git(
            root,
            "merge-base",
            "--is-ancestor",
            expected_old,
            candidate_head,
            check=False,
        )
        if ancestor.returncode != 0:
            raise ContractError(
                "LKG promotion must be a fast-forward descendant of the expected ref."
            )

    _verify_full_run_receipt(root, candidate_receipt, run_receipt)
    verified = verify_publication_receipt(root, candidate_receipt)
    if verified["head"] != candidate_head or verified["tree"] != candidate_tree:
        raise ContractError("Candidate receipt moved during LKG promotion.")
    if last_green_head(root) != before:
        raise ContractError("LKG ref moved while evidence was being verified; retry.")

    if before == candidate_head:
        return {
            "status": "UNCHANGED",
            "ref": LAST_GREEN_REF,
            "head": candidate_head,
            "tree": candidate_tree,
        }
    old_value = before if before is not None else _zero_object_id(root)
    update = _run_git(
        root,
        "update-ref",
        "--no-deref",
        "--create-reflog",
        "-m",
        "promote verified full-suite PASS",
        LAST_GREEN_REF,
        candidate_head,
        old_value,
        check=False,
    )
    if update.returncode != 0:
        detail = update.stderr.decode("utf-8", errors="replace").strip()
        raise ContractError(f"LKG compare-and-swap failed: {detail}")
    after = last_green_head(root)
    if after != candidate_head:
        raise ContractError(
            f"LKG postcondition failed: expected {candidate_head}, actual {after}."
        )
    return {
        "status": "PROMOTED",
        "ref": LAST_GREEN_REF,
        "head": candidate_head,
        "tree": candidate_tree,
    }


def _git_text(repository: Path, *arguments: str) -> str:
    return os.fsdecode(_run_git(repository, *arguments).stdout).strip()


def _branch_name(repository: Path) -> str:
    symbolic = _run_git(
        repository,
        "symbolic-ref",
        "--quiet",
        "--short",
        "HEAD",
        check=False,
    )
    if symbolic.returncode == 0:
        return os.fsdecode(symbolic.stdout).strip()
    return "(detached)"


def doctor_report(
    repository: str | Path,
    owner: str,
    intent: str = "author",
    *,
    allow_staging: bool = False,
    receipt_path: str | Path | None = None,
) -> DoctorReport:
    root = repository_root(repository)
    normalized_owner = normalize_owner(owner)
    normalized_intent = intent.strip().lower()
    if normalized_intent not in {"author", "integration", "publish"}:
        raise ContractError("Doctor intent must be author, integration or publish.")

    dirty = changed_paths(root)
    violations = validate_paths(normalized_owner, dirty)
    reasons: list[str] = []
    structure_status: str | None = None
    structure_match = STRUCTURE_OWNER_PATTERN.fullmatch(normalized_owner)
    if structure_match is not None:
        structure_status, structure_reasons = _structure_package_status(
            root, structure_match.group(1)
        )
        reasons.extend(structure_reasons)
        if structure_status == "staging" and not allow_staging:
            reasons.append(
                "unregistered structure package requires explicit allow_staging"
            )
        elif structure_status in {"missing", "invalid_registration"}:
            reasons.append(f"structure package status is {structure_status}")
    if violations:
        reasons.append(
            f"dirty write-set crosses {len(violations)} ownership boundary/boundaries"
        )
    if normalized_intent in {"integration", "publish"}:
        if normalized_owner != OWNER_INTEGRATION:
            reasons.append(
                f"intent {normalized_intent} requires owner={OWNER_INTEGRATION}"
            )
        if dirty:
            reasons.append(
                f"intent {normalized_intent} requires a clean source worktree"
            )
    receipt_verified = False
    normalized_receipt: str | None = None
    if receipt_path is not None:
        normalized_receipt = str(Path(receipt_path).resolve(strict=False))
    if normalized_intent == "publish":
        if receipt_path is None:
            reasons.append(
                "intent publish requires an explicit verified publication receipt"
            )
        elif not dirty:
            try:
                verify_publication_receipt(root, receipt_path)
                receipt_verified = True
            except ContractError as error:
                reasons.append(f"publication receipt verification failed: {error}")

    return DoctorReport(
        worktree=str(root),
        branch=_branch_name(root),
        head=_git_text(root, "rev-parse", "HEAD"),
        git_common_dir=str(git_common_dir(root)),
        publication_lock=str(publication_lock_path(root)),
        owner=normalized_owner,
        intent=normalized_intent,
        inventory_count=len(inventory_paths(root)),
        dirty_paths=dirty,
        violations=violations,
        structure_status=structure_status,
        publication_receipt=normalized_receipt,
        publication_receipt_verified=receipt_verified,
        ready=not reasons,
        reasons=tuple(reasons),
    )


def _write_json(value: object) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        default=".",
        help="path inside the Git worktree (default: current directory)",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    inventory = commands.add_parser(
        "inventory",
        help="list tracked and nonignored untracked files",
    )
    inventory.add_argument("--json", action="store_true")

    classify = commands.add_parser("classify", help="show the owner of paths")
    classify.add_argument("paths", nargs="+")
    classify.add_argument("--json", action="store_true")

    validate = commands.add_parser(
        "validate",
        help="validate an explicit write-set or current diff against one owner",
    )
    validate.add_argument("--owner", required=True)
    validate.add_argument("--path", action="append", default=[])
    validate.add_argument("--write-set", action="append", default=[])
    validate.add_argument("--diff", action="store_true")
    validate.add_argument("--base")
    validate.add_argument("--json", action="store_true")

    doctor = commands.add_parser(
        "doctor",
        help="show worktree/branch/dirty state and enforce integration cleanliness",
    )
    doctor.add_argument("--owner", required=True)
    doctor.add_argument(
        "--intent",
        choices=("author", "integration", "publish"),
        default="author",
    )
    doctor.add_argument(
        "--allow-staging",
        action="store_true",
        help="explicitly accept a complete but unregistered structure package",
    )
    doctor.add_argument(
        "--receipt",
        help="verified publication receipt required for intent=publish",
    )
    doctor.add_argument("--json", action="store_true")

    lock_path = commands.add_parser(
        "lock-path",
        help="show the publication lock shared by all worktrees",
    )
    lock_path.add_argument("--name", default=DEFAULT_PUBLICATION_LOCK)

    commands.add_parser(
        "eol-check",
        help="reject tracked eol=lf files with CRLF or mixed worktree bytes",
    )

    publication = commands.add_parser(
        "publication",
        help="create or verify a fail-closed publication receipt",
    )
    publication_commands = publication.add_subparsers(
        dest="publication_command",
        required=True,
    )
    publication_create = publication_commands.add_parser(
        "create",
        help="hash a clean candidate and publish an immutable receipt",
    )
    publication_create.add_argument("--input-list", required=True)
    publication_create.add_argument("--output-list", required=True)
    publication_create.add_argument("--input-root", action="append", required=True)
    publication_create.add_argument("--output-root", action="append", required=True)
    publication_create.add_argument("--receipt", required=True)
    publication_verify = publication_commands.add_parser(
        "verify",
        help="verify a receipt, clean candidate, HEAD/tree and closed file sets",
    )
    publication_verify.add_argument("--receipt", required=True)

    last_green = commands.add_parser(
        "lkg",
        help="resolve or atomically promote the authoritative last-green ref",
    )
    last_green_commands = last_green.add_subparsers(
        dest="last_green_command",
        required=True,
    )
    last_green_resolve = last_green_commands.add_parser(
        "resolve",
        help="require candidate, full PASS evidence and last-green to identify one commit",
    )
    last_green_resolve.add_argument("--candidate-receipt", required=True)
    last_green_resolve.add_argument("--run-receipt", required=True)
    last_green_promote = last_green_commands.add_parser(
        "promote",
        help="move last-green by Git compare-and-swap after full PASS verification",
    )
    last_green_promote.add_argument("--candidate-receipt", required=True)
    last_green_promote.add_argument("--run-receipt", required=True)
    last_green_promote.add_argument(
        "--expected-old",
        required=True,
        help="current last-green commit, or 'missing' for the first promotion",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        root = repository_root(args.repo)
        if args.command == "inventory":
            paths = inventory_paths(root)
            if args.json:
                _write_json({"count": len(paths), "paths": paths})
            else:
                print("\n".join(paths))
            return 0

        if args.command == "classify":
            records = [
                {"path": normalize_repo_path(path), "owner": owner_for_path(path)}
                for path in args.paths
            ]
            if args.json:
                _write_json(records)
            else:
                for record in records:
                    print(f"{record['owner']}\t{record['path']}")
            return 0

        if args.command == "validate":
            selector_supplied = bool(
                args.path or args.write_set or args.diff or args.base
            )
            paths: set[str] = {normalize_repo_path(path) for path in args.path}
            for write_set_path in args.write_set:
                paths.update(read_write_set(write_set_path))
            if args.diff or args.base:
                paths.update(changed_paths(root, args.base))
            if not selector_supplied:
                raise ContractError(
                    "validate requires --path, --write-set, --diff or --base"
                )
            owner = normalize_owner(args.owner)
            violations = validate_paths(owner, paths)
            payload = {
                "owner": owner,
                "path_count": len(paths),
                "ready": not violations,
                "violations": [asdict(item) for item in violations],
            }
            if args.json:
                _write_json(payload)
            elif violations:
                for item in violations:
                    print(
                        "CROSS_OWNER\t"
                        f"requested={item.requested_owner}\t"
                        f"actual={item.actual_owner}\t{item.path}",
                        file=sys.stderr,
                    )
            else:
                print(f"PASS owner={owner} paths={len(paths)}")
            return 0 if not violations else 2

        if args.command == "doctor":
            report = doctor_report(
                root,
                args.owner,
                args.intent,
                allow_staging=args.allow_staging,
                receipt_path=args.receipt,
            )
            payload = asdict(report)
            if args.json:
                _write_json(payload)
            else:
                print(f"worktree: {report.worktree}")
                print(f"branch: {report.branch}")
                print(f"head: {report.head}")
                print(f"git_common_dir: {report.git_common_dir}")
                print(f"publication_lock: {report.publication_lock}")
                print(f"owner: {report.owner}")
                print(f"intent: {report.intent}")
                if report.structure_status is not None:
                    print(f"structure_status: {report.structure_status}")
                if report.publication_receipt is not None:
                    print(f"publication_receipt: {report.publication_receipt}")
                    print(
                        "publication_receipt_verified: "
                        f"{report.publication_receipt_verified}"
                    )
                print(f"dirty: {len(report.dirty_paths)}")
                for path in report.dirty_paths:
                    print(f"  {owner_for_path(path)}\t{path}")
                for reason in report.reasons:
                    print(f"BLOCKED: {reason}", file=sys.stderr)
                print("READY" if report.ready else "NOT_READY")
            return 0 if report.ready else 2

        if args.command == "publication":
            if args.publication_command == "create":
                receipt = create_publication_receipt(
                    root,
                    input_list=args.input_list,
                    output_list=args.output_list,
                    input_roots=args.input_root,
                    output_roots=args.output_root,
                    receipt_path=args.receipt,
                )
                print(
                    f"{receipt['status']} head={receipt['head']} "
                    f"tree={receipt['tree']} receipt={Path(args.receipt).resolve(strict=False)}"
                )
                return 0
            if args.publication_command == "verify":
                receipt = verify_publication_receipt(root, args.receipt)
                print(
                    f"VERIFIED head={receipt['head']} tree={receipt['tree']} "
                    f"receipt={Path(args.receipt).resolve(strict=False)}"
                )
                return 0
            raise ContractError(
                f"Unsupported publication command: {args.publication_command}"
            )

        if args.command == "lkg":
            if args.last_green_command == "resolve":
                resolved = resolve_last_green(
                    root,
                    candidate_receipt=args.candidate_receipt,
                    run_receipt=args.run_receipt,
                )
                print(
                    f"LKG_RESOLVED ref={resolved['ref']} "
                    f"head={resolved['head']} tree={resolved['tree']}"
                )
                return 0
            if args.last_green_command == "promote":
                promoted = promote_last_green(
                    root,
                    candidate_receipt=args.candidate_receipt,
                    run_receipt=args.run_receipt,
                    expected_old=(
                        None if args.expected_old == "missing" else args.expected_old
                    ),
                )
                print(
                    f"LKG_{promoted['status']} ref={promoted['ref']} "
                    f"head={promoted['head']} tree={promoted['tree']}"
                )
                return 0
            raise ContractError(
                f"Unsupported last-green command: {args.last_green_command}"
            )

        if args.command == "lock-path":
            print(publication_lock_path(root, args.name))
            return 0
        if args.command == "eol-check":
            checked = assert_tracked_lf_eol(root)
            print(f"PASS tracked_eol_lf={checked}")
            return 0
        raise ContractError(f"Unsupported command: {args.command}")
    except (ContractError, OSError) as error:
        print(f"workbench contract error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
