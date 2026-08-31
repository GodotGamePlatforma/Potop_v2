#!/usr/bin/env python3
"""Mutation-style checks for the simple native merge-queue contract."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATION = ROOT / ".github" / "workflows" / "agent-validation.yml"
INTEGRATION = ROOT / ".github" / "workflows" / "agent-integration.yml"


def job_block(workflow: str, job_id: str) -> str:
    marker = f"  {job_id}:\n"
    start = workflow.find(marker)
    if start < 0:
        return ""
    next_job = workflow.find("\n  ", start + len(marker))
    while next_job >= 0:
        line_end = workflow.find("\n", next_job + 1)
        candidate = workflow[next_job + 1 : line_end if line_end >= 0 else len(workflow)]
        if candidate.endswith(":") and not candidate.startswith("    "):
            return workflow[start:next_job]
        next_job = workflow.find("\n  ", next_job + 3)
    return workflow[start:]


def violations(validation: str, integration: str) -> list[str]:
    findings: list[str] = []
    combined = validation + "\n" + integration
    validation_fast_check = job_block(validation, "fast-check")
    integration_shards = job_block(integration, "integration-shards")
    integration_green = job_block(integration, "integration-green")
    fast_check = job_block(integration, "fast-check")
    for token in (
        "repository_dispatch",
        "workflow_run",
        "pull_request_target",
        "create-github-app-token",
        "/check-runs",
        "self-hosted",
        "secrets.",
        "GIT_LFS_SKIP_SMUDGE",
    ):
        if token in combined:
            findings.append(f"forbidden token: {token}")
    if "  pull_request:\n" not in validation:
        findings.append("validation must use pull_request")
    if validation.count("    name: fast-check\n") != 1:
        findings.append("PR workflow must expose exactly one fast-check job")
    if "github.event.pull_request.head.sha" not in validation:
        findings.append("PR workflow must check out the exact head")
    if "-ExpectedHeadSha $env:EXPECTED_HEAD" not in validation:
        findings.append("PR fast-check must bind detached HEAD to the event SHA")
    if "-ExpectedBranch $env:EXPECTED_BRANCH" not in validation:
        findings.append("PR fast-check must bind the event branch")
    if "./tools/agent_fast_check.ps1" not in validation:
        findings.append("PR workflow must use the canonical fast-check")
    timeout = re.search(r"(?m)^    timeout-minutes:\s*(\d+)\s*$", validation_fast_check)
    if timeout is None or int(timeout.group(1)) < 60:
        findings.append("PR fast-check timeout must allow the canonical changed-target lane")
    if "  merge_group:\n" not in integration:
        findings.append("integration workflow must use merge_group")
    if "  integration-shards:\n" not in integration:
        findings.append("merge group must define the two paid shard jobs")
    if integration.count("runs-on: potop-windows-16core-64gb") != 1:
        findings.append("heavy integration matrix must use the configured larger runner")
    if "      max-parallel: 2\n" not in integration:
        findings.append("heavy integration matrix must use exactly two concurrent jobs")
    if "      fail-fast: false\n" not in integration:
        findings.append("both shard results must be collected for one repair iteration")
    if integration.count("          - slot: ") != 2:
        findings.append("integration matrix must contain exactly two heavy jobs")
    for token in (
        "headless_shard: headless-0",
        "headless_shard: headless-1",
        "run_native: true",
        "-WriteShardPlan $planPath",
        "-HeadlessShardCount 2",
        "-NativeShardCount 1",
        "-ShardId $headlessShard",
        '-ShardId "native-0"',
    ):
        if token not in integration:
            findings.append(f"integration shard contract is missing: {token}")
    if integration.count("-RunReceiptOutputPath $receiptPath") != 2:
        findings.append("both logical shard executions must finish through the canonical receipt path")
    if integration.count("    name: integration-green\n") != 1:
        findings.append("merge-group workflow must expose integration-green")
    if "      - integration-shards\n" not in integration:
        findings.append("integration-green must depend on both matrix shard jobs")
    if "needs.integration-shards.result" not in integration_green:
        findings.append("integration-green must reject a non-success shard matrix")
    if 'if [ "$SHARD_JOBS_RESULT" != "success" ]' not in integration_green:
        findings.append("integration-green must fail for every non-success shard matrix")
    if integration.count("    name: fast-check\n") != 1:
        findings.append("merge-group workflow must expose one fast-check bridge")
    if "      - integration-green\n" not in integration:
        findings.append("group fast-check must depend on integration-green")
    if "needs.integration-green.result" not in fast_check:
        findings.append("group fast-check must inspect the dependency result")
    if 'if [ "$INTEGRATION_RESULT" != "success" ]' not in fast_check:
        findings.append("non-success integration must fail group fast-check")
    if "-Full" not in integration or "./tests/run_all_tests.ps1" not in integration:
        findings.append("merge group must run the full project suite")
    if "permissions:\n  contents: read" not in validation:
        findings.append("PR workflow must be read-only")
    if "permissions:\n  contents: read" not in integration:
        findings.append("group workflow must be read-only")
    lfs_contracts = (
        ("PR", (validation,)),
        ("merge-group", (integration_shards,)),
    )
    for label, blocks in lfs_contracts:
        if any("lfs: true" not in block for block in blocks):
            findings.append(f"{label} checkout must fetch LFS objects")
        if any("git lfs checkout" not in block or "git lfs fsck" not in block for block in blocks):
            findings.append(f"{label} workflow must hydrate and fsck LFS before tests")
        if any('"git", "lfs", "ls-files", "--json"' not in block for block in blocks):
            findings.append(f"{label} workflow must enumerate tracked LFS files")
        if any("version https://git-lfs.github.com/spec/v1" not in block for block in blocks):
            findings.append(f"{label} workflow must reject remaining LFS pointers")
    return findings


class WorkflowContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.validation = VALIDATION.read_text(encoding="utf-8")
        self.integration = INTEGRATION.read_text(encoding="utf-8")

    def test_current_workflows_pass(self) -> None:
        self.assertEqual([], violations(self.validation, self.integration))

    def test_missing_dependency_is_detected(self) -> None:
        mutated = self.integration.replace("      - integration-green\n", "      - unrelated\n", 1)
        self.assertIn(
            "group fast-check must depend on integration-green",
            violations(self.validation, mutated),
        )

    def test_false_green_bridge_is_detected(self) -> None:
        mutated = self.integration.replace(
            'if [ "$INTEGRATION_RESULT" != "success" ]',
            'if [ "$INTEGRATION_RESULT" == "cancelled" ]',
            1,
        )
        self.assertIn(
            "non-success integration must fail group fast-check",
            violations(self.validation, mutated),
        )

    def test_paid_runner_parallelism_regressions_are_detected(self) -> None:
        wrong_runner = self.integration.replace(
            "runs-on: potop-windows-16core-64gb",
            "runs-on: windows-latest",
            1,
        )
        self.assertIn(
            "heavy integration matrix must use the configured larger runner",
            violations(self.validation, wrong_runner),
        )
        serial = self.integration.replace("max-parallel: 2", "max-parallel: 1", 1)
        self.assertIn(
            "heavy integration matrix must use exactly two concurrent jobs",
            violations(self.validation, serial),
        )

    def test_missing_native_or_matrix_gate_is_detected(self) -> None:
        no_native = self.integration.replace('-ShardId "native-0"', '-ShardId "headless-1"', 1)
        self.assertIn(
            'integration shard contract is missing: -ShardId "native-0"',
            violations(self.validation, no_native),
        )
        no_matrix_gate = self.integration.replace("needs.integration-shards.result", "needs.unrelated.result", 1)
        self.assertIn(
            "integration-green must reject a non-success shard matrix",
            violations(self.validation, no_matrix_gate),
        )
        false_green = self.integration.replace(
            'if [ "$SHARD_JOBS_RESULT" != "success" ]',
            'if [ "$SHARD_JOBS_RESULT" == "cancelled" ]',
            1,
        )
        self.assertIn(
            "integration-green must fail for every non-success shard matrix",
            violations(self.validation, false_green),
        )

    def test_custom_app_or_dispatch_regression_is_detected(self) -> None:
        for token in ("repository_dispatch", "create-github-app-token", "/check-runs"):
            with self.subTest(token=token):
                findings = violations(self.validation + "\n" + token, self.integration)
                self.assertIn(f"forbidden token: {token}", findings)

    def test_wrong_event_and_unpinned_head_are_detected(self) -> None:
        mutated = self.validation.replace("  pull_request:\n", "  push:\n", 1)
        mutated = mutated.replace("github.event.pull_request.head.sha", "github.sha")
        findings = violations(mutated, self.integration)
        self.assertIn("validation must use pull_request", findings)
        self.assertIn("PR workflow must check out the exact head", findings)

    def test_short_pr_timeout_is_detected(self) -> None:
        mutated = re.sub(
            r"(?m)^    timeout-minutes:\s*\d+\s*$",
            "    timeout-minutes: 20",
            self.validation,
            count=1,
        )
        self.assertIn(
            "PR fast-check timeout must allow the canonical changed-target lane",
            violations(mutated, self.integration),
        )

    def test_detached_sha_binding_and_lfs_regressions_are_detected(self) -> None:
        detached = self.validation.replace("-ExpectedHeadSha $env:EXPECTED_HEAD", "")
        self.assertIn(
            "PR fast-check must bind detached HEAD to the event SHA",
            violations(detached, self.integration),
        )
        for target, other, label in (
            (self.validation, self.integration, "PR"),
            (self.integration, self.validation, "merge-group"),
        ):
            mutated = target.replace("git lfs checkout", "git lfs status")
            candidate_validation = mutated if label == "PR" else other
            candidate_integration = other if label == "PR" else mutated
            self.assertIn(
                f"{label} workflow must hydrate and fsck LFS before tests",
                violations(candidate_validation, candidate_integration),
            )

    def test_skip_smudge_regression_is_detected(self) -> None:
        mutated = self.validation + '\n  GIT_LFS_SKIP_SMUDGE: "1"\n'
        self.assertIn(
            "forbidden token: GIT_LFS_SKIP_SMUDGE",
            violations(mutated, self.integration),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
