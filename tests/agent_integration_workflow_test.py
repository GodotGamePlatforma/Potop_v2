#!/usr/bin/env python3
"""Cross-file CI-S1A, assignment and playable-build contract."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FEEDBACK = ROOT / ".github" / "workflows" / "agent-validation.yml"
TRUSTED = ROOT / ".github" / "workflows" / "agent-auto-integrator.yml"
FULL = ROOT / ".github" / "workflows" / "agent-integration.yml"
PUBLISH = ROOT / "tools" / "publish_agent_pr.ps1"
SETUP = ROOT / "tools" / "setup_agent_worktree.ps1"
CONTRACT = ROOT / "tools" / "workbench_contract.py"
SYNC = ROOT / "tools" / "sync_play_main.ps1"
DECISIONS = ROOT / ".ai" / "DECISIONS.md"
README = ROOT / "README.md"
ARCHITECTURE = ROOT / "docs" / "Ostatni_Pomost_architektura_Godot.txt"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class SimpleAgentFlowContractTest(unittest.TestCase):
    maxDiff = None

    def test_one_automatic_lane_has_feedback_trusted_gate_queue_and_squash(self) -> None:
        feedback = _read(FEEDBACK)
        trusted = _read(TRUSTED)
        publisher = _read(PUBLISH)
        self.assertIn("pull_request:", feedback)
        self.assertIn("merge_group:", feedback)
        self.assertIn("repository_dispatch:", trusted)
        self.assertIn("verify-fast-pr", trusted)
        self.assertIn("openai/codex-action@", trusted)
        self.assertIn("create-github-app-token@", trusted)
        self.assertIn('name = "fast-green"', trusted)
        self.assertIn("gh-readonly-queue/main/pr-$env:PR_NUMBER-", trusted)
        self.assertIn("'--auto', '--squash', '--match-head-commit', $head", publisher)
        for forbidden in (
            "MANUAL_CONTROL_PLANE",
            "control-plane-reviewed",
            "--admin",
            "--disable-auto",
            "control-plane-maintenance",
        ):
            self.assertNotIn(forbidden, publisher + trusted)
        self.assertEqual(trusted.count("environment: integration-attester"), 2)

    def test_candidate_feedback_never_receives_trusted_credentials(self) -> None:
        feedback = _read(FEEDBACK)
        for forbidden in (
            "OPENAI_API_KEY",
            "INTEGRATION_ATTESTER",
            "create-github-app-token",
            "openai/codex-action",
            "checks: write",
            "contents: write",
        ):
            self.assertNotIn(forbidden, feedback)
        self.assertNotIn("name: fast-green", feedback)
        self.assertIn("name: Agent fast feedback", feedback)

    def test_publisher_requires_fresh_base_running_assignment_and_exact_dispatch(self) -> None:
        script = _read(PUBLISH)
        current_offset = script.index("'assignment', 'current', '--json'")
        validate_offset = script.index("'--assignment', $assignmentId")
        push_offset = script.index("'push', '--set-upstream'")
        dispatch_offset = script.index("'event_type=verify-fast-pr'")
        merge_offset = script.index("'--auto', '--squash'")
        close_offset = script.rindex(
            "Close-CurrentAssignment -Repository $repo -Assignment $assignment"
        )
        self.assertLess(current_offset, validate_offset)
        self.assertLess(validate_offset, push_offset)
        self.assertLess(push_offset, dispatch_offset)
        self.assertLess(dispatch_offset, merge_offset)
        self.assertLess(merge_offset, close_offset)
        for marker in (
            "refs/remotes/origin/main^{commit}",
            "merge-base",
            "--task-id",
            "--thread-id",
            "--owner",
            "'--base', $originMain",
            "assignment_state",
            "client_payload[base_sha]",
            "client_payload[head_sha]",
            "client_payload[target_sha]",
            "--match-head-commit",
        ):
            self.assertIn(marker, script)
        self.assertNotIn("ci_protected_paths.py", script)
        self.assertNotIn("'--auto', '--merge'", script)

    def test_origin_main_setup_preserves_durable_assignment_ack(self) -> None:
        script = _read(SETUP)
        for marker in (
            "FromOriginMain",
            "TaskId",
            "ThreadId",
            "TaskBrief",
            "writeSetPath",
            "refs/remotes/origin/main",
            "create-main",
            "WAITING_ACK",
            "assignment ack",
        ):
            self.assertIn(marker, script)
        self.assertNotIn("WORKTREE_READY", script)
        contract = _read(CONTRACT)
        self.assertIn("MAIN_ASSIGNMENT_SCHEMA_VERSION = 2", contract)
        self.assertIn('"current"', contract)
        self.assertIn("current_assignment", contract)
        self.assertIn("unknown event or file", contract)

    def test_background_full_is_report_only_latest_main(self) -> None:
        workflow = _read(FULL)
        self.assertIn("push:\n    branches:\n      - main", workflow)
        self.assertIn("group: full-regression-main-latest", workflow)
        self.assertIn("cancel-in-progress: true", workflow)
        self.assertIn("headless-0", workflow)
        self.assertIn("headless-3", workflow)
        self.assertIn("native-0", workflow)
        self.assertIn("underwater_map_workbench/tools/build_underwater_map.py --check", workflow)
        self.assertIn("name: full-regression", workflow)
        self.assertNotIn("fast-green", workflow)
        self.assertNotIn("auto-revert", workflow.lower())
        self.assertNotIn("gh pr merge", workflow)

    def test_local_builder_is_sequential_immutable_and_promotes_only_pass(self) -> None:
        script = _read(SYNC)
        for marker in (
            "source-mirror.json",
            "queue",
            "builds",
            "current",
            "target_sha",
            "git-common-dir",
            "lfs",
            "fetch",
            "fsck",
            "export_presets.cfg",
            "--export-release",
            "-Full",
            "EXPORT_BOOTSTRAP_REQUIRED",
            "full-green",
            "alert",
            "Register-ScheduledTask",
        ):
            self.assertIn(marker, script)
        for forbidden in ("reset --hard", "clean -fd", "worktree remove --force"):
            self.assertNotIn(forbidden, script)

    def test_ard_0112_has_exact_provenance_and_symmetric_replacements(self) -> None:
        decisions = _read(DECISIONS)
        headers = re.findall(r"(?m)^## (ARD-[0-9]{4})\b", decisions)
        self.assertEqual(len(headers), len(set(headers)))
        ard_0112 = decisions.split("## ARD-0112", 1)[1]
        for marker in (
            "CI-S1A",
            "2026-08-27T21:42:01",
            "ARD-0110/calosc",
            "ARD-0108/D4,D9,D11",
            "ARD-0109/D1,D7,D9",
            "fast-green",
            "merge_group",
            "SQUASH",
            "OPENAI_API_KEY",
            "EXPORT_BOOTSTRAP_REQUIRED",
        ):
            self.assertIn(marker, ard_0112)
        ard_0108 = decisions.split("## ARD-0108", 1)[1].split("\n## ARD-", 1)[0]
        ard_0109 = decisions.split("## ARD-0109", 1)[1].split("\n## ARD-", 1)[0]
        self.assertIn("ARD-0112", ard_0108)
        self.assertIn("D4,D9,D11", ard_0108)
        self.assertIn("ARD-0112", ard_0109)
        self.assertIn("D1,D7,D9", ard_0109)
        self.assertNotIn("Zastąpiona w całości", ard_0109)

    def test_onboarding_and_architecture_match_the_same_boundary(self) -> None:
        combined = _read(README) + "\n" + _read(ARCHITECTURE)
        for marker in (
            "WAITING_ACK",
            "RUNNING",
            "App-owned `fast-green`",
            "Codex gate",
            "`merge_queue`",
            "squash",
            "immutable",
            "`current`",
            "EXPORT_BOOTSTRAP_REQUIRED",
        ):
            self.assertIn(marker, combined)
        for forbidden in (
            "manual-only",
            "ręczny merge",
            "bez assignmentu",
            "nie tworzy, nie odczytuje i nie zamyka assignmentu",
        ):
            self.assertNotIn(forbidden, combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
