#!/usr/bin/env python3
"""Deterministic, fail-closed Git LFS provenance for CI workspaces.

The cache verified by this module is only a transport optimisation.  The
manifest is derived from the exact Git ``HEAD`` and index, cache objects are
rehash-verified, and hydrated worktree paths are verified separately before a
test lane may consume them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence


MANIFEST_SCHEMA = "potop-git-lfs-manifest-v1"
OBJECT_SET_SCHEMA = "potop-git-lfs-object-set-v1"
POINTER_VERSION = b"version https://git-lfs.github.com/spec/v1"
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
MAX_POINTER_BYTES = 1024
MAX_LFS_SIZE = (1 << 63) - 1

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_GIT_OBJECT_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
_POINTER_OID_RE = re.compile(rb"^oid sha256:([0-9a-f]{64})$")
_POINTER_SIZE_RE = re.compile(rb"^size (0|[1-9][0-9]*)$")


class LfsContractError(RuntimeError):
    """Raised when Git or LFS provenance cannot be proven exactly."""


def _canonical_json_bytes(value: object) -> bytes:
    try:
        text = json.dumps(
            value,
            ensure_ascii=True,
            allow_nan=False,
            separators=(",", ":"),
            sort_keys=True,
        )
    except (TypeError, ValueError) as error:
        raise LfsContractError("Value cannot be encoded as canonical JSON.") from error
    return (text + "\n").encode("ascii")


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _run_git(
    repository: Path,
    *arguments: str,
    input_data: bytes | None = None,
    allowed_returncodes: Iterable[int] = (0,),
) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repository}",
            "-c",
            "core.quotepath=false",
            "-C",
            str(repository),
            *arguments,
        ],
        input=input_data,
        check=False,
        capture_output=True,
    )
    allowed = set(allowed_returncodes)
    if result.returncode not in allowed:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail}" if detail else ""
        raise LfsContractError(
            f"git {' '.join(arguments)} failed ({result.returncode}){suffix}"
        )
    return result


def repository_root(repository: str | Path = ".") -> Path:
    candidate = Path(repository).expanduser().resolve()
    result = _run_git(candidate, "rev-parse", "--show-toplevel")
    raw = result.stdout.rstrip(b"\r\n")
    if not raw:
        raise LfsContractError("Git returned an empty repository root.")
    try:
        root = Path(os.fsdecode(raw)).resolve()
    except (OSError, UnicodeError) as error:
        raise LfsContractError("Git returned an invalid repository root.") from error
    return root


def _decode_repo_path(raw_path: bytes) -> str:
    try:
        path = raw_path.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise LfsContractError(
            "Git LFS CI requires repository paths encoded as UTF-8."
        ) from error
    if not path or "\x00" in path or "\\" in path:
        raise LfsContractError("Git returned an invalid repository-relative path.")
    pure = PurePosixPath(path)
    if (
        pure.is_absolute()
        or pure.as_posix() != path
        or any(part in {"", ".", ".."} for part in pure.parts)
        or (pure.parts and re.match(r"^[A-Za-z]:", pure.parts[0]))
    ):
        raise LfsContractError(f"Unsafe repository-relative path: {path!r}")
    return path


def _path_sort_key(path: str) -> bytes:
    return path.encode("utf-8", errors="strict")


def _decode_ascii_line(payload: bytes, description: str) -> str:
    try:
        value = payload.decode("ascii", errors="strict").strip()
    except UnicodeDecodeError as error:
        raise LfsContractError(f"Git returned non-ASCII {description}.") from error
    return value


def _index_entries(repository: Path) -> dict[str, tuple[str, str]]:
    payload = _run_git(repository, "ls-files", "--stage", "-z").stdout
    entries: dict[str, tuple[str, str]] = {}
    for record in payload.split(b"\0"):
        if not record:
            continue
        try:
            metadata, raw_path = record.split(b"\t", 1)
            mode_raw, object_raw, stage = metadata.split(b" ")
        except ValueError as error:
            raise LfsContractError("Git returned malformed index metadata.") from error
        path = _decode_repo_path(raw_path)
        mode = _decode_ascii_line(mode_raw, "index mode")
        object_id = _decode_ascii_line(object_raw, "index object ID")
        if stage != b"0" or path in entries:
            raise LfsContractError(f"Index has unresolved or duplicate path: {path}")
        if not _GIT_OBJECT_RE.fullmatch(object_id):
            raise LfsContractError(f"Invalid Git index object ID for {path}.")
        entries[path] = (mode, object_id)
    return entries


def _head_tree_entries(repository: Path) -> dict[str, tuple[str, str, str]]:
    payload = _run_git(
        repository,
        "ls-tree",
        "-r",
        "-z",
        "--full-tree",
        "HEAD",
    ).stdout
    entries: dict[str, tuple[str, str, str]] = {}
    for record in payload.split(b"\0"):
        if not record:
            continue
        try:
            metadata, raw_path = record.split(b"\t", 1)
            mode_raw, type_raw, object_raw = metadata.split(b" ")
        except ValueError as error:
            raise LfsContractError("Git returned malformed HEAD tree metadata.") from error
        path = _decode_repo_path(raw_path)
        mode = _decode_ascii_line(mode_raw, "HEAD mode")
        object_type = _decode_ascii_line(type_raw, "HEAD object type")
        object_id = _decode_ascii_line(object_raw, "HEAD object ID")
        if path in entries or not _GIT_OBJECT_RE.fullmatch(object_id):
            raise LfsContractError(f"Invalid or duplicate HEAD tree path: {path}")
        entries[path] = (mode, object_type, object_id)
    return entries


def _exact_head_state(
    repository: Path,
) -> tuple[str, str, dict[str, tuple[str, str, str]]]:
    head = _decode_ascii_line(
        _run_git(repository, "rev-parse", "--verify", "HEAD^{commit}").stdout,
        "HEAD commit",
    )
    tree = _decode_ascii_line(
        _run_git(repository, "rev-parse", "--verify", "HEAD^{tree}").stdout,
        "HEAD tree",
    )
    if not _GIT_OBJECT_RE.fullmatch(head) or not _GIT_OBJECT_RE.fullmatch(tree):
        raise LfsContractError("Git returned an unsupported HEAD or tree object ID.")

    index = _index_entries(repository)
    head_entries = _head_tree_entries(repository)
    index_projection = {path: value for path, value in index.items()}
    head_projection = {
        path: (mode, object_id)
        for path, (mode, _object_type, object_id) in head_entries.items()
    }
    if index_projection != head_projection:
        changed = sorted(
            set(index_projection).symmetric_difference(head_projection)
            | {
                path
                for path in set(index_projection).intersection(head_projection)
                if index_projection[path] != head_projection[path]
            },
            key=_path_sort_key,
        )
        preview = ", ".join(changed[:20])
        if len(changed) > 20:
            preview += f", ... (+{len(changed) - 20})"
        raise LfsContractError(
            "Git index must match exact HEAD before creating or verifying an LFS "
            f"manifest; differing paths: {preview or '<unknown>'}"
        )
    return head, tree, head_entries


def _cached_filter_attributes(
    repository: Path,
    paths: Sequence[str],
) -> dict[str, str]:
    if not paths:
        return {}
    standard_input = b"".join(path.encode("utf-8") + b"\0" for path in paths)
    payload = _run_git(
        repository,
        "check-attr",
        "--cached",
        "-z",
        "--stdin",
        "filter",
        input_data=standard_input,
    ).stdout
    fields = payload.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    if len(fields) % 3:
        raise LfsContractError("Git returned malformed check-attr output.")

    expected = set(paths)
    attributes: dict[str, str] = {}
    for offset in range(0, len(fields), 3):
        path = _decode_repo_path(fields[offset])
        attribute = _decode_ascii_line(fields[offset + 1], "attribute name")
        value = _decode_ascii_line(fields[offset + 2], "attribute value")
        if path not in expected or attribute != "filter" or path in attributes:
            raise LfsContractError("Git returned unexpected check-attr output.")
        attributes[path] = value
    if set(attributes) != expected:
        raise LfsContractError("Git check-attr output is incomplete.")
    return attributes


def _read_git_blobs(repository: Path, object_ids: Iterable[str]) -> dict[str, bytes]:
    requested = sorted(set(object_ids))
    if not requested:
        return {}
    for object_id in requested:
        if not _GIT_OBJECT_RE.fullmatch(object_id):
            raise LfsContractError(f"Invalid Git blob object ID: {object_id!r}")

    metadata_payload = _run_git(
        repository,
        "cat-file",
        "--batch-check=%(objectname) %(objecttype) %(objectsize)",
        input_data=b"".join(object_id.encode("ascii") + b"\n" for object_id in requested),
    ).stdout
    metadata_lines = metadata_payload.splitlines()
    if len(metadata_lines) != len(requested):
        raise LfsContractError("Git cat-file returned incomplete blob metadata.")
    for requested_id, metadata in zip(requested, metadata_lines):
        try:
            returned_raw, object_type, size_raw = metadata.split(b" ")
            returned_id = returned_raw.decode("ascii", errors="strict")
            size = int(size_raw.decode("ascii", errors="strict"), 10)
        except (UnicodeDecodeError, ValueError) as error:
            raise LfsContractError("Git cat-file returned malformed blob metadata.") from error
        if returned_id != requested_id or object_type != b"blob" or size < 0:
            raise LfsContractError(f"Git object is not the requested blob: {requested_id}")
        if size >= MAX_POINTER_BYTES:
            raise LfsContractError(
                f"Git blob exceeds the Git LFS pointer size limit: {requested_id}"
            )

    payload = _run_git(
        repository,
        "cat-file",
        "--batch",
        input_data=b"".join(object_id.encode("ascii") + b"\n" for object_id in requested),
    ).stdout

    cursor = 0
    blobs: dict[str, bytes] = {}
    for requested_id in requested:
        header_end = payload.find(b"\n", cursor)
        if header_end < 0:
            raise LfsContractError("Git cat-file returned a truncated header.")
        header = payload[cursor:header_end]
        cursor = header_end + 1
        try:
            returned_raw, object_type, size_raw = header.split(b" ")
            returned_id = returned_raw.decode("ascii", errors="strict")
            size = int(size_raw.decode("ascii", errors="strict"), 10)
        except (UnicodeDecodeError, ValueError) as error:
            raise LfsContractError("Git cat-file returned malformed metadata.") from error
        if returned_id != requested_id or object_type != b"blob" or size < 0:
            raise LfsContractError(f"Git object is not the requested blob: {requested_id}")
        end = cursor + size
        if end >= len(payload) or payload[end : end + 1] != b"\n":
            raise LfsContractError("Git cat-file returned truncated blob data.")
        blobs[requested_id] = payload[cursor:end]
        cursor = end + 1
    if cursor != len(payload):
        raise LfsContractError("Git cat-file returned unexpected trailing data.")
    return blobs


def _parse_pointer(pointer: bytes, path: str) -> tuple[str, int]:
    if len(pointer) >= MAX_POINTER_BYTES:
        raise LfsContractError(f"Git LFS pointer exceeds the size limit: {path}")
    if not pointer.endswith(b"\n") or b"\r" in pointer or b"\0" in pointer:
        raise LfsContractError(f"Non-canonical Git LFS pointer bytes: {path}")
    lines = pointer[:-1].split(b"\n")
    if not lines or lines[0] != POINTER_VERSION:
        raise LfsContractError(f"Tracked filter=lfs path is not an LFS v1 pointer: {path}")
    if any(line.startswith(b"ext-") for line in lines[1:]):
        # Extension pointers hash the transformed cache payload, not necessarily
        # the final hydrated worktree bytes.  Without an original-size field we
        # cannot prove both worktree SHA and size, so refuse a false PASS.
        raise LfsContractError(
            f"Git LFS pointer extensions are not supported by worktree verification: {path}"
        )
    if len(lines) != 3:
        raise LfsContractError(f"Malformed Git LFS pointer field count: {path}")
    oid_match = _POINTER_OID_RE.fullmatch(lines[1])
    size_match = _POINTER_SIZE_RE.fullmatch(lines[2])
    if oid_match is None or size_match is None:
        raise LfsContractError(f"Malformed Git LFS oid or size: {path}")
    oid = oid_match.group(1).decode("ascii")
    size = int(size_match.group(1).decode("ascii"), 10)
    if size > MAX_LFS_SIZE:
        raise LfsContractError(f"Git LFS object size exceeds supported range: {path}")
    return oid, size


def _object_set_digest(objects: Sequence[Mapping[str, object]]) -> str:
    return _sha256_bytes(
        _canonical_json_bytes(
            {
                "schema": OBJECT_SET_SCHEMA,
                "objects": list(objects),
            }
        )
    )


def _seal_manifest(body: Mapping[str, object]) -> dict[str, object]:
    sealed = dict(body)
    sealed["manifest_digest"] = _sha256_bytes(_canonical_json_bytes(body))
    return sealed


def build_manifest(repository: str | Path = ".") -> dict[str, object]:
    """Build a deterministic LFS manifest from exact ``HEAD`` and its index."""

    root = repository_root(repository)
    head, tree, head_entries = _exact_head_state(root)
    paths = sorted(head_entries, key=_path_sort_key)
    filters = _cached_filter_attributes(root, paths)
    lfs_paths = [path for path in paths if filters[path] == "lfs"]

    pointer_blobs: dict[str, str] = {}
    for path in lfs_paths:
        mode, object_type, object_id = head_entries[path]
        if not mode.startswith("100") or object_type != "blob":
            raise LfsContractError(f"filter=lfs path is not a regular Git blob: {path}")
        pointer_blobs[path] = object_id
    blob_payloads = _read_git_blobs(root, pointer_blobs.values())

    entries: list[dict[str, object]] = []
    unique_objects: dict[str, int] = {}
    for path in lfs_paths:
        pointer_blob = pointer_blobs[path]
        oid, size = _parse_pointer(blob_payloads[pointer_blob], path)
        previous_size = unique_objects.setdefault(oid, size)
        if previous_size != size:
            raise LfsContractError(
                f"Git LFS oid {oid} has conflicting sizes: {previous_size} and {size}"
            )
        entries.append(
            {
                "path": path,
                "oid_sha256": oid,
                "size": size,
                "pointer_blob": pointer_blob,
            }
        )

    objects: list[dict[str, object]] = [
        {"oid_sha256": oid, "size": unique_objects[oid]}
        for oid in sorted(unique_objects)
    ]
    body: dict[str, object] = {
        "schema": MANIFEST_SCHEMA,
        "git": {"head": head, "tree": tree},
        "paths": entries,
        "objects": objects,
        "path_count": len(entries),
        "object_count": len(objects),
        "total_object_bytes": sum(int(item["size"]) for item in objects),
        "object_set_digest": _object_set_digest(objects),
    }
    return _seal_manifest(body)


def _require_exact_keys(
    value: Mapping[str, object],
    expected: set[str],
    description: str,
) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        details: list[str] = []
        if missing:
            details.append("missing=" + ",".join(missing))
        if unexpected:
            details.append("unexpected=" + ",".join(unexpected))
        raise LfsContractError(f"Invalid {description} fields: {'; '.join(details)}")


def _require_int(value: object, description: str, *, maximum: int = MAX_LFS_SIZE) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0 or value > maximum:
        raise LfsContractError(f"Invalid non-negative integer for {description}.")
    return value


def validate_manifest(payload: object) -> dict[str, object]:
    """Validate all structure and self-digests of an untrusted manifest."""

    if not isinstance(payload, dict):
        raise LfsContractError("Git LFS manifest root must be an object.")
    _require_exact_keys(
        payload,
        {
            "schema",
            "git",
            "paths",
            "objects",
            "path_count",
            "object_count",
            "total_object_bytes",
            "object_set_digest",
            "manifest_digest",
        },
        "manifest",
    )
    if payload["schema"] != MANIFEST_SCHEMA:
        raise LfsContractError("Unsupported Git LFS manifest schema.")

    git_state = payload["git"]
    if not isinstance(git_state, dict):
        raise LfsContractError("Manifest git state must be an object.")
    _require_exact_keys(git_state, {"head", "tree"}, "manifest git state")
    for name in ("head", "tree"):
        value = git_state[name]
        if not isinstance(value, str) or not _GIT_OBJECT_RE.fullmatch(value):
            raise LfsContractError(f"Invalid manifest Git {name} object ID.")

    raw_paths = payload["paths"]
    if not isinstance(raw_paths, list):
        raise LfsContractError("Manifest paths must be an array.")
    paths: list[dict[str, object]] = []
    seen_paths: set[str] = set()
    derived_objects: dict[str, int] = {}
    for raw_entry in raw_paths:
        if not isinstance(raw_entry, dict):
            raise LfsContractError("Manifest path entry must be an object.")
        _require_exact_keys(
            raw_entry,
            {"path", "oid_sha256", "size", "pointer_blob"},
            "manifest path entry",
        )
        path_value = raw_entry["path"]
        if not isinstance(path_value, str):
            raise LfsContractError("Manifest path must be a string.")
        try:
            raw_path = path_value.encode("utf-8", errors="strict")
        except UnicodeEncodeError as error:
            raise LfsContractError("Manifest path is not valid UTF-8.") from error
        path = _decode_repo_path(raw_path)
        oid = raw_entry["oid_sha256"]
        pointer_blob = raw_entry["pointer_blob"]
        if not isinstance(oid, str) or not _SHA256_RE.fullmatch(oid):
            raise LfsContractError(f"Invalid Git LFS oid for path: {path}")
        if not isinstance(pointer_blob, str) or not _GIT_OBJECT_RE.fullmatch(pointer_blob):
            raise LfsContractError(f"Invalid pointer blob ID for path: {path}")
        size = _require_int(raw_entry["size"], f"size of {path}")
        if path in seen_paths:
            raise LfsContractError(f"Duplicate manifest path: {path}")
        seen_paths.add(path)
        previous = derived_objects.setdefault(oid, size)
        if previous != size:
            raise LfsContractError(f"Conflicting sizes for Git LFS oid: {oid}")
        paths.append(
            {
                "path": path,
                "oid_sha256": oid,
                "size": size,
                "pointer_blob": pointer_blob,
            }
        )
    if paths != sorted(paths, key=lambda item: _path_sort_key(str(item["path"]))):
        raise LfsContractError("Manifest paths are not in canonical order.")

    raw_objects = payload["objects"]
    if not isinstance(raw_objects, list):
        raise LfsContractError("Manifest objects must be an array.")
    objects: list[dict[str, object]] = []
    seen_objects: set[str] = set()
    for raw_object in raw_objects:
        if not isinstance(raw_object, dict):
            raise LfsContractError("Manifest object entry must be an object.")
        _require_exact_keys(raw_object, {"oid_sha256", "size"}, "manifest object")
        oid = raw_object["oid_sha256"]
        if not isinstance(oid, str) or not _SHA256_RE.fullmatch(oid):
            raise LfsContractError("Invalid Git LFS object oid.")
        size = _require_int(raw_object["size"], f"size of object {oid}")
        if oid in seen_objects:
            raise LfsContractError(f"Duplicate Git LFS object oid: {oid}")
        seen_objects.add(oid)
        objects.append({"oid_sha256": oid, "size": size})
    if objects != sorted(objects, key=lambda item: str(item["oid_sha256"])):
        raise LfsContractError("Manifest objects are not in canonical order.")
    expected_objects = [
        {"oid_sha256": oid, "size": derived_objects[oid]}
        for oid in sorted(derived_objects)
    ]
    if objects != expected_objects:
        raise LfsContractError("Manifest object set does not match its path entries.")

    if _require_int(payload["path_count"], "path_count") != len(paths):
        raise LfsContractError("Manifest path_count is inconsistent.")
    if _require_int(payload["object_count"], "object_count") != len(objects):
        raise LfsContractError("Manifest object_count is inconsistent.")
    total_bytes = sum(int(item["size"]) for item in objects)
    if _require_int(
        payload["total_object_bytes"],
        "total_object_bytes",
        maximum=MAX_LFS_SIZE * max(1, len(objects)),
    ) != total_bytes:
        raise LfsContractError("Manifest total_object_bytes is inconsistent.")

    object_set_digest = payload["object_set_digest"]
    if (
        not isinstance(object_set_digest, str)
        or not _SHA256_RE.fullmatch(object_set_digest)
        or object_set_digest != _object_set_digest(objects)
    ):
        raise LfsContractError("Manifest object_set_digest is invalid.")
    manifest_digest = payload["manifest_digest"]
    if not isinstance(manifest_digest, str) or not _SHA256_RE.fullmatch(manifest_digest):
        raise LfsContractError("Manifest manifest_digest is invalid.")
    body = dict(payload)
    del body["manifest_digest"]
    if manifest_digest != _sha256_bytes(_canonical_json_bytes(body)):
        raise LfsContractError("Manifest digest does not match its contents.")

    # Rebuild to return only validated primitive values and canonical ordering.
    return {
        "schema": MANIFEST_SCHEMA,
        "git": {"head": git_state["head"], "tree": git_state["tree"]},
        "paths": paths,
        "objects": objects,
        "path_count": len(paths),
        "object_count": len(objects),
        "total_object_bytes": total_bytes,
        "object_set_digest": object_set_digest,
        "manifest_digest": manifest_digest,
    }


def _reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise LfsContractError(f"Duplicate JSON key in Git LFS manifest: {key}")
        result[key] = value
    return result


def load_manifest(path: str | Path) -> dict[str, object]:
    manifest_path = Path(path)
    try:
        size = manifest_path.stat().st_size
    except OSError as error:
        raise LfsContractError(f"Cannot stat Git LFS manifest: {manifest_path}") from error
    if size > MAX_MANIFEST_BYTES:
        raise LfsContractError("Git LFS manifest exceeds the size limit.")
    try:
        raw = manifest_path.read_bytes()
        payload = json.loads(raw, object_pairs_hook=_reject_duplicate_json_keys)
    except LfsContractError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LfsContractError(f"Cannot read Git LFS manifest: {manifest_path}") from error
    return validate_manifest(payload)


def write_manifest(path: str | Path, manifest: Mapping[str, object]) -> None:
    validated = validate_manifest(dict(manifest))
    destination = Path(path).expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = _canonical_json_bytes(validated)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.",
        suffix=".tmp",
        dir=str(destination.parent),
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    except BaseException:
        try:
            temporary.unlink(missing_ok=True)
        finally:
            raise


def _assert_repository_manifest(
    repository: Path,
    manifest: Mapping[str, object],
) -> dict[str, object]:
    validated = validate_manifest(dict(manifest))
    current = build_manifest(repository)
    if current != validated:
        expected_git = validated["git"]
        actual_git = current["git"]
        raise LfsContractError(
            "Git LFS manifest does not describe the exact checked-out HEAD/tree; "
            f"expected {expected_git}, actual {actual_git}."
        )
    return validated


def default_object_store(repository: str | Path = ".") -> Path:
    """Return the shared LFS object store, including for linked worktrees."""

    root = repository_root(repository)
    common_raw = _run_git(
        root,
        "rev-parse",
        "--path-format=absolute",
        "--git-common-dir",
    ).stdout.rstrip(b"\r\n")
    if not common_raw:
        raise LfsContractError("Git returned an empty common directory.")
    common = Path(os.fsdecode(common_raw)).resolve()
    configured = _run_git(
        root,
        "config",
        "--path",
        "--get",
        "lfs.storage",
        allowed_returncodes=(0, 1),
    )
    if configured.returncode == 0:
        storage_raw = configured.stdout.rstrip(b"\r\n")
        if not storage_raw:
            raise LfsContractError("Git lfs.storage is configured but empty.")
        storage = Path(os.fsdecode(storage_raw)).expanduser()
        if not storage.is_absolute():
            storage = common / storage
        return (storage.resolve() / "objects").resolve()
    return (common / "lfs" / "objects").resolve()


def _is_link_or_reparse(path: Path) -> bool:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise LfsContractError(f"Cannot inspect path metadata: {path}") from error
    if stat.S_ISLNK(metadata.st_mode):
        return True
    attributes = getattr(metadata, "st_file_attributes", 0)
    reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    return bool(attributes & reparse_flag)


def _safe_child(root: Path, relative: PurePosixPath) -> Path:
    root_resolved = root.resolve()
    child = root.joinpath(*relative.parts)
    try:
        resolved = child.resolve(strict=False)
        resolved.relative_to(root_resolved)
    except (OSError, ValueError) as error:
        raise LfsContractError(f"Path escapes its trusted root: {relative.as_posix()}") from error
    return child


def _verify_regular_file(path: Path, description: str) -> None:
    if not path.exists() or not path.is_file():
        raise LfsContractError(f"Missing regular file for {description}: {path}")
    if _is_link_or_reparse(path):
        raise LfsContractError(f"Links/reparse points are forbidden for {description}: {path}")


def _verify_file_payload(path: Path, oid: str, size: int, description: str) -> None:
    _verify_regular_file(path, description)
    try:
        actual_size = path.stat().st_size
    except OSError as error:
        raise LfsContractError(f"Cannot stat {description}: {path}") from error
    if actual_size != size:
        raise LfsContractError(
            f"Size mismatch for {description}: expected {size}, got {actual_size}: {path}"
        )
    try:
        actual_oid = _sha256_file(path)
    except OSError as error:
        raise LfsContractError(f"Cannot hash {description}: {path}") from error
    if actual_oid != oid:
        raise LfsContractError(
            f"SHA-256 mismatch for {description}: expected {oid}, got {actual_oid}: {path}"
        )


def verify_object_store(
    manifest: Mapping[str, object],
    object_store: str | Path,
    *,
    reject_extra: bool = False,
) -> dict[str, object]:
    """Rehash every expected cache object and optionally reject every extra file."""

    validated = validate_manifest(dict(manifest))
    store = Path(object_store).expanduser().resolve()
    if not store.exists() or not store.is_dir() or _is_link_or_reparse(store):
        raise LfsContractError(f"Git LFS object store is not a regular directory: {store}")

    expected_relative: set[str] = set()
    for item in validated["objects"]:  # type: ignore[index]
        if not isinstance(item, dict):  # Defensive after type erasure.
            raise LfsContractError("Validated manifest object is malformed.")
        oid = str(item["oid_sha256"])
        size = int(item["size"])
        relative = PurePosixPath(oid[:2], oid[2:4], oid)
        expected_relative.add(relative.as_posix())
        target = _safe_child(store, relative)
        _verify_file_payload(target, oid, size, f"cached Git LFS object {oid}")

    if reject_extra:
        actual_files: set[str] = set()

        def fail_walk(error: OSError) -> None:
            raise LfsContractError(
                f"Cannot traverse Git LFS object store: {error.filename or store}"
            ) from error

        for current_root, directory_names, file_names in os.walk(
            store,
            followlinks=False,
            onerror=fail_walk,
        ):
            current = Path(current_root)
            for name in list(directory_names):
                directory = current / name
                if _is_link_or_reparse(directory):
                    raise LfsContractError(
                        f"Unexpected link/reparse directory in Git LFS cache: {directory}"
                    )
            for name in file_names:
                file_path = current / name
                if _is_link_or_reparse(file_path):
                    raise LfsContractError(
                        f"Unexpected link/reparse file in Git LFS cache: {file_path}"
                    )
                try:
                    relative = file_path.relative_to(store).as_posix()
                except ValueError as error:
                    raise LfsContractError("Cache traversal escaped the object store.") from error
                actual_files.add(relative)
        unexpected = sorted(actual_files - expected_relative)
        missing = sorted(expected_relative - actual_files)
        if missing or unexpected:
            details: list[str] = []
            if missing:
                details.append("missing=" + ", ".join(missing[:20]))
            if unexpected:
                details.append("unexpected=" + ", ".join(unexpected[:20]))
            raise LfsContractError("Git LFS cache is not exact: " + "; ".join(details))

    return {
        "object_count": validated["object_count"],
        "total_object_bytes": validated["total_object_bytes"],
        "object_set_digest": validated["object_set_digest"],
        "object_store": str(store),
        "reject_extra": reject_extra,
    }


def verify_worktree(
    repository: str | Path,
    manifest: Mapping[str, object],
) -> dict[str, object]:
    """Verify hydrated LFS paths in the exact checkout described by manifest."""

    root = repository_root(repository)
    validated = _assert_repository_manifest(root, manifest)
    for item in validated["paths"]:  # type: ignore[index]
        if not isinstance(item, dict):
            raise LfsContractError("Validated manifest path is malformed.")
        path = str(item["path"])
        target = _safe_child(root, PurePosixPath(path))
        _verify_file_payload(
            target,
            str(item["oid_sha256"]),
            int(item["size"]),
            f"hydrated Git LFS path {path}",
        )
    return {
        "head": validated["git"]["head"],  # type: ignore[index]
        "tree": validated["git"]["tree"],  # type: ignore[index]
        "path_count": validated["path_count"],
        "total_path_bytes": sum(
            int(item["size"])
            for item in validated["paths"]  # type: ignore[index]
        ),
        "object_set_digest": validated["object_set_digest"],
    }


def _summary(manifest: Mapping[str, object]) -> dict[str, object]:
    return {
        "head": manifest["git"]["head"],  # type: ignore[index]
        "tree": manifest["git"]["tree"],  # type: ignore[index]
        "path_count": manifest["path_count"],
        "object_count": manifest["object_count"],
        "total_object_bytes": manifest["total_object_bytes"],
        "object_set_digest": manifest["object_set_digest"],
        "manifest_digest": manifest["manifest_digest"],
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create and verify exact Git LFS provenance for CI.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    manifest_parser = subparsers.add_parser(
        "manifest",
        help="Create a deterministic manifest from exact HEAD/tree.",
    )
    manifest_parser.add_argument("--repo", default=".")
    manifest_parser.add_argument("--output", required=True)

    cache_parser = subparsers.add_parser(
        "verify-cache",
        help="Verify every cached object by SHA-256 and size.",
    )
    cache_parser.add_argument("--repo", default=".")
    cache_parser.add_argument("--manifest", required=True)
    cache_parser.add_argument("--object-store")
    cache_parser.add_argument("--reject-extra", action="store_true")

    worktree_parser = subparsers.add_parser(
        "verify-worktree",
        help="Verify hydrated LFS paths in the exact checkout.",
    )
    worktree_parser.add_argument("--repo", default=".")
    worktree_parser.add_argument("--manifest", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        if arguments.command == "manifest":
            manifest = build_manifest(arguments.repo)
            write_manifest(arguments.output, manifest)
            output = {
                "status": "PASS",
                "operation": "manifest",
                "manifest": str(Path(arguments.output).expanduser().resolve()),
                **_summary(manifest),
            }
        elif arguments.command == "verify-cache":
            root = repository_root(arguments.repo)
            manifest = load_manifest(arguments.manifest)
            manifest = _assert_repository_manifest(root, manifest)
            store = (
                Path(arguments.object_store).expanduser().resolve()
                if arguments.object_store
                else default_object_store(root)
            )
            verification = verify_object_store(
                manifest,
                store,
                reject_extra=arguments.reject_extra,
            )
            output = {
                "status": "PASS",
                "operation": "verify-cache",
                **_summary(manifest),
                **verification,
            }
        elif arguments.command == "verify-worktree":
            manifest = load_manifest(arguments.manifest)
            verification = verify_worktree(arguments.repo, manifest)
            output = {
                "status": "PASS",
                "operation": "verify-worktree",
                **_summary(manifest),
                **verification,
            }
        else:  # pragma: no cover - argparse enforces the closed command set.
            raise LfsContractError(f"Unsupported command: {arguments.command}")
    except (LfsContractError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    print(json.dumps(output, ensure_ascii=True, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
