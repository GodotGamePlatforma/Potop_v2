from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
FAST = WORKFLOWS / "agent-validation.yml"
FULL = WORKFLOWS / "agent-integration.yml"
PUBLISH = ROOT / "tools" / "publish_agent_pr.ps1"
SETUP = ROOT / "tools" / "setup_agent_worktree.ps1"
SYNC = ROOT / "tools" / "sync_play_main.ps1"
DECISIONS = ROOT / ".ai" / "DECISIONS.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _job(workflow: str, job_id: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        workflow,
    )
    if match is None:
        raise AssertionError(f"workflow job is missing: {job_id}")
    return match.group("body")


class SimpleAgentFlowContractTest(unittest.TestCase):
    maxDiff = None

    def test_fast_green_is_the_only_short_branch_job(self) -> None:
        workflow = _read(FAST)
        self.assertIn('branches:\n      - "codex/**"', workflow)
        self.assertNotIn("pull_request_target:", workflow)
        self.assertNotIn("workflow_run:", workflow)
        self.assertNotIn("repository_dispatch:", workflow)
        self.assertNotIn("workflow_dispatch:", workflow)
        self.assertEqual(["fast-contract"], re.findall(r"(?m)^  ([a-z0-9-]+):$", workflow.split("\njobs:\n", 1)[1]))
        self.assertRegex(_job(workflow, "fast-contract"), r"(?m)^    name: fast-green$")
        self.assertRegex(workflow, r"(?m)^permissions:\n  contents: read$")
        self.assertIn("tools/workbench_contract.py --repo . eol-check", workflow)
        self.assertIn("tools/ci_branch_owner.py validate", workflow)
        self.assertIn("tests/publish_agent_pr_test.ps1", workflow)
        self.assertIn("tests/sync_play_main_test.ps1", workflow)
        self.assertNotIn("run_all_tests.ps1", workflow)
        self.assertNotRegex(workflow, r"(?m)^\s+(?:checks|contents|pull-requests|actions): write$")

    def test_full_regression_is_main_push_only_and_secretless(self) -> None:
        workflow = _read(FULL)
        trigger = workflow.split("\npermissions:\n", 1)[0]
        self.assertIn("push:\n    branches:\n      - main", trigger)
        for forbidden in (
            "pull_request_target:",
            "workflow_run:",
            "repository_dispatch:",
            "workflow_dispatch:",
            "schedule:",
        ):
            self.assertNotIn(forbidden, trigger)
        self.assertIn("concurrency:\n  group: full-regression-main-latest", workflow)
        self.assertIn("cancel-in-progress: true", workflow)
        self.assertNotIn("INTEGRATION_ATTESTER", workflow)
        self.assertNotIn("create-github-app-token", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertNotIn("integration-green", workflow)
        self.assertNotIn("continue-on-error", workflow)
        self.assertRegex(workflow, r"(?m)^permissions:\n  contents: read$")

    def test_each_merged_sha_is_bound_without_moving_main_precondition(self) -> None:
        workflow = _read(FULL)
        exact = _job(workflow, "exact-main")
        self.assertIn("ref: ${{ github.sha }}", exact)
        self.assertIn("PUSH_AFTER: ${{ github.event.after }}", exact)
        self.assertIn('$env:PUSH_AFTER -cne $env:GITHUB_SHA', exact)
        self.assertIn('refs/heads/main', exact)
        self.assertNotIn("ls-remote", workflow)
        self.assertNotIn("refs/remotes/origin/main", workflow)
        self.assertNotIn("current main", workflow.lower())

    def test_background_full_suite_has_four_headless_one_native_and_map(self) -> None:
        workflow = _read(FULL)
        shard = _job(workflow, "shard")
        self.assertEqual(4, len(re.findall(r"(?m)^          - headless-[0-3]$", shard)))
        self.assertEqual(1, len(re.findall(r"(?m)^          - native-0$", shard)))
        self.assertIn("fail-fast: false", shard)
        self.assertIn("tests\\run_all_tests.ps1", shard)
        self.assertIn("-ShardId", shard)
        self.assertIn("-RunReceiptOutputPath", shard)
        map_job = _job(workflow, "map-authority")
        self.assertIn("underwater_map_workbench/tools/build_underwater_map.py --check", map_job)
        self.assertIn("git lfs fetch origin $env:GITHUB_SHA", map_job)

    def test_background_report_fails_red_and_writes_summary(self) -> None:
        report = _job(_read(FULL), "full-regression")
        self.assertRegex(report, r"(?m)^    name: full-regression$")
        self.assertIn("if: ${{ always() }}", report)
        for required in (
            "exact-main",
            "infrastructure",
            "prepare-godot",
            "prepare-plan",
            "map-authority",
            "shard",
        ):
            self.assertRegex(report, rf"(?m)^      - {re.escape(required)}$")
        self.assertIn("GITHUB_STEP_SUMMARY", report)
        self.assertIn("throw \"Incomplete full regression", report)
        self.assertIn("-AggregateShardReceipt", report)

    def test_retired_custom_integrators_are_absent(self) -> None:
        self.assertFalse((WORKFLOWS / "agent-auto-integrator.yml").exists())
        self.assertFalse((WORKFLOWS / "map-control-plane-maintenance.yml").exists())

    def test_all_third_party_actions_are_pinned_and_runners_are_hosted(self) -> None:
        for path in (FAST, FULL):
            workflow = _read(path)
            self.assertNotIn("self-hosted", workflow)
            for action in re.findall(r"(?m)^\s*uses:\s*([^\s#]+)", workflow):
                self.assertRegex(action, r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*@[0-9a-f]{40}$")
            self.assertNotRegex(workflow, r"(?m)^\s+lfs:\s*true$")
            self.assertNotRegex(workflow, r"(?m)^\s+persist-credentials:\s*true$")

    def test_publish_helper_is_plain_exact_native_auto_merge(self) -> None:
        script = _read(PUBLISH)
        param_block = script.split(")", 1)[0]
        for removed in ("TaskId", "ThreadId", "AssignmentId", "Owner"):
            self.assertNotIn(removed, param_block)
        self.assertIn("'pr', 'create'", script)
        self.assertIn("'pr', 'merge'", script)
        self.assertIn("--auto", script)
        self.assertIn("--merge", script)
        self.assertIn("--match-head-commit", script)
        self.assertIn("merge-base", script)
        self.assertNotIn("repository_dispatch", script)
        self.assertNotIn("integration-ready", script)
        self.assertNotIn("control-plane-reviewed", script)
        self.assertNotIn("ci_protected_paths.py", script)
        self.assertNotIn("assignment current", script)
        self.assertNotIn("assignment close", script)

    def test_origin_main_setup_creates_ready_worktree_without_assignment(self) -> None:
        script = _read(SETUP)
        self.assertIn("FromOriginMain", script)
        self.assertIn("WORKTREE_READY", script)
        self.assertIn("refs/remotes/origin/main", script)
        self.assertIn("'worktree', 'add', '-b'", script)
        self.assertNotIn("create-main", script)
        self.assertNotIn("'assignment', 'ack'", script)

    def test_play_main_is_standalone_clean_exact_and_isolated(self) -> None:
        script = _read(SYNC)
        self.assertIn("'clone', '--no-tags', '--single-branch'", script)
        self.assertIn("managed-clone.json", script)
        self.assertIn("rev-parse --git-common-dir", script)
        self.assertIn("git lfs fetch origin", script)
        self.assertIn("'underwater_map_workbench'", script)
        self.assertIn("'tools/build_underwater_map.py', '--check'", script)
        self.assertIn("tests\\run_all_tests.ps1", script)
        self.assertIn("-SourceRepositoryPath", script)
        self.assertIn("SYNC_FAILED_UNCHANGED", script)
        self.assertIn("RetryFailed", script)
        self.assertIn("Register-ScheduledTask", script)
        self.assertNotIn("git worktree add", script)
        self.assertNotIn("git reset --hard", script)
        self.assertNotIn("git clean", script)

    def test_ard_0112_replaces_the_old_premerge_full_gate(self) -> None:
        decisions = _read(DECISIONS)
        headers = re.findall(r"(?m)^## (ARD-[0-9]{4})\b", decisions)
        self.assertEqual(len(headers), len(set(headers)))
        self.assertIn("## ARD-0112", decisions)
        ard_0110 = decisions.split("## ARD-0110", 1)[1].split("\n## ARD-", 1)[0]
        ard_0112 = decisions.split("## ARD-0112", 1)[1]
        self.assertIn("ARD-0112", ard_0110)
        self.assertIn("fast-green", ard_0112)
        self.assertIn("po merge", ard_0112.lower())
        self.assertIn("bez wyjątk", ard_0112.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
