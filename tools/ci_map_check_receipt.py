#!/usr/bin/env python3
"""Create and verify immutable evidence for the trusted map authority check."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence


SCHEMA = "trusted-map-authority-check-v2"
PLAN_SCHEMA = "godot-test-shard-plan-v1"
EMPTY_STATUS_DIGEST = hashlib.sha256(b"").hexdigest()
REQUIRED_DEPENDENCIES = (
    "tools/workbench_contract.py",
    "tools/workbench_lock.py",
    "underwater_map_workbench/tools/build_underwater_map.py",
)


class MapCheckReceiptError(RuntimeError):
    """Raised when map-check evidence is incomplete, stale, or non-canonical."""


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    try:
        hasher = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    except OSError as exc:
        raise MapCheckReceiptError(f"Cannot hash {path}: {exc}") from exc


def _git(repo: Path, *arguments: str) -> str:
    configured_git = os.environ.get("CI_TRUSTED_GIT")
    raw_git = configured_git or shutil.which("git")
    if not raw_git:
        raise MapCheckReceiptError("Trusted Git executable is unavailable.")
    git_path = Path(raw_git)
    if not git_path.is_absolute() or git_path.is_symlink():
        raise MapCheckReceiptError("Trusted Git executable must be one absolute non-symlink file.")
    resolved_git = git_path.resolve(strict=True)
    if not resolved_git.is_file():
        raise MapCheckReceiptError("Trusted Git executable is not a regular file.")
    process = subprocess.run(
        [str(resolved_git), "-C", str(repo), *arguments],
        text=True,
        encoding="utf-8",
        errors="strict",
        capture_output=True,
        check=False,
    )
    if process.returncode != 0:
        detail = (process.stderr or process.stdout).strip()
        raise MapCheckReceiptError(
            f"Git command failed ({' '.join(arguments)}): {detail}"
        )
    return process.stdout.strip()


def _source_identity(repo: Path) -> tuple[str, str, str]:
    resolved = repo.resolve()
    head = _git(resolved, "rev-parse", "HEAD^{commit}")
    tree = _git(resolved, "rev-parse", "HEAD^{tree}")
    status = _git(resolved, "status", "--porcelain=v1", "--untracked-files=all")
    if head.lower() != head or tree.lower() != tree:
        raise MapCheckReceiptError("Git object IDs must be lowercase.")
    if len(head) not in (40, 64) or len(tree) not in (40, 64):
        raise MapCheckReceiptError("Git HEAD/tree object IDs are malformed.")
    if status:
        raise MapCheckReceiptError("Map-check evidence requires a clean candidate.")
    return head, tree, EMPTY_STATUS_DIGEST


def _read_envelope(path: Path) -> tuple[str, list[str]]:
    try:
        raw = path.read_bytes()
        text = raw.decode("utf-8", errors="strict")
    except (OSError, UnicodeError) as exc:
        raise MapCheckReceiptError(f"Cannot read canonical evidence {path}: {exc}") from exc
    if b"\r" in raw or not text.endswith("\n") or text.endswith("\n\n"):
        raise MapCheckReceiptError(
            f"Canonical evidence must use LF and exactly one final newline: {path}"
        )
    lines = text[:-1].split("\n")
    if len(lines) < 2 or not lines[0].startswith("canonical_sha256="):
        raise MapCheckReceiptError(f"Canonical evidence envelope is missing: {path}")
    digest = lines[0].removeprefix("canonical_sha256=")
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise MapCheckReceiptError(f"Canonical evidence digest is malformed: {path}")
    canonical = "\n".join(lines[1:])
    if _sha256_bytes(canonical.encode("utf-8")) != digest:
        raise MapCheckReceiptError(f"Canonical evidence digest does not match: {path}")
    return digest, lines[1:]


def _unique_records(
    lines: Sequence[str], *, repeatable: frozenset[str] = frozenset()
) -> dict[str, str]:
    records: dict[str, str] = {}
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or not key:
            raise MapCheckReceiptError(f"Malformed canonical evidence record: {line!r}")
        if key in records:
            if key not in repeatable:
                raise MapCheckReceiptError(
                    f"Canonical evidence contains duplicate singleton {key!r}."
                )
            continue
        records[key] = value
    return records


def _plan_binding(plan_path: Path) -> dict[str, str]:
    digest, lines = _read_envelope(plan_path)
    records = _unique_records(lines, repeatable=frozenset(("shard", "target")))
    required = (
        "version",
        "source_head",
        "source_tree",
        "source_worktree_clean",
        "source_status_digest",
        "source_snapshot",
        "runner_sha256",
        "target_count",
    )
    missing = [key for key in required if key not in records]
    if missing:
        raise MapCheckReceiptError(f"Shard plan is missing records: {missing}")
    if records["version"] != PLAN_SCHEMA:
        raise MapCheckReceiptError("Map check requires the canonical full-suite shard plan.")
    if records["source_worktree_clean"] != "1":
        raise MapCheckReceiptError("Shard plan does not bind a clean candidate.")
    if records["source_status_digest"] != EMPTY_STATUS_DIGEST:
        raise MapCheckReceiptError("Shard plan status digest is not the clean digest.")
    for key in ("source_snapshot", "runner_sha256"):
        value = records[key]
        if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
            raise MapCheckReceiptError(f"Shard plan {key} is malformed.")
    if not records["target_count"].isdigit() or int(records["target_count"]) < 1:
        raise MapCheckReceiptError("Shard plan target_count must be positive.")
    return {**records, "canonical_sha256": digest}


def _encode_path(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def _authorization(value: str) -> str:
    if value == "none":
        return value
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise MapCheckReceiptError(
            "Map-check authorization must be 'none' or one lowercase SHA-256."
        )
    return value


def _canonical_body(
    repo: Path,
    plan_path: Path,
    log_path: Path,
    authorization_sha256: str = "none",
) -> str:
    head, tree, status_digest = _source_identity(repo)
    plan = _plan_binding(plan_path)
    authorization = _authorization(authorization_sha256)
    if plan["source_head"] != head or plan["source_tree"] != tree:
        raise MapCheckReceiptError("Shard plan and map-check candidate Git identity differ.")

    dependency_lines: list[str] = []
    for relative_path in sorted(REQUIRED_DEPENDENCIES):
        candidate = repo / Path(relative_path)
        if not candidate.is_file():
            raise MapCheckReceiptError(f"Map-check dependency is missing: {relative_path}")
        dependency_lines.append(
            f"dependency={_encode_path(relative_path)}|{_sha256_file(candidate)}"
        )
    if not log_path.is_file():
        raise MapCheckReceiptError(f"Map-check log is missing: {log_path}")

    lines = [
        f"version={SCHEMA}",
        f"source_head={head}",
        f"source_tree={tree}",
        "source_worktree_clean=1",
        f"source_status_digest={status_digest}",
        f"source_snapshot={plan['source_snapshot']}",
        f"runner_sha256={plan['runner_sha256']}",
        f"plan_sha256={plan['canonical_sha256']}",
        f"plan_target_count={plan['target_count']}",
        f"authorization_sha256={authorization}",
        "command=underwater_map_workbench/tools/build_underwater_map.py --check",
        f"dependency_count={len(dependency_lines)}",
        *dependency_lines,
        f"log_sha256={_sha256_file(log_path)}",
        "result=PASS",
    ]
    return "\n".join(lines)


def _receipt_content(
    repo: Path,
    plan_path: Path,
    log_path: Path,
    authorization_sha256: str = "none",
) -> str:
    body = _canonical_body(
        repo.resolve(),
        plan_path.resolve(),
        log_path.resolve(),
        authorization_sha256,
    )
    return f"canonical_sha256={_sha256_bytes(body.encode('utf-8'))}\n{body}\n"


def create_receipt(
    repo: Path,
    plan_path: Path,
    log_path: Path,
    output: Path,
    authorization_sha256: str = "none",
) -> dict[str, str]:
    content = _receipt_content(repo, plan_path, log_path, authorization_sha256)
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        try:
            existing = output.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise MapCheckReceiptError(f"Cannot read existing receipt {output}: {exc}") from exc
        if existing != content:
            raise MapCheckReceiptError("Existing map-check receipt has different content.")
    else:
        temporary: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                newline="\n",
                dir=output.parent,
                prefix=f".{output.name}.tmp-",
                delete=False,
            ) as handle:
                handle.write(content)
                temporary = Path(handle.name)
            os.replace(temporary, output)
            temporary = None
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return verify_receipt(
        repo,
        plan_path,
        log_path,
        output,
        authorization_sha256,
    )


def verify_receipt(
    repo: Path,
    plan_path: Path,
    log_path: Path,
    receipt: Path,
    authorization_sha256: str = "none",
) -> dict[str, str]:
    try:
        actual = receipt.resolve().read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise MapCheckReceiptError(f"Cannot read map-check receipt {receipt}: {exc}") from exc
    expected = _receipt_content(repo, plan_path, log_path, authorization_sha256)
    if actual != expected:
        raise MapCheckReceiptError("Map-check receipt does not match exact current evidence.")
    digest, lines = _read_envelope(receipt.resolve())
    records = _unique_records(lines, repeatable=frozenset(("dependency",)))
    if records.get("version") != SCHEMA or records.get("result") != "PASS":
        raise MapCheckReceiptError("Map-check receipt is not a terminal PASS.")
    return {
        "schema": SCHEMA,
        "status": "PASS",
        "canonical_sha256": digest,
        "source_head": records["source_head"],
        "source_tree": records["source_tree"],
        "plan_sha256": records["plan_sha256"],
        "authorization_sha256": records["authorization_sha256"],
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "verify"):
        command = subparsers.add_parser(name)
        command.add_argument("--repo", required=True, type=Path)
        command.add_argument("--plan", required=True, type=Path)
        command.add_argument("--log", required=True, type=Path)
        command.add_argument("--receipt", required=True, type=Path)
        command.add_argument("--authorization-sha256", default="none")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        result = (
            create_receipt(
                args.repo,
                args.plan,
                args.log,
                args.receipt,
                args.authorization_sha256,
            )
            if args.command == "create"
            else verify_receipt(
                args.repo,
                args.plan,
                args.log,
                args.receipt,
                args.authorization_sha256,
            )
        )
    except MapCheckReceiptError as exc:
        print(f"MAP CHECK RECEIPT FAILED: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
