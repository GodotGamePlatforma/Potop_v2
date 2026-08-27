#!/usr/bin/env python3
"""Resolve a Codex branch owner and validate its complete committed diff."""

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
    if process.returncode != 0:
        detail = process.stderr.strip()
        raise BranchOwnerError(
            f"git {' '.join(arguments)} failed ({process.returncode})"
            + (f": {detail}" if detail else "")
        )
    return process.stdout.strip()


def resolve_validation_state(
    repository: str | Path,
    branch: str,
    base_ref: str,
) -> dict[str, str]:
    root = Path(repository).expanduser().resolve()
    owner = resolve_owner(branch)
    head = _git(root, "rev-parse", "--verify", "HEAD^{commit}")
    base = _git(root, "rev-parse", "--verify", f"{base_ref}^{{commit}}")
    merge_base = _git(root, "merge-base", head, base)
    for label, value in (("HEAD", head), ("base", base), ("merge-base", merge_base)):
        if GIT_OBJECT_RE.fullmatch(value) is None:
            raise BranchOwnerError(f"Git returned an invalid {label} commit ID.")
    if _git(root, "merge-base", "--is-ancestor", merge_base, head) != "":
        raise BranchOwnerError("Git returned unexpected merge-base ancestry output.")
    return {
        "branch": branch,
        "owner": owner,
        "head": head,
        "base_ref": base_ref,
        "base": base,
        "merge_base": merge_base,
    }


def validate_branch_diff(
    repository: str | Path,
    branch: str,
    base_ref: str,
) -> dict[str, str]:
    state = resolve_validation_state(repository, branch, base_ref)
    root = Path(repository).expanduser().resolve()
    contract = root / "tools" / "workbench_contract.py"
    if not contract.is_file():
        raise BranchOwnerError(f"Ownership verifier is missing: {contract}")
    command = [
        sys.executable,
        "-B",
        str(contract),
        "--repo",
        str(root),
        "validate",
        "--owner",
        state["owner"],
        "--diff",
        "--base",
        state["merge_base"],
    ]
    process = subprocess.run(command, check=False)
    if process.returncode != 0:
        raise BranchOwnerError(
            f"Committed branch diff violates owner {state['owner']!r} "
            f"relative to merge-base {state['merge_base']}."
        )
    return state


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
                ),
            }
    except BranchOwnerError as error:
        print(f"CI BRANCH OWNER FAILED: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
