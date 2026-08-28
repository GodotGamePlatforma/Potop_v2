#!/usr/bin/env python3
"""Fail closed when an automatic candidate changes CI control-plane files."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Sequence


MAX_CHANGED_PATHS = 3000
FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
NAME_STATUS_RE = re.compile(r"^(?:[ACDMRTUXB]|[RC][0-9]{1,3})$")

PROTECTED_DIRECTORIES = frozenset((".github", ".githooks"))
PROTECTED_EXACT_PATHS = frozenset(
    (
        ".gitattributes",
        ".gitignore",
        ".gitmodules",
        ".lfsconfig",
        "export_presets.cfg",
        "agents.md",
        ".ai/decisions.md",
        "tools/workbench_contract.py",
        "tools/workbench_lock.py",
        "tools/setup_agent_worktree.ps1",
        "tools/agent_fast_check.ps1",
        "tools/publish_agent_pr.ps1",
        "tools/plan_github_ruleset.ps1",
        "tools/sync_play_main.ps1",
        "tools/build_playable_main.ps1",
        "tools/freeze_workbench_revision.py",
        "tools/install_agent_git_hooks.ps1",
        "tests/agent_integration_workflow_test.py",
        "tests/run_all_tests.ps1",
        "tests/runner_isolation_test.ps1",
        "tests/workbench_contract_test.py",
        "tests/workbench_lock_test.py",
        "tests/setup_agent_worktree_test.ps1",
        "tests/agent_fast_check_test.ps1",
        "tests/publish_agent_pr_test.ps1",
        "tests/plan_github_ruleset_test.ps1",
        "tests/sync_play_main_test.ps1",
        "tests/build_playable_main_test.ps1",
        "tests/freeze_workbench_revision_test.py",
        "tests/pre_push_guard_test.ps1",
        "tests/map_atomic_write_test.py",
        "tests/parallel_worktree_godot_test.ps1",
        "underwater_map_workbench/tests/portal_backdrop_clearance_test.py",
        "underwater_map_workbench/tests/underwater_map_smoke_test.gd",
        "underwater_map_workbench/tools/build_underwater_map.py",
    )
)
MAP_MAINTENANCE_EXACT_PATHS = frozenset(
    (
        "underwater_map_workbench/tests/portal_backdrop_clearance_test.py",
        "underwater_map_workbench/tests/underwater_map_smoke_test.gd",
        "underwater_map_workbench/tools/build_underwater_map.py",
    )
)
# A maintenance PR is the verifier-only half of a two-phase trust transition.
# It must not smuggle map source, runtime, authority outputs, or generated data
# alongside the three verifier changes.
MAP_MAINTENANCE_ALLOWED_PATHS = MAP_MAINTENANCE_EXACT_PATHS


class ProtectedPathError(RuntimeError):
    """Raised when path input or a candidate diff cannot be trusted."""


def _git_executable() -> str:
    requested = os.environ.get("CI_TRUSTED_GIT", "")
    if not requested:
        return "git"
    path = Path(requested)
    if not path.is_absolute() or path.is_symlink():
        raise ProtectedPathError("CI_TRUSTED_GIT must name one absolute non-symlink file.")
    resolved = path.resolve(strict=True)
    if not resolved.is_file():
        raise ProtectedPathError("CI_TRUSTED_GIT must name one regular file.")
    return str(resolved)


def normalize_repo_path(path: str | Path) -> str:
    raw = str(path)
    if not raw or raw != raw.strip():
        raise ProtectedPathError(f"Repository path is empty or padded: {path!r}")
    if "\0" in raw or any(ord(character) < 32 or ord(character) == 127 for character in raw):
        raise ProtectedPathError(f"Repository path contains a control character: {path!r}")
    portable = raw.replace("\\", "/")
    if portable.startswith("/") or re.match(r"^[A-Za-z]:", portable):
        raise ProtectedPathError(f"Repository path must be relative: {path!r}")

    components: list[str] = []
    for component in portable.split("/"):
        if component in ("", "."):
            continue
        if component == "..":
            raise ProtectedPathError(f"Repository path cannot traverse parents: {path!r}")
        components.append(component)
    if not components:
        raise ProtectedPathError(f"Repository path is empty after normalization: {path!r}")
    return "/".join(components)


def is_protected_path(path: str | Path) -> bool:
    normalized = normalize_repo_path(path).lower()
    components = normalized.split("/")
    if components[0] in PROTECTED_DIRECTORIES:
        return True
    if normalized in PROTECTED_EXACT_PATHS:
        return True
    if len(components) >= 2 and components[0] == "tools" and components[1].startswith("ci_"):
        return True
    if len(components) >= 2 and components[0] == "tests" and components[1].startswith("ci_"):
        return True
    return False


def _bounded_paths(paths: Iterable[str | Path]) -> tuple[str, ...]:
    normalized: list[str] = []
    for path in paths:
        if len(normalized) >= MAX_CHANGED_PATHS:
            raise ProtectedPathError(
                f"Diff exceeds the {MAX_CHANGED_PATHS}-path admission limit."
            )
        normalized.append(normalize_repo_path(path))
    return tuple(normalized)


def validate_paths(paths: Iterable[str | Path]) -> dict[str, object]:
    normalized = _bounded_paths(paths)
    protected = tuple(sorted({path for path in normalized if is_protected_path(path)}))
    if protected:
        preview = ", ".join(protected[:20])
        if len(protected) > 20:
            preview += f", ... (+{len(protected) - 20} more)"
        raise ProtectedPathError(
            f"Automatic integration cannot change protected control-plane paths: {preview}"
        )
    return {
        "status": "PASS",
        "path_count": len(normalized),
        "protected_path_count": 0,
    }


def _decode_path(raw: bytes) -> str:
    try:
        return raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ProtectedPathError("Git path is not valid UTF-8.") from error


def parse_name_only_z(payload: bytes) -> tuple[str, ...]:
    if not payload:
        return ()
    if not payload.endswith(b"\0"):
        raise ProtectedPathError("NUL path stream is not terminated.")
    fields = payload[:-1].split(b"\0")
    if any(field == b"" for field in fields):
        raise ProtectedPathError("NUL path stream contains an empty path.")
    return _bounded_paths(_decode_path(field) for field in fields)


def parse_name_status_records_z(
    payload: bytes,
) -> tuple[tuple[str, tuple[str, ...]], ...]:
    """Parse exact NUL-framed name-status records without losing status."""
    if not payload:
        return ()
    if not payload.endswith(b"\0"):
        raise ProtectedPathError("NUL name-status stream is not terminated.")
    fields = payload[:-1].split(b"\0")
    records: list[tuple[str, tuple[str, ...]]] = []
    path_total = 0
    offset = 0
    while offset < len(fields):
        try:
            status = fields[offset].decode("ascii", errors="strict")
        except UnicodeDecodeError as error:
            raise ProtectedPathError("Name-status token is not ASCII.") from error
        offset += 1
        if NAME_STATUS_RE.fullmatch(status) is None:
            raise ProtectedPathError(f"Invalid name-status token: {status!r}")
        path_count = 2 if status[0] in {"R", "C"} else 1
        if offset + path_count > len(fields):
            raise ProtectedPathError(
                f"Name-status record {status!r} is missing path fields."
            )
        record_paths: list[str] = []
        for raw_path in fields[offset:offset + path_count]:
            if raw_path == b"":
                raise ProtectedPathError(
                    f"Name-status record {status!r} contains an empty path."
                )
            record_paths.append(normalize_repo_path(_decode_path(raw_path)))
        path_total += len(record_paths)
        if path_total > MAX_CHANGED_PATHS:
            raise ProtectedPathError(
                f"Diff exceeds the {MAX_CHANGED_PATHS}-path admission limit."
            )
        records.append((status, tuple(record_paths)))
        offset += path_count
    return tuple(records)


def parse_name_status_z(payload: bytes) -> tuple[str, ...]:
    """Parse `git diff --name-status -z`, preserving both rename paths."""

    return tuple(
        path
        for _status, paths in parse_name_status_records_z(payload)
        for path in paths
    )


def _git_bytes(repository: Path, *arguments: str) -> bytes:
    try:
        process = subprocess.run(
            [
                _git_executable(),
                "-c",
                f"safe.directory={repository}",
                "-c",
                "core.quotepath=false",
                "-C",
                str(repository),
                *arguments,
            ],
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise ProtectedPathError(f"Cannot execute Git: {error}") from error
    if process.returncode != 0:
        detail = process.stderr.decode("utf-8", errors="replace").strip()
        raise ProtectedPathError(
            f"git {' '.join(arguments)} failed ({process.returncode})"
            + (f": {detail}" if detail else "")
        )
    return process.stdout


def _require_full_sha(value: str, label: str) -> str:
    if FULL_SHA_RE.fullmatch(value) is None:
        raise ProtectedPathError(
            f"{label} must be a full 40-character lowercase commit SHA."
        )
    return value


def _resolve_exact_commit(repository: Path, value: str, label: str) -> str:
    expected = _require_full_sha(value, label)
    payload = _git_bytes(
        repository,
        "rev-parse",
        "--verify",
        f"{expected}^{{commit}}",
    )
    try:
        resolved = payload.decode("ascii", errors="strict").strip()
    except UnicodeDecodeError as error:
        raise ProtectedPathError(f"Git returned a non-ASCII {label}.") from error
    _require_full_sha(resolved, f"Resolved {label}")
    if resolved != expected:
        raise ProtectedPathError(
            f"Resolved {label} {resolved} does not match expected {expected}."
        )
    return resolved


def _repository_root(repository: str | Path) -> Path:
    try:
        root = Path(repository).expanduser().resolve()
    except (OSError, RuntimeError) as error:
        raise ProtectedPathError(
            f"Cannot resolve candidate repository path {repository!r}: {error}"
        ) from error
    if not root.is_dir():
        raise ProtectedPathError(f"Candidate repository is not a directory: {root}")
    payload = _git_bytes(root, "rev-parse", "--show-toplevel")
    try:
        reported = Path(payload.decode("utf-8", errors="strict").strip()).resolve()
    except (UnicodeDecodeError, OSError, RuntimeError) as error:
        raise ProtectedPathError("Cannot resolve candidate repository root.") from error
    if reported != root:
        raise ProtectedPathError(
            f"--repo must name the exact worktree root: {root}; Git reports {reported}."
        )
    return root


def validate_diff(
    repository: str | Path,
    base: str,
    head: str,
) -> dict[str, object]:
    root = _repository_root(repository)
    base_commit = _resolve_exact_commit(root, base, "Base")
    head_commit = _resolve_exact_commit(root, head, "Head")
    payload = _git_bytes(
        root,
        "diff",
        "--name-only",
        "--no-renames",
        "-z",
        base_commit,
        head_commit,
        "--",
    )
    paths = parse_name_only_z(payload)
    return {
        **validate_paths(paths),
        "base": base_commit,
        "head": head_commit,
    }


def validate_map_maintenance_diff(
    repository: str | Path,
    base: str,
    head: str,
) -> dict[str, object]:
    root = _repository_root(repository)
    base_commit = _resolve_exact_commit(root, base, "Base")
    head_commit = _resolve_exact_commit(root, head, "Head")
    payload = _git_bytes(
        root,
        "diff",
        "--name-status",
        "--find-renames",
        "-z",
        base_commit,
        head_commit,
        "--",
    )
    records = parse_name_status_records_z(payload)
    if not records:
        raise ProtectedPathError(
            "Map maintenance requires at least one protected map verifier path."
        )
    paths: list[str] = []
    unauthorized: list[str] = []
    for status, record_paths in records:
        if status != "M" or len(record_paths) != 1:
            rendered = " -> ".join(record_paths)
            raise ProtectedPathError(
                "Map maintenance accepts only exact modified files, not "
                f"status {status!r}: {rendered}"
            )
        path = record_paths[0]
        paths.append(path)
        if path not in MAP_MAINTENANCE_ALLOWED_PATHS:
            unauthorized.append(path)
    if len(set(paths)) != len(paths):
        raise ProtectedPathError("Map maintenance diff contains a duplicate path.")
    if unauthorized:
        raise ProtectedPathError(
            "Map maintenance cannot authorize paths outside its exact verifier-only lane: "
            + ", ".join(unauthorized)
        )
    protected = tuple(sorted(paths))
    return {
        "status": "PASS",
        "path_count": len(paths),
        "protected_path_count": len(protected),
        "protected_paths": protected,
        "base": base_commit,
        "head": head_commit,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Reject automatic integration of CI control-plane changes."
    )
    commands = parser.add_subparsers(dest="command", required=True)

    validate_diff_parser = commands.add_parser("validate-diff")
    validate_diff_parser.add_argument("--repo", required=True)
    validate_diff_parser.add_argument("--base", required=True)
    validate_diff_parser.add_argument("--head", required=True)

    validate_map_parser = commands.add_parser("validate-map-maintenance-diff")
    validate_map_parser.add_argument("--repo", required=True)
    validate_map_parser.add_argument("--base", required=True)
    validate_map_parser.add_argument("--head", required=True)

    validate_status_parser = commands.add_parser(
        "validate-name-status",
        aliases=("validate-name-status-file",),
    )
    validate_status_parser.add_argument("--input", required=True)

    validate_paths_parser = commands.add_parser("validate-paths")
    validate_paths_parser.add_argument("--path", action="append", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        if arguments.command == "validate-diff":
            result = validate_diff(arguments.repo, arguments.base, arguments.head)
        elif arguments.command == "validate-map-maintenance-diff":
            result = validate_map_maintenance_diff(
                arguments.repo,
                arguments.base,
                arguments.head,
            )
        elif arguments.command in {"validate-name-status", "validate-name-status-file"}:
            source = Path(arguments.input).expanduser().resolve()
            try:
                payload = source.read_bytes()
            except OSError as error:
                raise ProtectedPathError(
                    f"Cannot read NUL name-status input {source}: {error}"
                ) from error
            result = validate_paths(parse_name_status_z(payload))
        else:
            result = validate_paths(arguments.path)
    except ProtectedPathError as error:
        print(f"CI PROTECTED PATHS FAILED: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
