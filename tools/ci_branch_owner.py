#!/usr/bin/env python3
"""Resolve a Codex branch owner and validate its complete committed diff.

The fast branch workflow may use the local feedback mode.  Trusted admission
supplies an expected head, expected base and a contract tool from the protected
checkout; supplying only part of that tuple is always an error.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence


BRANCH_RE = re.compile(
    r"^codex/(?P<token>root|map|diver|integration|structure-(?P<structure>[a-z0-9][a-z0-9_-]*))"
    r"/(?P<slug>[a-z0-9][a-z0-9._-]*)$"
)
GIT_OBJECT_RE = re.compile(r"^[0-9a-f]{40}$")


class BranchOwnerError(RuntimeError):
    """Raised when branch ownership or its baseline cannot be proven."""


def resolve_owner(branch: str) -> str:
    match = BRANCH_RE.fullmatch(branch)
    if match is None:
        raise BranchOwnerError(
            "Branch must be codex/<root|map|diver|integration|structure-ID>/<task-slug>."
        )
    token = match.group("token")
    structure = match.group("structure")
    if structure is not None:
        return f"structure:{structure}"
    return token


def _git(repository: Path, *arguments: str) -> str:
    try:
        process = subprocess.run(
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
    except OSError as error:
        raise BranchOwnerError(f"Cannot execute Git: {error}") from error
    if process.returncode != 0:
        detail = process.stderr.strip()
        raise BranchOwnerError(
            f"git {' '.join(arguments)} failed ({process.returncode})"
            + (f": {detail}" if detail else "")
        )
    return process.stdout.strip()


def _require_full_sha(value: str, label: str) -> str:
    if GIT_OBJECT_RE.fullmatch(value) is None:
        raise BranchOwnerError(
            f"{label} must be a full 40-character lowercase commit SHA."
        )
    return value


def _trusted_arguments(
    expected_head: str | None,
    expected_base: str | None,
    contract_tool: str | Path | None,
) -> tuple[str, str, str | Path] | None:
    supplied = tuple(
        value is not None
        for value in (expected_head, expected_base, contract_tool)
    )
    if not any(supplied):
        return None
    if not all(supplied):
        raise BranchOwnerError(
            "Trusted validation requires --expected-head, --expected-base "
            "and --contract-tool together."
        )
    assert expected_head is not None
    assert expected_base is not None
    assert contract_tool is not None
    return (
        _require_full_sha(expected_head, "Expected head"),
        _require_full_sha(expected_base, "Expected base"),
        contract_tool,
    )


def resolve_validation_state(
    repository: str | Path,
    branch: str,
    base_ref: str,
    expected_head: str | None = None,
    expected_base: str | None = None,
) -> dict[str, str]:
    root = Path(repository).expanduser().resolve()
    owner = resolve_owner(branch)
    if expected_head is not None:
        expected_head = _require_full_sha(expected_head, "Expected head")
    if expected_base is not None:
        expected_base = _require_full_sha(expected_base, "Expected base")
    head = _git(root, "rev-parse", "--verify", "HEAD^{commit}")
    _require_full_sha(head, "Git HEAD")
    base = _git(root, "rev-parse", "--verify", f"{base_ref}^{{commit}}")
    _require_full_sha(base, "Git base")
    merge_base = _git(root, "merge-base", head, base)
    _require_full_sha(merge_base, "Git merge-base")
    if expected_head is not None and head != expected_head:
        raise BranchOwnerError(
            f"Resolved HEAD {head} does not match expected head {expected_head}."
        )
    if expected_base is not None and base != expected_base:
        raise BranchOwnerError(
            f"Resolved base {base} does not match expected base {expected_base}."
        )
    if expected_base is not None and merge_base != expected_base:
        raise BranchOwnerError(
            f"Candidate does not contain the required base {expected_base}; "
            f"merge-base is {merge_base}."
        )
    return {
        "branch": branch,
        "owner": owner,
        "head": head,
        "base_ref": base_ref,
        "base": base,
        "merge_base": merge_base,
    }


def _resolve_contract_tool(
    repository: Path,
    contract_tool: str | Path | None,
) -> tuple[Path, bool]:
    trusted = contract_tool is not None
    if contract_tool is None:
        candidate = repository / "tools" / "workbench_contract.py"
    else:
        requested = Path(contract_tool).expanduser()
        if not requested.is_absolute():
            raise BranchOwnerError(
                "Trusted ownership verifier path must be absolute."
            )
        candidate = requested
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise BranchOwnerError(
            f"Ownership verifier cannot be resolved: {candidate}: {error}"
        ) from error
    if not resolved.is_file():
        raise BranchOwnerError(f"Ownership verifier is not a file: {resolved}")
    if trusted:
        try:
            resolved.relative_to(repository)
        except ValueError:
            pass
        else:
            raise BranchOwnerError(
                "Trusted ownership verifier must be outside the candidate repository."
            )
    return resolved, trusted


def validate_branch_diff(
    repository: str | Path,
    branch: str,
    base_ref: str,
    expected_head: str | None = None,
    expected_base: str | None = None,
    contract_tool: str | Path | None = None,
) -> dict[str, str]:
    root = Path(repository).expanduser().resolve()
    trusted = _trusted_arguments(expected_head, expected_base, contract_tool)
    if trusted is not None:
        expected_head, expected_base, contract_tool = trusted
    state = resolve_validation_state(
        root,
        branch,
        base_ref,
        expected_head=expected_head,
        expected_base=expected_base,
    )
    contract, trusted_mode = _resolve_contract_tool(root, contract_tool)
    isolated_launcher = Path(__file__).resolve().with_name("ci_python_entry.py")
    contract_lock = contract.resolve().with_name("workbench_lock.py")
    if not isolated_launcher.is_file() or not contract_lock.is_file():
        raise BranchOwnerError(
            "Trusted isolated Python launcher or exact workbench lock is missing."
        )
    command = [
        sys.executable,
        "-I",
        "-B",
        str(isolated_launcher),
        "--preload",
        f"workbench_lock={contract_lock}",
        "--script",
        str(contract),
        "--",
        "--repo",
        str(root),
        "validate",
        "--owner",
        state["owner"],
        "--diff",
        "--base",
        state["merge_base"],
    ]
    try:
        process = subprocess.run(command, check=False)
    except OSError as error:
        raise BranchOwnerError(
            f"Cannot execute ownership verifier {contract}: {error}"
        ) from error
    if process.returncode != 0:
        raise BranchOwnerError(
            f"Committed branch diff violates owner {state['owner']!r} "
            f"relative to merge-base {state['merge_base']}."
        )
    final_state = resolve_validation_state(
        root,
        branch,
        base_ref,
        expected_head=expected_head,
        expected_base=expected_base,
    )
    if final_state != state:
        raise BranchOwnerError(
            "Repository identity changed while ownership validation was running."
        )
    return {
        **state,
        "contract_tool": str(contract),
        "validation_mode": "trusted" if trusted_mode else "local-feedback",
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate the complete committed diff of one Codex owner branch."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    resolve = subparsers.add_parser("resolve")
    resolve.add_argument("--branch", required=True)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--repo", default=".")
    validate.add_argument("--branch", required=True)
    validate.add_argument("--base-ref", default="refs/remotes/origin/main")
    validate.add_argument("--expected-head")
    validate.add_argument("--expected-base")
    validate.add_argument("--contract-tool")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        if arguments.command == "resolve":
            result = {
                "status": "PASS",
                "branch": arguments.branch,
                "owner": resolve_owner(arguments.branch),
            }
        else:
            result = {
                "status": "PASS",
                **validate_branch_diff(
                    arguments.repo,
                    arguments.branch,
                    arguments.base_ref,
                    expected_head=arguments.expected_head,
                    expected_base=arguments.expected_base,
                    contract_tool=arguments.contract_tool,
                ),
            }
    except BranchOwnerError as error:
        print(f"CI BRANCH OWNER FAILED: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
