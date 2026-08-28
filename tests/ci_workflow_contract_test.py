#!/usr/bin/env python3
"""Mutation-style checks for the simple native merge-queue contract."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATION = ROOT / ".github" / "workflows" / "agent-validation.yml"
INTEGRATION = ROOT / ".github" / "workflows" / "agent-integration.yml"


def violations(validation: str, integration: str) -> list[str]:
    findings: list[str] = []
    combined = validation + "\n" + integration
    for token in (
        "repository_dispatch",
        "workflow_run",
        "pull_request_target",
        "create-github-app-token",
        "/check-runs",
        "self-hosted",
        "secrets.",
    ):
        if token in combined:
            findings.append(f"forbidden token: {token}")
    if "  pull_request:\n" not in validation:
        findings.append("validation must use pull_request")
    if validation.count("    name: fast-check\n") != 1:
        findings.append("PR workflow must expose exactly one fast-check job")
    if "github.event.pull_request.head.sha" not in validation:
        findings.append("PR workflow must check out the exact head")
    if "./tools/agent_fast_check.ps1" not in validation:
        findings.append("PR workflow must use the canonical fast-check")
    if "  merge_group:\n" not in integration:
        findings.append("integration workflow must use merge_group")
    if integration.count("    name: integration-green\n") != 1:
        findings.append("merge-group workflow must expose integration-green")
    if integration.count("    name: fast-check\n") != 1:
        findings.append("merge-group workflow must expose one fast-check bridge")
    if "      - integration-green\n" not in integration:
        findings.append("group fast-check must depend on integration-green")
    if "needs.integration-green.result" not in integration:
        findings.append("group fast-check must inspect the dependency result")
    if '!= "success"' not in integration:
        findings.append("non-success integration must fail group fast-check")
    if "-Full" not in integration or "./tests/run_all_tests.ps1" not in integration:
        findings.append("merge group must run the full project suite")
    if "permissions:\n  contents: read" not in validation:
        findings.append("PR workflow must be read-only")
    if "permissions:\n  contents: read" not in integration:
        findings.append("group workflow must be read-only")
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
        mutated = self.integration.replace('!= "success"', '== "cancelled"', 1)
        self.assertIn(
            "non-success integration must fail group fast-check",
            violations(self.validation, mutated),
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
