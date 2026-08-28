#!/usr/bin/env python3
"""Static acceptance tests for the intentionally small GitHub flow."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def text(name: str) -> str:
    return (WORKFLOWS / name).read_text(encoding="utf-8")


class SimpleAgentWorkflowTest(unittest.TestCase):
    def test_old_custom_controllers_are_gone(self) -> None:
        self.assertFalse((WORKFLOWS / "agent-auto-integrator.yml").exists())
        self.assertFalse((WORKFLOWS / "map-control-plane-maintenance.yml").exists())

    def test_pull_request_runs_one_actions_owned_fast_check(self) -> None:
        workflow = text("agent-validation.yml")
        self.assertRegex(workflow, r"(?m)^  pull_request:$")
        self.assertNotIn("pull_request_target", workflow)
        self.assertNotIn("repository_dispatch", workflow)
        self.assertIn("ref: ${{ github.event.pull_request.head.sha }}", workflow)
        self.assertRegex(workflow, r"(?m)^  fast-check:$")
        self.assertRegex(workflow, r"(?m)^    name: fast-check$")
        self.assertIn("runs-on: windows-latest", workflow)
        self.assertIn("./tools/agent_fast_check.ps1", workflow)
        self.assertIn("refs/remotes/origin/main", workflow)
        self.assertIn("-ExpectedHeadSha $env:EXPECTED_HEAD", workflow)
        self.assertIn("-ExpectedBranch $env:EXPECTED_BRANCH", workflow)
        self.assertIn("EXPECTED_BRANCH: ${{ github.event.pull_request.head.ref }}", workflow)
        self.assertIn("persist-credentials: false", workflow)

    def test_merge_group_full_integration_releases_required_fast_check(self) -> None:
        workflow = text("agent-integration.yml")
        self.assertRegex(workflow, r"(?m)^  merge_group:$")
        self.assertNotIn("repository_dispatch", workflow)
        self.assertRegex(workflow, r"(?m)^  integration-green:$")
        self.assertRegex(workflow, r"(?m)^    name: integration-green$")
        self.assertIn("ref: ${{ github.event.merge_group.head_sha }}", workflow)
        self.assertIn("-Full", workflow)
        self.assertIn("./tests/run_all_tests.ps1", workflow)
        self.assertRegex(workflow, r"(?ms)^  fast-check:\n.*?needs:\n      - integration-green")
        self.assertIn("INTEGRATION_RESULT: ${{ needs.integration-green.result }}", workflow)
        self.assertIn('if [ "$INTEGRATION_RESULT" != "success" ]', workflow)
        self.assertIn("runs-on: ubuntu-latest", workflow)

    def test_candidate_jobs_are_secretless_and_github_hosted(self) -> None:
        combined = text("agent-validation.yml") + "\n" + text("agent-integration.yml")
        forbidden = (
            "self-hosted",
            "secrets.",
            "create-github-app-token",
            "/check-runs",
            "INTEGRATION_ATTESTER",
            "candidate_receipt",
            "run_receipt",
            "FROZEN_RECEIPT",
            "last-green",
        )
        for token in forbidden:
            with self.subTest(token=token):
                self.assertNotIn(token, combined)
        self.assertNotRegex(combined, r"(?m)^\s+(?:checks|contents|pull-requests): write$")

    def test_both_workflows_hydrate_and_reject_remaining_lfs_pointers(self) -> None:
        workflows = (text("agent-validation.yml"), text("agent-integration.yml"))
        for workflow in workflows:
            with self.subTest(workflow=workflow.splitlines()[0]):
                self.assertNotIn("GIT_LFS_SKIP_SMUDGE", workflow)
                self.assertIn("lfs: true", workflow)
                self.assertIn("git lfs checkout", workflow)
                self.assertIn("git lfs fsck", workflow)
                self.assertIn('"git", "lfs", "ls-files", "--json"', workflow)
                self.assertIn("version https://git-lfs.github.com/spec/v1", workflow)
                self.assertIn("Tracked LFS pointers remain unhydrated", workflow)

    def test_actions_are_pinned_and_godot_archive_is_verified(self) -> None:
        combined = text("agent-validation.yml") + "\n" + text("agent-integration.yml")
        uses = re.findall(r"(?m)^\s+-?\s*uses:\s*([^\s#]+)", combined)
        self.assertGreaterEqual(len(uses), 4)
        for action in uses:
            with self.subTest(action=action):
                self.assertRegex(action, r"@[0-9a-f]{40}$")
        self.assertEqual(combined.count("GODOT_ARCHIVE_SHA256:"), 2)
        self.assertGreaterEqual(combined.count("Get-FileHash"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
