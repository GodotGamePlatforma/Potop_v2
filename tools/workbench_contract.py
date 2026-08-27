#!/usr/bin/env python3
"""Machine-readable ownership checks for concurrent repository work.

The module deliberately separates *file ownership* from the integration role.
An integration agent may compose files owned by several domains, but authoring
agents are accepted only when every declared or detected write belongs to their
single domain.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
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
PUBLICATION_RECEIPT_SCHEMA_VERSION = 1
PUBLICATION_RECEIPT_STATUS = "PUBLICATION_READY"
ISOLATED_EOL_PROOF_SCHEMA_VERSION = 1
ISOLATED_EOL_PROOF_KIND = "isolated-git-eol-proof"
ISOLATED_EOL_PROOF_PURPOSE = "structure-target-build"
ISOLATED_EOL_PROOF_KEY_ENV = "OSTATNI_POMOST_ISOLATED_EOL_PROOF_KEY"
ISOLATED_EOL_PROOF_PATH_ENV = "OSTATNI_POMOST_ISOLATED_EOL_PROOF_PATH"


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


def _isolated_snapshot_file_records(
    snapshot_root: Path,
    paths: Iterable[str],
) -> tuple[tuple[dict[str, object], ...], str, int, int]:
    """Hash an explicit Git-closed path set using the runner's snapshot format."""

    root = snapshot_root.resolve(strict=True)
    if not root.is_dir():
        raise ContractError(f"Snapshot root must be a directory: {root}")
    normalized_paths = tuple(normalize_repo_path(path) for path in paths)
    if tuple(sorted(normalized_paths)) != normalized_paths:
        raise ContractError("Snapshot proof paths must be canonical and ordered.")
    if len(set(normalized_paths)) != len(normalized_paths):
        raise ContractError("Snapshot proof paths contain duplicates.")

    records: list[dict[str, object]] = []
    canonical_records: list[str] = []
    file_count = 0
    missing_count = 0
    for relative_path in normalized_paths:
        candidate = root.joinpath(*PurePosixPath(relative_path).parts)
        if candidate.is_symlink():
            raise ContractError(
                f"Snapshot proof path cannot be a symlink: {relative_path}"
            )
        resolved = candidate.resolve(strict=False)
        if not resolved.is_relative_to(root):
            raise ContractError(f"Snapshot proof path escapes root: {relative_path}")
        path_token = base64.b64encode(relative_path.encode("utf-8")).decode("ascii")
        if not candidate.exists():
            missing_count += 1
            record = {
                "path": relative_path,
                "exists": False,
                "size": 0,
                "sha256": "",
            }
            canonical_records.append(f"M\t{path_token}")
        else:
            if not candidate.is_file():
                raise ContractError(
                    f"Snapshot proof path must be a regular file: {relative_path}"
                )
            raw = candidate.read_bytes()
            file_count += 1
            record = {
                "path": relative_path,
                "exists": True,
                "size": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
            canonical_records.append(
                f"F\t{path_token}\t{len(raw)}\t{record['sha256']}"
            )
        records.append(record)
    digest = hashlib.sha256("\n".join(canonical_records).encode("utf-8")).hexdigest()
    return tuple(records), digest, file_count, missing_count


def _isolated_eol_secret(secret_hex: str | None = None) -> bytes:
    value = secret_hex or os.environ.get(ISOLATED_EOL_PROOF_KEY_ENV, "")
    if re.fullmatch(r"[0-9a-fA-F]{64}", value) is None:
        raise ContractError(
            f"{ISOLATED_EOL_PROOF_KEY_ENV} must contain one ephemeral 256-bit hex key."
        )
    return bytes.fromhex(value)


def _isolated_eol_proof_path(
    snapshot_root: Path,
    proof_path: str | Path,
    *,
    must_exist: bool,
) -> Path:
    root = snapshot_root.resolve(strict=True)
    candidate = Path(proof_path)
    if not candidate.is_absolute():
        candidate = root / candidate
    if candidate.is_symlink():
        raise ContractError("Isolated EOL proof cannot be a symlink.")
    try:
        resolved = candidate.resolve(strict=must_exist)
    except OSError as error:
        raise ContractError(f"Isolated EOL proof does not exist: {candidate}") from error
    allowed_parent = (root / ".godot" / "isolated_eol_proofs").resolve(
        strict=False
    )
    if resolved.parent != allowed_parent or resolved.suffix.lower() != ".json":
        raise ContractError(
            "Isolated EOL proof must be one JSON file directly under "
            "<snapshot>/.godot/isolated_eol_proofs/."
        )
    return resolved


def _assert_non_git_snapshot(snapshot_root: Path) -> None:
    try:
        boundary = _find_git_boundary(snapshot_root)
    except ContractError:
        return
    raise ContractError(
        "Isolated EOL proof is valid only for a non-Git snapshot; "
        f"found Git boundary {boundary}."
    )


def _isolated_eol_canonical_payload(payload: dict[str, object]) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def create_isolated_eol_proof(
    repository: str | Path,
    *,
    snapshot_root: str | Path,
    expected_snapshot_sha256: str,
    structure_id: str,
    proof_path: str | Path,
    secret_hex: str | None = None,
) -> dict[str, object]:
    """Attest one exact non-Git runner snapshot after Git's LF preflight."""

    source_root = repository_root(repository)
    isolated_root = Path(snapshot_root).resolve(strict=True)
    _assert_non_git_snapshot(isolated_root)
    if STRUCTURE_ID_PATTERN.fullmatch(structure_id) is None:
        raise ContractError(f"Invalid structure ID for isolated EOL proof: {structure_id}")
    expected_digest = expected_snapshot_sha256.lower()
    if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
        raise ContractError("Expected isolated snapshot SHA-256 is invalid.")
    secret = _isolated_eol_secret(secret_hex)

    checked_lf_paths = assert_tracked_lf_eol(source_root)
    paths = inventory_paths(source_root)
    source_records, source_digest, source_files, source_missing = (
        _isolated_snapshot_file_records(source_root, paths)
    )
    isolated_records, isolated_digest, isolated_files, isolated_missing = (
        _isolated_snapshot_file_records(isolated_root, paths)
    )
    if source_digest != expected_digest or isolated_digest != expected_digest:
        raise ContractError(
            "Isolated EOL proof source/snapshot digest mismatch: "
            f"expected={expected_digest}, source={source_digest}, "
            f"snapshot={isolated_digest}."
        )
    if source_records != isolated_records:
        raise ContractError("Isolated EOL proof source and snapshot byte records differ.")
    if (source_files, source_missing) != (isolated_files, isolated_missing):
        raise ContractError("Isolated EOL proof source and snapshot counts differ.")

    head = os.fsdecode(_run_git(source_root, "rev-parse", "--verify", "HEAD").stdout).strip().lower()
    tree = os.fsdecode(
        _run_git(source_root, "rev-parse", "--verify", "HEAD^{tree}").stdout
    ).strip().lower()
    status = _run_git(
        source_root,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        "-z",
    ).stdout
    payload: dict[str, object] = {
        "schema_version": ISOLATED_EOL_PROOF_SCHEMA_VERSION,
        "kind": ISOLATED_EOL_PROOF_KIND,
        "purpose": ISOLATED_EOL_PROOF_PURPOSE,
        "structure_id": structure_id,
        "snapshot_root": str(isolated_root),
        "source_head": head,
        "source_tree": tree,
        "source_status_sha256": hashlib.sha256(status).hexdigest(),
        "source_snapshot_sha256": isolated_digest,
        "path_count": len(paths),
        "file_count": isolated_files,
        "missing_count": isolated_missing,
        "tracked_eol_lf_count": checked_lf_paths,
        "nonce": secrets.token_hex(16),
        "files": list(isolated_records),
    }
    signature = hmac.new(
        secret,
        _isolated_eol_canonical_payload(payload),
        hashlib.sha256,
    ).hexdigest()
    receipt = dict(payload)
    receipt["hmac_sha256"] = signature

    destination = _isolated_eol_proof_path(
        isolated_root,
        proof_path,
        must_exist=False,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        with destination.open("xb") as stream:
            stream.write(
                json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2).encode(
                    "utf-8"
                )
            )
            stream.write(b"\n")
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError as error:
        raise ContractError(f"Isolated EOL proof already exists: {destination}") from error
    return receipt


def verify_isolated_eol_proof(
    snapshot_root: str | Path,
    *,
    proof_path: str | Path,
    structure_id: str,
    secret_hex: str | None = None,
) -> dict[str, object]:
    """Verify an ephemeral HMAC proof and rehash every attested snapshot byte."""

    isolated_root = Path(snapshot_root).resolve(strict=True)
    _assert_non_git_snapshot(isolated_root)
    secret = _isolated_eol_secret(secret_hex)
    source = _isolated_eol_proof_path(
        isolated_root,
        proof_path,
        must_exist=True,
    )
    if source.stat().st_size > 16 * 1024 * 1024:
        raise ContractError("Isolated EOL proof exceeds the fail-closed size limit.")
    try:
        receipt = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError(f"Invalid isolated EOL proof JSON: {error}") from error
    if not isinstance(receipt, dict):
        raise ContractError("Isolated EOL proof must be a JSON object.")
    signature = receipt.get("hmac_sha256")
    if not isinstance(signature, str) or re.fullmatch(r"[0-9a-f]{64}", signature) is None:
        raise ContractError("Isolated EOL proof HMAC is missing or invalid.")
    payload = dict(receipt)
    del payload["hmac_sha256"]
    expected_signature = hmac.new(
        secret,
        _isolated_eol_canonical_payload(payload),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(signature, expected_signature):
        raise ContractError("Isolated EOL proof HMAC verification failed.")

    expected_keys = {
        "schema_version",
        "kind",
        "purpose",
        "structure_id",
        "snapshot_root",
        "source_head",
        "source_tree",
        "source_status_sha256",
        "source_snapshot_sha256",
        "path_count",
        "file_count",
        "missing_count",
        "tracked_eol_lf_count",
        "nonce",
        "files",
    }
    if set(payload) != expected_keys:
        raise ContractError("Isolated EOL proof fields do not match the closed schema.")
    if payload["schema_version"] != ISOLATED_EOL_PROOF_SCHEMA_VERSION or payload["kind"] != ISOLATED_EOL_PROOF_KIND:
        raise ContractError("Isolated EOL proof schema or kind is unsupported.")
    if payload["purpose"] != ISOLATED_EOL_PROOF_PURPOSE:
        raise ContractError("Isolated EOL proof purpose is invalid.")
    if payload["structure_id"] != structure_id:
        raise ContractError("Isolated EOL proof belongs to a different structure.")
    if Path(str(payload["snapshot_root"])).resolve(strict=False) != isolated_root:
        raise ContractError("Isolated EOL proof belongs to a different snapshot root.")
    for digest_name in (
        "source_head",
        "source_tree",
        "source_status_sha256",
        "source_snapshot_sha256",
    ):
        pattern = r"[0-9a-f]{40,64}" if digest_name in {"source_head", "source_tree"} else r"[0-9a-f]{64}"
        if not isinstance(payload[digest_name], str) or re.fullmatch(pattern, str(payload[digest_name])) is None:
            raise ContractError(f"Isolated EOL proof has invalid {digest_name}.")
    if not isinstance(payload["nonce"], str) or re.fullmatch(r"[0-9a-f]{32}", str(payload["nonce"])) is None:
        raise ContractError("Isolated EOL proof nonce is invalid.")
    if not isinstance(payload["files"], list):
        raise ContractError("Isolated EOL proof files must be a list.")
    records: list[dict[str, object]] = []
    paths: list[str] = []
    for value in payload["files"]:
        if not isinstance(value, dict) or set(value) != {"path", "exists", "size", "sha256"}:
            raise ContractError("Isolated EOL proof contains an invalid file record.")
        if not isinstance(value["exists"], bool) or not isinstance(value["size"], int):
            raise ContractError("Isolated EOL proof contains invalid file metadata.")
        path = normalize_repo_path(str(value["path"]))
        sha256 = str(value["sha256"])
        if value["exists"]:
            if value["size"] < 0 or re.fullmatch(r"[0-9a-f]{64}", sha256) is None:
                raise ContractError("Isolated EOL proof contains invalid present-file metadata.")
        elif value["size"] != 0 or sha256:
            raise ContractError("Isolated EOL proof contains invalid missing-file metadata.")
        normalized_record = {
            "path": path,
            "exists": value["exists"],
            "size": value["size"],
            "sha256": sha256,
        }
        records.append(normalized_record)
        paths.append(path)
    current_records, current_digest, file_count, missing_count = (
        _isolated_snapshot_file_records(isolated_root, paths)
    )
    if tuple(records) != current_records:
        raise ContractError("Isolated EOL proof snapshot bytes changed after attestation.")
    if payload["source_snapshot_sha256"] != current_digest:
        raise ContractError("Isolated EOL proof snapshot digest does not match current bytes.")
    if payload["path_count"] != len(paths) or payload["file_count"] != file_count or payload["missing_count"] != missing_count:
        raise ContractError("Isolated EOL proof path/file counts do not match current bytes.")
    if not isinstance(payload["tracked_eol_lf_count"], int) or payload["tracked_eol_lf_count"] < 0:
        raise ContractError("Isolated EOL proof tracked LF count is invalid.")
    return receipt


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

    eol_proof = commands.add_parser(
        "eol-proof",
        help="create an ephemeral proof for one exact non-Git runner snapshot",
    )
    eol_proof_commands = eol_proof.add_subparsers(
        dest="eol_proof_command",
        required=True,
    )
    eol_proof_create = eol_proof_commands.add_parser(
        "create",
        help="attest source LF state and an exact copied snapshot",
    )
    eol_proof_create.add_argument("--snapshot-root", required=True)
    eol_proof_create.add_argument("--snapshot-digest", required=True)
    eol_proof_create.add_argument("--structure-id", required=True)
    eol_proof_create.add_argument("--proof", required=True)

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
            paths: set[str] = {normalize_repo_path(path) for path in args.path}
            for write_set_path in args.write_set:
                paths.update(read_write_set(write_set_path))
            if args.diff or args.base:
                paths.update(changed_paths(root, args.base))
            if not paths:
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

        if args.command == "lock-path":
            print(publication_lock_path(root, args.name))
            return 0
        if args.command == "eol-check":
            checked = assert_tracked_lf_eol(root)
            print(f"PASS tracked_eol_lf={checked}")
            return 0
        if args.command == "eol-proof":
            if args.eol_proof_command != "create":
                raise ContractError(
                    f"Unsupported EOL proof command: {args.eol_proof_command}"
                )
            receipt = create_isolated_eol_proof(
                root,
                snapshot_root=args.snapshot_root,
                expected_snapshot_sha256=args.snapshot_digest,
                structure_id=args.structure_id,
                proof_path=args.proof,
            )
            print(
                "PASS isolated_eol_proof "
                f"snapshot={receipt['source_snapshot_sha256']} "
                f"structure={receipt['structure_id']} "
                f"proof={Path(args.proof).resolve(strict=True)}"
            )
            return 0
        raise ContractError(f"Unsupported command: {args.command}")
    except (ContractError, OSError) as error:
        print(f"workbench contract error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
