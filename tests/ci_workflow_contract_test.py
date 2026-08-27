#!/usr/bin/env python3
"""Fail-closed static contract for the three CI-S1A workflows."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
FEEDBACK = WORKFLOWS / "agent-validation.yml"
TRUSTED = WORKFLOWS / "agent-auto-integrator.yml"
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


def audit_workflows(feedback: str, trusted: str, full: str) -> list[str]:
    errors: list[str] = []
    if "pull_request:" not in feedback or "merge_group:" not in feedback:
        errors.append("secretless feedback does not cover PR and merge_group")
    if "repository_dispatch:" not in trusted or "verify-fast-pr" not in trusted:
        errors.append("trusted default-branch receiver is missing")
    if "push:\n    branches:\n      - main" not in full:
        errors.append("full regression is not main-push only")
    if "group: full-regression-main-latest" not in full or "cancel-in-progress: true" not in full:
        errors.append("background regression is not latest-main coalesced")
    for forbidden in ("pull_request_target:",):
        if forbidden in feedback or forbidden in trusted or forbidden in full:
            errors.append(f"forbidden trigger: {forbidden}")
    if "workflow_run:" in feedback or "workflow_run:" in trusted or "workflow_run:" in full:
        errors.append("merge-group liveness depends on a mutable workflow_run source")
    if len(re.findall(r"(?m)^  schedule:\s*$", trusted)) != 1 or 'cron: "*/5 * * * *"' not in trusted:
        errors.append("trusted default-branch merge-group schedule watchdog is missing")
    if "workflow_dispatch:" not in trusted:
        errors.append("trusted merge-group recovery dispatch is missing")
    if "AUTO_INTEGRATOR_ENABLED == 'true'" not in trusted:
        errors.append("trusted automatic gate does not fail closed on its rollout flag")
    for forbidden in ("OPENAI_API_KEY", "INTEGRATION_ATTESTER_PRIVATE_KEY", "checks: write"):
        if forbidden in feedback or forbidden in full:
            errors.append(f"candidate/background workflow receives trusted credential: {forbidden}")
    if "openai/codex-action@" not in trusted or "create-github-app-token@" not in trusted:
        errors.append("trusted sensitive/App publisher jobs are missing")
    if trusted.count("environment: integration-attester") != 2:
        errors.append("trusted secrets are not confined to the automatic attester environment")
    if "name = \"fast-green\"" not in trusted or "head_sha = $env:TARGET_SHA" not in trusted:
        errors.append("App-owned exact-target fast-green publication is missing")
    if trusted.count('kind = "merge_group"') < 2 or "queue_ref = $queueRef" not in trusted:
        errors.append("synthetic merge-group redispatch binding is missing")
    for name, workflow in (
        ("feedback", feedback),
        ("trusted", trusted),
        ("full", full),
    ):
        if "self-hosted" in workflow:
            errors.append(f"{name} uses a persistent self-hosted runner")
        if re.search(r"(?m)^\s+lfs:\s*true$", workflow):
            errors.append(f"{name} checkout enables implicit LFS")
        if re.search(r"(?m)^\s+persist-credentials:\s*true$", workflow):
            errors.append(f"{name} checkout persists credentials")
        for action in ACTION_RE.findall(workflow):
            if PINNED_ACTION_RE.fullmatch(action) is None:
                errors.append(f"{name} action is not immutable: {action}")
    return errors


class RepositoryWorkflowContractTest(unittest.TestCase):
    maxDiff = None

    def test_repository_has_only_ci_s1a_workflows(self) -> None:
        self.assertEqual(
            [
                "agent-auto-integrator.yml",
                "agent-integration.yml",
                "agent-validation.yml",
            ],
            sorted(path.name for path in WORKFLOWS.glob("*.yml")),
        )

    def test_public_ci_surface_is_fail_closed(self) -> None:
        self.assertEqual([], audit_workflows(_read(FEEDBACK), _read(TRUSTED), _read(FULL)))

    def test_candidate_feedback_is_secretless_and_not_required_authority(self) -> None:
        workflow = _read(FEEDBACK)
        self.assertIn("pull_request:", workflow)
        self.assertIn("merge_group:", workflow)
        self.assertIn("name: Agent fast feedback", workflow)
        self.assertNotRegex(workflow, r"(?m)^\s+name: fast-green$")
        self.assertNotIn("repository_dispatch:", workflow)
        self.assertNotIn("openai/codex-action@", workflow)
        self.assertNotIn("create-github-app-token@", workflow)
        self.assertRegex(workflow, r"(?m)^permissions:\n  contents: read$")
        self.assertNotRegex(
            workflow,
            r"(?m)^\s+(?:actions|checks|contents|pull-requests|statuses): write$",
        )

    def test_trusted_receiver_uses_default_branch_dispatch_and_metadata_only_watchdog(self) -> None:
        workflow = _read(TRUSTED)
        trigger = workflow.split("\npermissions:", 1)[0]
        self.assertIn("repository_dispatch:", trigger)
        self.assertIn("verify-fast-pr", trigger)
        self.assertIn("schedule:", trigger)
        self.assertIn('cron: "*/5 * * * *"', trigger)
        self.assertIn("workflow_dispatch:", trigger)
        for forbidden in (
            "pull_request:",
            "pull_request_target:",
            "merge_group:",
            "workflow_run:",
        ):
            self.assertNotIn(forbidden, trigger)
        self.assertIn("ref: ${{ github.sha }}", _job(workflow, "verify-request"))
        self.assertIn("path: trusted-control", _job(workflow, "verify-request"))
        intake = _job(workflow, "merge-group-intake")
        self.assertIn("github.event_name == 'schedule'", intake)
        self.assertIn("github.event_name == 'workflow_dispatch'", intake)
        self.assertIn("AUTO_INTEGRATOR_ENABLED == 'true'", intake)
        self.assertIn("git/matching-refs/heads/gh-readonly-queue/main/", intake)
        self.assertIn("gh-readonly-queue/main/pr-", intake)
        self.assertIn('kind = "merge_group"', intake)
        publisher = _job(workflow, "publish-check")
        self.assertIn("github.event_name == 'repository_dispatch'", publisher)
        self.assertIn("AUTO_INTEGRATOR_ENABLED == 'true'", publisher)
        capture_offset = intake.index("$pullNumber = [int]$Matches.pr")
        sha_offset = intake.index("$groupSha -cnotmatch '^[0-9a-f]{40}$'")
        self.assertLess(capture_offset, sha_offset)
        self.assertIn("target_sha = $groupSha", intake)
        self.assertIn("/dispatches", intake)
        for forbidden in ("actions/checkout@", "artifacts", "candidate-head", "candidate-target"):
            self.assertNotIn(forbidden, intake)

    def test_trusted_receiver_binds_full_pr_and_synthetic_queue_sha(self) -> None:
        workflow = _read(TRUSTED)
        verify = _job(workflow, "verify-request")
        for marker in (
            "pull.changed_files",
            "per_page=100&page=$page",
            "$files.Count -gt 3000",
            "previous_filename",
            "unsupported PR file status",
            "--raw --no-abbrev",
            "Symlink and submodule entries are forbidden",
            "ci_branch_owner.py validate",
            "ci_protected_paths.py classify-diff",
            "workbench_contract.py --repo candidate-target eol-check",
            "merge-base --is-ancestor $env:REQUEST_BASE_SHA $env:REQUEST_TARGET_SHA",
            "merge-base --is-ancestor $env:REQUEST_HEAD_SHA $env:REQUEST_TARGET_SHA",
            "gh-readonly-queue/main/pr-$pullNumber-",
        ):
            self.assertIn(marker, verify)
        broker = _job(workflow, "queue-broker")
        self.assertIn("git/matching-refs/heads/gh-readonly-queue/main/pr-$env:PR_NUMBER-", broker)
        self.assertIn('kind = "merge_group"', broker)
        self.assertIn("target_sha = $groupSha", broker)
        self.assertIn("queue_ref = $queueRef", broker)
        self.assertIn("/dispatches", broker)

    def test_sensitive_codex_job_never_checks_out_candidate(self) -> None:
        job = _job(_read(TRUSTED), "codex-review")
        self.assertIn("needs.verify-request.outputs.sensitive == 'true'", job)
        self.assertIn("path: trusted-control", job)
        self.assertNotIn("candidate-head", job)
        self.assertNotIn("candidate-target", job)
        self.assertIn("application/vnd.github.diff", job)
        self.assertIn("Assert-ReviewIdentity $before", job)
        self.assertIn("Assert-ReviewIdentity $after", job)
        self.assertIn("diff-sha256=$reviewDiffSha", job)
        self.assertIn("UNTRUSTED_DIFF", job)
        self.assertIn('permission-profile: ":read-only"', job)
        self.assertIn("safety-strategy: drop-sudo", job)
        self.assertIn("additionalProperties", job)
        self.assertTrue(job.rstrip().endswith('}'), "Codex action must remain the final job step")

    def test_app_publisher_never_executes_or_checks_out_candidate(self) -> None:
        job = _job(_read(TRUSTED), "publish-check")
        self.assertIn("permission-checks: write", job)
        self.assertIn("INTEGRATION_ATTESTER_PRIVATE_KEY", job)
        self.assertIn("INTEGRATION_ATTESTER_APP_ID", job)
        self.assertIn("$appId -ne 4737404", job)
        self.assertNotIn("actions/checkout@", job)
        self.assertNotIn("candidate-head", job)
        self.assertNotIn("candidate-target", job)
        self.assertIn('name = "fast-green"', job)
        self.assertIn("head_sha = $env:TARGET_SHA", job)
        self.assertIn("Duplicate App-owned fast-green binding", job)
        self.assertIn("[long]$check.app.id -ne $appId", job)
        self.assertIn("$env:KIND", job)
        self.assertIn("$env:PR_NUMBER", job)
        self.assertIn("$env:DIFF_SHA256", job)
        self.assertIn("$env:POLICY_SHA", job)
        self.assertIn("$env:QUEUE_REF", job)
        self.assertIn("$env:REVIEW_DIFF_SHA256", job)
        self.assertIn("$proofMaterial", job)

    def test_full_regression_remains_report_only_latest_main(self) -> None:
        workflow = _read(FULL)
        self.assertIn("push:\n    branches:\n      - main", workflow)
        self.assertIn("group: full-regression-main-latest", workflow)
        self.assertIn("cancel-in-progress: true", workflow)
        self.assertNotIn("repository_dispatch:", workflow)
        self.assertNotIn("INTEGRATION_ATTESTER", workflow)
        self.assertNotIn("fast-green", workflow)
        self.assertNotIn("auto-revert", workflow.lower())
        self.assertNotIn("gh pr merge", workflow)
        shard = _job(workflow, "shard")
        self.assertEqual(
            ["headless-0", "headless-1", "headless-2", "headless-3", "native-0"],
            re.findall(r"(?m)^          - ((?:headless|native)-[0-9]+)$", shard),
        )
        self.assertIn("fail-fast: false", shard)
        self.assertIn(
            "underwater_map_workbench/tools/build_underwater_map.py --check",
            _job(workflow, "map-authority"),
        )
        report = _job(workflow, "full-regression")
        self.assertIn("if: ${{ always() }}", report)
        self.assertIn("GITHUB_STEP_SUMMARY", report)


class NegativeFixtureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.feedback = _read(FEEDBACK)
        cls.trusted = _read(TRUSTED)
        cls.full = _read(FULL)

    def assert_rejected(
        self,
        *,
        feedback: str | None = None,
        trusted: str | None = None,
        full: str | None = None,
    ) -> None:
        self.assertTrue(
            audit_workflows(
                feedback or self.feedback,
                trusted or self.trusted,
                full or self.full,
            )
        )

    def test_rejects_unpinned_action(self) -> None:
        self.assert_rejected(
            trusted=self.trusted.replace(
                "openai/codex-action@f367b1e9572fd064ea71ef925ca24ee0f01080af",
                "openai/codex-action@v1",
                1,
            )
        )

    def test_rejects_secret_in_candidate_workflow(self) -> None:
        self.assert_rejected(feedback=self.feedback + "\n# OPENAI_API_KEY\n")

    def test_rejects_missing_merge_group_dispatch(self) -> None:
        self.assert_rejected(
            trusted=self.trusted.replace('kind = "merge_group"', 'kind = "missing"', 1)
        )

    def test_rejects_missing_merge_group_watchdog(self) -> None:
        self.assert_rejected(
            trusted=self.trusted.replace("schedule:", "missing_schedule:", 1)
        )

    def test_rejects_missing_latest_main_cancellation(self) -> None:
        self.assert_rejected(
            full=self.full.replace("cancel-in-progress: true", "cancel-in-progress: false", 1)
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
