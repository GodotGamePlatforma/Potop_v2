#!/usr/bin/env python3
"""Small fail-closed contracts for the two-workflow CI-S1 model."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
FAST = WORKFLOWS / "agent-validation.yml"
FULL = WORKFLOWS / "agent-integration.yml"
ACTION_RE = re.compile(r"(?m)^\s*uses:\s*([^\s#]+)")
PINNED_ACTION_RE = re.compile(
    r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*@[0-9a-f]{40}$"
)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _job(text: str, job_id: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        text,
    )
    if match is None:
        raise AssertionError(f"missing workflow job: {job_id}")
    return match.group("body")


def audit_workflows(fast: str, full: str) -> list[str]:
    errors: list[str] = []
    if 'branches:\n      - "codex/**"' not in fast:
        errors.append("fast trigger is not codex/** push")
    if not re.search(r"(?m)^  fast-contract:\n    name: fast-green$", fast):
        errors.append("fast-green job is missing or renamed")
    if "run_all_tests.ps1" in fast:
        errors.append("fast gate runs the long Godot suite")
    if "push:\n    branches:\n      - main" not in full:
        errors.append("full trigger is not main push")
    if "group: full-regression-main-latest" not in full or "cancel-in-progress: true" not in full:
        errors.append("full regression is not latest-main coalesced")
    if not re.search(r"(?m)^  full-regression:\n    name: full-regression$", full):
        errors.append("full-regression report job is missing")
    if "if: ${{ always() }}" not in _job(full, "full-regression"):
        errors.append("full-regression report is not fail-closed on dependency failure")
    for forbidden in (
        "pull_request_target:",
        "workflow_run:",
        "repository_dispatch:",
        "workflow_dispatch:",
        "schedule:",
        "create-github-app-token",
        "INTEGRATION_ATTESTER",
        "secrets.",
        "self-hosted",
    ):
        if forbidden in fast or forbidden in full:
            errors.append(f"forbidden CI surface: {forbidden}")
    for name, workflow in (("fast", fast), ("full", full)):
        if not re.search(r"(?m)^permissions:\n  contents: read$", workflow):
            errors.append(f"{name} permissions are not contents:read only")
        if re.search(r"(?m)^\s+(?:actions|checks|contents|pull-requests|statuses): write$", workflow):
            errors.append(f"{name} workflow has write permission")
        if re.search(r"(?m)^\s+lfs:\s*true$", workflow):
            errors.append(f"{name} checkout enables implicit LFS")
        if re.search(r"(?m)^\s+persist-credentials:\s*true$", workflow):
            errors.append(f"{name} checkout persists credentials")
        for action in ACTION_RE.findall(workflow):
            if PINNED_ACTION_RE.fullmatch(action) is None:
                errors.append(f"{name} action is not pinned: {action}")
    return errors


class RepositoryWorkflowContractTest(unittest.TestCase):
    maxDiff = None

    def test_repository_has_only_fast_and_background_workflows(self) -> None:
        names = sorted(path.name for path in WORKFLOWS.glob("*.yml"))
        self.assertEqual(["agent-integration.yml", "agent-validation.yml"], names)

    def test_public_ci_surface_is_fail_closed(self) -> None:
        self.assertEqual([], audit_workflows(_read(FAST), _read(FULL)))

    def test_fast_gate_binds_exact_owner_diff(self) -> None:
        fast = _job(_read(FAST), "fast-contract")
        self.assertIn("git fetch --no-tags origin", fast)
        self.assertIn("+refs/heads/main:refs/remotes/origin/main", fast)
        self.assertIn("tools/ci_branch_owner.py validate", fast)
        self.assertIn("--base-ref refs/remotes/origin/main", fast)
        self.assertIn("$env:GITHUB_REF_NAME", fast)
        self.assertIn("$env:GITHUB_SHA", fast)

    def test_full_regression_is_exact_main_and_report_only(self) -> None:
        full = _read(FULL)
        exact = _job(full, "exact-main")
        self.assertIn("ref: ${{ github.sha }}", exact)
        self.assertIn("PUSH_AFTER: ${{ github.event.after }}", exact)
        self.assertIn('$env:PUSH_AFTER -cne $env:GITHUB_SHA', exact)
        self.assertNotIn("integration-green", full)
        self.assertNotIn("auto-revert", full.lower())
        self.assertNotIn("gh pr merge", full)

    def test_full_regression_has_complete_parallel_plan(self) -> None:
        full = _read(FULL)
        shard = _job(full, "shard")
        self.assertEqual(
            ["headless-0", "headless-1", "headless-2", "headless-3", "native-0"],
            re.findall(r"(?m)^          - ((?:headless|native)-[0-9]+)$", shard),
        )
        self.assertIn("fail-fast: false", shard)
        report = _job(full, "full-regression")
        self.assertIn("-AggregateShardReceipt", report)
        self.assertIn("GITHUB_STEP_SUMMARY", report)
        self.assertIn("throw \"Incomplete full regression", report)


class WorkflowAuditorNegativeFixtureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fast = _read(FAST)
        cls.full = _read(FULL)

    def assertRejected(self, fast: str | None = None, full: str | None = None) -> None:
        self.assertTrue(audit_workflows(fast or self.fast, full or self.full))

    def test_rejects_unpinned_action(self) -> None:
        self.assertRejected(fast=self.fast.replace(
            "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
            "actions/checkout@main",
            1,
        ))

    def test_rejects_secret_or_write_permission(self) -> None:
        self.assertRejected(full=self.full + "\n# secrets.BAD\n")
        self.assertRejected(full=self.full.replace("contents: read", "contents: write", 1))

    def test_rejects_long_suite_in_fast_gate(self) -> None:
        self.assertRejected(fast=self.fast + "\n# run_all_tests.ps1\n")

    def test_rejects_removed_or_renamed_required_job(self) -> None:
        self.assertRejected(fast=self.fast.replace("name: fast-green", "name: almost-green", 1))

    def test_rejects_missing_latest_main_cancellation(self) -> None:
        self.assertRejected(full=self.full.replace("cancel-in-progress: true", "cancel-in-progress: false", 1))


if __name__ == "__main__":
    unittest.main(verbosity=2)
