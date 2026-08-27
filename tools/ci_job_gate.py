#!/usr/bin/env python3
"""Fail-closed validation of GitHub Actions fan-in job results."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Sequence


SCHEMA = "github-actions-needs-gate-v1"


class GateError(RuntimeError):
    """Raised when the fan-in dependency set is incomplete or not green."""


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GateError(f"Cannot read needs JSON {path}: {exc}") from exc


def verify_needs(payload: Any, required_jobs: Sequence[str]) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise GateError("GitHub needs context must be a JSON object.")

    required = list(required_jobs)
    if not required or any(not isinstance(job, str) or not job for job in required):
        raise GateError("At least one non-empty required job ID is mandatory.")
    if len(set(required)) != len(required):
        raise GateError("Required job IDs must be unique.")

    actual = set(payload)
    expected = set(required)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing or unexpected:
        raise GateError(
            "Fan-in dependency set mismatch: "
            f"missing={missing or 'none'} unexpected={unexpected or 'none'}."
        )

    results: dict[str, str] = {}
    failures: list[str] = []
    for job in required:
        record = payload[job]
        if not isinstance(record, dict):
            raise GateError(f"Needs record for {job!r} must be an object.")
        result = record.get("result")
        if not isinstance(result, str) or not result:
            raise GateError(f"Needs record for {job!r} has no result.")
        results[job] = result
        if result != "success":
            failures.append(f"{job}={result}")

    if failures:
        raise GateError("Fan-in dependencies are not green: " + ", ".join(failures))

    return {
        "schema": SCHEMA,
        "required_jobs": required,
        "results": results,
        "status": "PASS",
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate the exact GitHub Actions needs context before aggregation."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    verify = subparsers.add_parser("verify-needs")
    verify.add_argument("--input", required=True, type=Path)
    verify.add_argument("--required", required=True, nargs="+")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        result = verify_needs(_read_json(args.input), args.required)
    except GateError as exc:
        print(f"CI JOB GATE FAILED: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
