from __future__ import annotations

import ast
import re
import shutil
import subprocess
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_ROOT = REPOSITORY_ROOT / ".github" / "workflows"
DECISIONS_PATH = REPOSITORY_ROOT / ".ai" / "DECISIONS.md"
PROTECTED_PATH_HELPER = REPOSITORY_ROOT / "tools" / "ci_protected_paths.py"
RUNNER_PATH = REPOSITORY_ROOT / "tests" / "run_all_tests.ps1"


def _workflow(name: str) -> str:
    return (WORKFLOW_ROOT / name).read_text(encoding="utf-8")


def _job(workflow: str, job_id: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        workflow,
    )
    if match is None:
        raise AssertionError(f"workflow job is missing: {job_id}")
    return match.group("body")


def _job_ids(workflow: str) -> list[str]:
    jobs = workflow.split("\njobs:\n", 1)
    if len(jobs) != 2:
        raise AssertionError("workflow must have one jobs mapping")
    return re.findall(r"(?m)^  ([A-Za-z0-9_-]+):\s*$", jobs[1])


def _job_name(job: str) -> str | None:
    match = re.search(r"(?m)^    name:\s*['\"]?([^'\"\r\n]+)['\"]?\s*$", job)
    return None if match is None else match.group(1).strip()


def _inline_protected_exact_paths(job: str) -> frozenset[str]:
    match = re.search(r"(?ms)\$exact\s*=\s*@\((?P<body>.*?)^\s*\)", job)
    if match is None:
        raise AssertionError("inline protected exact-path set is missing")
    return frozenset(re.findall(r'"([^"\r\n]+)"', match.group("body")))


def _literal_collection(module_path: Path, variable_name: str) -> frozenset[str]:
    module = ast.parse(module_path.read_text(encoding="utf-8"), filename=str(module_path))
    for node in module.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        if not any(
            isinstance(target, ast.Name) and target.id == variable_name
            for target in targets
        ):
            continue
        value = node.value
        if (
            isinstance(value, ast.Call)
            and isinstance(value.func, ast.Name)
            and value.func.id == "frozenset"
            and len(value.args) == 1
        ):
            value = value.args[0]
        return frozenset(ast.literal_eval(value))
    raise AssertionError(f"{variable_name} is missing from {module_path}")


class AgentIntegrationWorkflowTest(unittest.TestCase):
    maxDiff = None

    ATTESTER_ACTION = (
        "actions/create-github-app-token@"
        "bcd2ba49218906704ab6c1aa796996da409d3eb1"
    )

    def test_fast_branch_validation_is_read_only_and_covers_ci_control_plane(self) -> None:
        workflow = _workflow("agent-validation.yml")
        self.assertIn('branches:\n      - "codex/**"', workflow)
        self.assertRegex(workflow, r"(?m)^permissions:\n  contents: read\s*$")
        self.assertIn("cancel-in-progress: true", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("tools/workbench_contract.py --repo . eol-check", workflow)
        self.assertIn("tools/ci_branch_owner.py validate", workflow)
        self.assertIn('Get-Item -LiteralPath "tests/agent_integration_workflow_test.py"', workflow)
        self.assertIn('-Filter "ci_*_test.py"', workflow)
        self.assertIn("ReadToEndAsync()", workflow)
        self.assertIn("$running.Add", workflow)
        self.assertIn("$failures.Count -gt 0", workflow)
        self.assertLess(
            workflow.index("foreach ($entry in $running)"),
            workflow.index("$failures.Count -gt 0"),
        )
        self.assertNotRegex(workflow, r"(?m)^\s+(?:checks|contents|pull-requests): write\s*$")
        self.assertNotIn("run_all_tests.ps1", workflow)

    def test_default_branch_controller_is_checkout_free_auto_off_and_minimal(self) -> None:
        workflow = _workflow("agent-auto-integrator.yml")

        self.assertIn("repository_dispatch:", workflow)
        self.assertIn("- integrate-agent-handoff", workflow)
        self.assertIn("- complete-agent-handoff", workflow)
        self.assertNotIn("workflow_run:", workflow)
        self.assertNotIn("schedule:", workflow)
        self.assertNotRegex(workflow, r"(?m)^  push:")
        self.assertRegex(workflow, r"(?m)^permissions:\s*\{\}\s*$")
        self.assertNotIn("actions/checkout", workflow)
        uses = re.findall(r"(?mi)^\s*(?:-\s*)?uses\s*:\s*(\S+)", workflow)
        self.assertEqual([self.ATTESTER_ACTION], uses)

        admit = _job(workflow, "admit-handoff")
        merge = _job(workflow, "merge-handoff")
        self.assertIn("github.event.action == 'integrate-agent-handoff'", admit)
        self.assertIn("github.event.action == 'complete-agent-handoff'", merge)
        for job in (admit, merge):
            self.assertIn("vars.AUTO_INTEGRATOR_ENABLED == 'true'", job)

        self.assertRegex(
            admit,
            r"(?ms)^    permissions:\n"
            r"      checks: read\n"
            r"      contents: write\n"
            r"      pull-requests: read\s*$",
        )
        self.assertIn("environment: integration-attester", admit)
        self.assertIn(self.ATTESTER_ACTION, admit)
        self.assertIn("permission-checks: write", admit)
        self.assertIn("INTEGRATION_ATTESTER_PRIVATE_KEY", admit)
        self.assertNotIn("environment: integration-attester", merge)
        self.assertNotIn(self.ATTESTER_ACTION, merge)
        self.assertNotIn("permission-checks: write", merge)
        self.assertNotIn("permission-administration: write", workflow)
        self.assertNotIn("INTEGRATION_ATTESTER_PRIVATE_KEY", merge)
        self.assertNotIn("RULESET_AUDITOR_TOKEN", merge)
        self.assertRegex(
            merge,
            r"(?ms)^    permissions:\n"
            r"      checks: read\n"
            r"      contents: write\n"
            r"      pull-requests: write\s*$",
        )
        self.assertIn('action = "complete"', admit)
        self.assertIn('action = "reuse"', admit)
        self.assertIn('action = "queue"', admit)
        self.assertIn("$queued = $decision.check", admit)

        forbidden_processes = (
            "Invoke-Expression",
            "Start-Process",
            "git checkout",
            "git switch",
            "git merge",
            "git commit",
        )
        for forbidden in forbidden_processes:
            self.assertNotIn(forbidden, workflow)

    def test_trusted_preflight_binds_exact_base_head_and_trusted_helpers(self) -> None:
        workflow = _workflow("agent-integration.yml")
        preflight = _job(workflow, "trust-preflight")

        self.assertRegex(
            preflight,
            r"(?ms)^    permissions:\n"
            r"      checks: read\n"
            r"      contents: read\n"
            r"      pull-requests: read\s*$",
        )
        self.assertEqual(preflight.count("actions/checkout@"), 2)
        self.assertIn("path: trusted-control", preflight)
        self.assertIn("path: candidate", preflight)
        self.assertGreaterEqual(preflight.count("persist-credentials: false"), 2)
        self.assertIn("$trustedHead -cne $baseSha", preflight)
        self.assertIn("$candidateHead -cne $targetSha", preflight)
        self.assertIn("$currentMain.sha -cne $baseSha", preflight)
        self.assertIn("$pullRequest.base.sha -cne $baseSha", preflight)
        self.assertIn("$pullRequest.head.sha -cne $targetSha", preflight)
        self.assertIn('"handoff-v2:', preflight)
        self.assertIn(
            '(Join-Path $trustedRepository "tools/ci_protected_paths.py")', preflight
        )
        self.assertIn(
            '(Join-Path $trustedRepository "tools/ci_branch_owner.py")', preflight
        )
        self.assertIn(
            '(Join-Path $trustedRepository "tools/workbench_contract.py")', preflight
        )
        self.assertIn("--expected-head $targetSha", preflight)
        self.assertIn("--expected-base $baseSha", preflight)

        for dependent in (
            "infra-contracts",
            "prepare-godot",
            "prepare-lfs-plan",
            "shard",
            "aggregate-attestation",
        ):
            self.assertIn("- trust-preflight", _job(workflow, dependent))

    def test_only_one_custom_check_context_is_exposed(self) -> None:
        integration = _workflow("agent-integration.yml")
        controller = _workflow("agent-auto-integrator.yml")
        combined = integration + "\n" + controller

        for workflow in (integration, controller):
            for job_id in _job_ids(workflow):
                self.assertNotEqual("integration-green", job_id)
                self.assertNotEqual("integration-green", _job_name(_job(workflow, job_id)))

        required_check_values = set(
            re.findall(r'\$requiredCheck\s*=\s*"([^"\r\n]+)"', combined)
        )
        self.assertEqual({"integration-green"}, required_check_values)
        self.assertNotIn("Trusted integration gate", combined)
        self.assertNotIn("Trusted main audit", combined)

        admit = _job(controller, "admit-handoff")
        publisher = _job(integration, "publish-attestation")
        dispatcher = _job(integration, "dispatch-completion")
        merge = _job(controller, "merge-handoff")
        self.assertEqual(1, admit.count("New-AttesterCheckRun -Body"))
        self.assertEqual(
            1,
            len(re.findall(r'-Method POST -Path "[^"\n]*/check-runs"', publisher)),
        )
        self.assertEqual(
            2,
            len(re.findall(r'-Method PATCH -Path "[^"\n]*/check-runs/', publisher)),
        )
        self.assertNotRegex(
            dispatcher, r"-Method\s+(?:POST|PATCH)\s+[^\n]*/check-runs"
        )
        self.assertNotRegex(
            merge, r"-Method\s+(?:POST|PATCH)\s+[^\n]*/check-runs"
        )

        self.assertIn("$checkRunId", publisher)
        self.assertIn("$checkRunId", dispatcher)
        self.assertIn("[long]$check.app.id -ne $attesterAppId", dispatcher)

    def test_main_audit_has_one_automatic_trigger_and_reuses_its_check(self) -> None:
        integration = _workflow("agent-integration.yml")
        controller = _workflow("agent-auto-integrator.yml")
        publisher = _job(integration, "publish-attestation")
        merge = _job(controller, "merge-handoff")

        self.assertNotRegex(integration, r"(?m)^  push:")
        self.assertIn("- verify-integrated-main", integration)
        self.assertNotIn("workflow_dispatch:", integration)
        self.assertNotIn('GITHUB_EVENT_NAME -ceq "workflow_dispatch"', integration)
        self.assertIn(
            'throw "Only trusted repository_dispatch events may execute integration."',
            integration,
        )
        self.assertEqual(1, merge.count('event_type = "verify-integrated-main"'))
        self.assertIn("$existingResponse.check_runs", publisher)
        self.assertIn("$existing.Count -gt 0", publisher)
        self.assertIn(
            'Invoke-GitHubApi -Method PATCH -Path "/repos/$repository/check-runs/$checkRunId" -Body $checkBody',
            publisher,
        )

    def test_later_failed_main_audit_rejects_older_success(self) -> None:
        controller = _workflow("agent-auto-integrator.yml")
        functions = re.findall(
            r"(?ms)^          (function Get-SuccessfulMainAudit \{.*?"
            r"^          \})\n\n^          function ",
            controller,
        )
        self.assertEqual(2, len(functions))
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        base_sha = "1" * 40
        success_external = f"main-lkg-v2:{base_sha}:{'2' * 64}:{'3' * 64}"
        failed_external = f"main-lkg-v2:{base_sha}:failed:11"

        for function in functions:
            script = f'''\
$ErrorActionPreference = "Stop"
$requiredCheck = "integration-green"
$repository = "owner/repository"
$attesterAppId = 77L
function Invoke-GitHubApi {{
  return [pscustomobject]@{{ check_runs = @(
    [pscustomobject]@{{ id = 10L; name = "integration-green"; head_sha = "{base_sha}"; external_id = "{success_external}"; status = "completed"; conclusion = "success"; app = [pscustomobject]@{{ id = 77L }} }},
    [pscustomobject]@{{ id = 11L; name = "integration-green"; head_sha = "{base_sha}"; external_id = "{failed_external}"; status = "completed"; conclusion = "failure"; app = [pscustomobject]@{{ id = 77L }} }}
  ) }}
}}
{function}
$rejected = $false
try {{ [void](Get-SuccessfulMainAudit -BaseSha "{base_sha}") }}
catch {{
  if ($_.Exception.Message -like "*newest exact-main integration-green*not successful*") {{ $rejected = $true }}
  else {{ throw }}
}}
if (-not $rejected) {{ throw "Older success was accepted over a newer failure." }}
'''
            result = subprocess.run(
                [str(powershell), "-NoProfile", "-NonInteractive", "-Command", "-"],
                input=script,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_candidate_retry_does_not_replay_an_older_success(self) -> None:
        controller = _workflow("agent-auto-integrator.yml")
        match = re.search(
            r"(?ms)^          (function Get-CandidateFamilyDecision \{.*?"
            r"^          \})\n\n^          function Assert-StrictRuleset",
            controller,
        )
        self.assertIsNotNone(match)
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        base_sha = "1" * 40
        candidate_sha = "2" * 40
        pattern = (
            f"^candidate-v2:owner/repository:7:{base_sha}:{candidate_sha}:"
            "([0-9a-f]{64}):([0-9a-f]{64})$"
        )
        success_external = (
            f"candidate-v2:owner/repository:7:{base_sha}:{candidate_sha}:"
            f"{'3' * 64}:{'4' * 64}"
        )
        handoff_external = f"handoff-v2:7:{base_sha}:{candidate_sha}"
        script = f'''\
$ErrorActionPreference = "Stop"
$requiredCheck = "integration-green"
{match.group(1)}
$checks = @(
  [pscustomobject]@{{ id = 10L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{success_external}"; status = "completed"; conclusion = "success"; app = [pscustomobject]@{{ id = 77L }} }},
  [pscustomobject]@{{ id = 11L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{handoff_external}"; status = "completed"; conclusion = "failure"; app = [pscustomobject]@{{ id = 77L }} }}
)
$decision = Get-CandidateFamilyDecision -CheckRuns $checks -CandidateSha "{candidate_sha}" -CandidatePattern "{pattern}" -HandoffExternalId "{handoff_external}" -ExpectedAppId 77
if ($decision.action -cne "queue" -or [long]$decision.check.id -ne 11L) {{
  throw "Older candidate success was replayed over the newer failed handoff."
}}
'''
        result = subprocess.run(
            [str(powershell), "-NoProfile", "-NonInteractive", "-Command", "-"],
            input=script,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_merge_rejects_old_green_when_candidate_family_has_newer_red(self) -> None:
        merge = _job(_workflow("agent-auto-integrator.yml"), "merge-handoff")
        match = re.search(
            r"(?ms)^          (function Get-LatestCandidateFamilyCheck \{.*?"
            r"^          \})\n\n^          function Assert-StrictRuleset",
            merge,
        )
        self.assertIsNotNone(match)
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        base_sha = "1" * 40
        candidate_sha = "2" * 40
        pattern = (
            f"^candidate-v2:owner/repository:7:{base_sha}:{candidate_sha}:"
            "[0-9a-f]{64}:[0-9a-f]{64}$"
        )
        success_external = (
            f"candidate-v2:owner/repository:7:{base_sha}:{candidate_sha}:"
            f"{'3' * 64}:{'4' * 64}"
        )
        handoff_external = f"handoff-v2:7:{base_sha}:{candidate_sha}"
        script = f'''\
$ErrorActionPreference = "Stop"
$requiredCheck = "integration-green"
{match.group(1)}
$checks = @(
  [pscustomobject]@{{ id = 10L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{success_external}"; status = "completed"; conclusion = "success"; app = [pscustomobject]@{{ id = 77L }} }},
  [pscustomobject]@{{ id = 11L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{handoff_external}"; status = "completed"; conclusion = "failure"; app = [pscustomobject]@{{ id = 77L }} }}
)
$latest = Get-LatestCandidateFamilyCheck -CheckRuns $checks -CandidateSha "{candidate_sha}" -CandidatePattern "{pattern}" -HandoffExternalId "{handoff_external}" -ExpectedAppId 77
$payloadCheckRunId = 10L
if ([long]$latest.id -eq $payloadCheckRunId) {{ throw "Old green payload remained mergeable." }}
if ([long]$latest.id -ne 11L) {{ throw "Newest candidate-family check was not selected." }}
'''
        result = subprocess.run(
            [str(powershell), "-NoProfile", "-NonInteractive", "-Command", "-"],
            input=script,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_v2_external_ids_use_only_fresh_ci_receipt_hashes(self) -> None:
        integration = _workflow("agent-integration.yml")
        controller = _workflow("agent-auto-integrator.yml")
        combined = integration + "\n" + controller
        admit = _job(controller, "admit-handoff")
        aggregate = _job(integration, "aggregate-attestation")
        publisher = _job(integration, "publish-attestation")

        self.assertNotRegex(
            admit,
            r"github\.event\.client_payload\.[A-Za-z0-9_]*receipt[A-Za-z0-9_]*",
        )
        self.assertNotIn("BASE_CANDIDATE_RECEIPT_SHA256", admit)
        self.assertNotIn("BASE_FULL_RUN_RECEIPT_SHA256", admit)
        self.assertNotIn("FULL_RUN_RECEIPT_SHA256", admit)
        self.assertIn("Fresh receipt hashes are created only by CI", admit)

        self.assertIn("Hash the fresh verified receipt pair", aggregate)
        self.assertIn("candidate-receipt-sha256=$candidateSha", aggregate)
        self.assertIn("aggregate-receipt-sha256=$aggregateSha", aggregate)
        self.assertIn(
            "needs.aggregate-attestation.outputs.candidate-receipt-sha256",
            publisher,
        )
        self.assertIn(
            "needs.aggregate-attestation.outputs.aggregate-receipt-sha256",
            publisher,
        )
        self.assertRegex(
            publisher,
            r"candidate-v2:[^\"\r\n]*\$candidateReceiptSha[^\"\r\n]*\$aggregateReceiptSha",
        )
        self.assertRegex(
            publisher,
            r"main-lkg-v2:[^\"\r\n]*\$candidateReceiptSha[^\"\r\n]*\$aggregateReceiptSha",
        )
        self.assertRegex(
            admit,
            r"candidate-v2:[^\"\r\n]*\(\[0-9a-f\]\{64\}\):"
            r"\(\[0-9a-f\]\{64\}\)\$",
        )
        for obsolete in (
            "handoff-v1:",
            "candidate-v1:",
            "main-audit-v1:",
            "main-lkg-v1:",
        ):
            self.assertNotIn(obsolete, combined)

    def test_four_headless_one_native_and_central_lfs_plan(self) -> None:
        workflow = _workflow("agent-integration.yml")
        plan = _job(workflow, "prepare-lfs-plan")
        shard = _job(workflow, "shard")

        self.assertIn('HEADLESS_SHARD_COUNT: "4"', workflow)
        self.assertIn('NATIVE_SHARD_COUNT: "1"', workflow)
        shard_ids = re.findall(
            r"(?m)^          - (headless-[0-9]+|native-[0-9]+)\s*$", shard
        )
        self.assertEqual(
            ["headless-0", "headless-1", "headless-2", "headless-3", "native-0"],
            shard_ids,
        )
        self.assertIn("-HeadlessShardCount $env:HEADLESS_SHARD_COUNT", plan)
        self.assertIn("-NativeShardCount $env:NATIVE_SHARD_COUNT", plan)
        self.assertIn("-WriteShardPlan $shardPlan", plan)

        self.assertIn('(Join-Path $trustedRoot "tools/ci_lfs.py") manifest', plan)
        self.assertIn("git -C $candidateRoot lfs fetch origin $exactHead", plan)
        self.assertIn("actions/cache@", plan)
        self.assertIn("verify-cache", plan)
        self.assertIn("verify-worktree", plan)
        self.assertIn("candidate-receipt.json", plan)
        self.assertIn("shard-plan.receipt", plan)

        self.assertIn("actions/cache/restore@", shard)
        self.assertIn("fail-on-cache-miss: true", shard)
        self.assertNotIn("git lfs fetch", shard)
        self.assertNotRegex(shard, r"uses:\s*actions/cache@(?!/restore)")
        self.assertIn("-ShardPlan $planPath", shard)
        self.assertIn('-ShardId "${{ matrix.shard_id }}"', shard)
        self.assertIn("-RunReceiptOutputPath $receiptPath", shard)

    def test_artifacts_are_bound_by_exact_id_digest_and_run(self) -> None:
        workflow = _workflow("agent-integration.yml")
        plan = _job(workflow, "prepare-lfs-plan")
        shard = _job(workflow, "shard")
        aggregate = _job(workflow, "aggregate-attestation")

        self.assertEqual(3, workflow.count("actions/download-artifact@"))
        self.assertEqual(3, workflow.count("artifact-ids:"))
        self.assertNotRegex(workflow, r"(?m)^\s+(?:pattern|merge-multiple):")
        self.assertIn("plan-artifact-id: ${{ steps.plan-artifact.outputs.artifact-id }}", plan)
        self.assertIn(
            "plan-artifact-digest: ${{ steps.plan-artifact.outputs.artifact-digest }}",
            plan,
        )

        for job in (shard, aggregate):
            self.assertIn("workflow_run.id", job)
            self.assertIn(".digest", job)
            self.assertIn("expired", job)
        self.assertIn("EXPECTED_ARTIFACT_ID", shard)
        self.assertIn("EXPECTED_ARTIFACT_DIGEST", shard)
        self.assertIn("EXPECTED_PLAN_ARTIFACT_ID", aggregate)
        self.assertIn("EXPECTED_PLAN_ARTIFACT_DIGEST", aggregate)
        self.assertIn("$expectedNames", aggregate)
        self.assertIn("$matches.Count -ne 1", aggregate)
        self.assertIn("artifact-ids=$([string]::Join(',',", aggregate)

    def test_aggregate_is_always_fail_closed_and_exact(self) -> None:
        workflow = _workflow("agent-integration.yml")
        aggregate = _job(workflow, "aggregate-attestation")
        publisher = _job(workflow, "publish-attestation")

        self.assertRegex(aggregate, r"(?m)^    if: \$\{\{ always\(\) \}\}\s*$")
        for dependency in (
            "trust-preflight",
            "infra-contracts",
            "prepare-godot",
            "prepare-lfs-plan",
            "shard",
        ):
            self.assertIn(f"- {dependency}", aggregate)
        self.assertIn("CI_NEEDS_JSON: ${{ toJSON(needs) }}", aggregate)
        self.assertIn('(Join-Path $trustedRoot "tools/ci_job_gate.py") verify-needs', aggregate)
        self.assertIn("-AggregateShardReceipt", aggregate)
        self.assertIn("-VerifyRunReceipt $aggregateReceipt", aggregate)
        self.assertIn("-CandidateReceipt $candidateReceipt", aggregate)
        self.assertIn("canonical_sha256=([0-9a-f]{64})", aggregate)
        self.assertIn("candidate-receipt-sha256", aggregate)
        self.assertIn("aggregate-receipt-sha256", aggregate)
        self.assertIn("actions/cache/restore@", aggregate)
        self.assertNotIn("git lfs fetch", aggregate)

        self.assertRegex(publisher, r"(?m)^    if: \$\{\{ always\(\) \}\}\s*$")
        self.assertIn("AGGREGATE_RESULT", publisher)
        self.assertIn("$allSucceeded", publisher)
        self.assertIn('throw "Trusted integration attestation failed', publisher)

    def test_candidate_startup_hooks_cannot_control_plan_shards_or_aggregate(self) -> None:
        workflow = _workflow("agent-integration.yml")
        runner = RUNNER_PATH.read_text(encoding="utf-8")

        for job_id in (
            "infra-contracts",
            "prepare-lfs-plan",
            "shard",
            "aggregate-attestation",
        ):
            job = _job(workflow, job_id)
            self.assertIn("path: trusted-control", job)
            self.assertIn("path: candidate", job)
            self.assertIn("needs.trust-preflight.outputs.base-sha", job)
            self.assertIn("needs.trust-preflight.outputs.target-sha", job)
            self.assertNotIn("python -B", job)
            self.assertNotRegex(job, r'@\(\s*"-B"')

        for job_id in ("prepare-lfs-plan", "shard", "aggregate-attestation"):
            job = _job(workflow, job_id)
            self.assertIn('(Join-Path $trustedRoot "tests/run_all_tests.ps1")', job)
            self.assertIn("-SourceRepositoryPath $candidateRoot", job)
            self.assertNotIn('-File tests/run_all_tests.ps1', job)

        aggregate = _job(workflow, "aggregate-attestation")
        self.assertNotIn("-GodotConsolePath", aggregate)
        self.assertNotIn("Run isolated shard", aggregate)
        self.assertIn("-I -B", aggregate)

        python_switches = re.findall(r'"-I",\s*"-B"', runner)
        self.assertEqual(4, len(python_switches))
        self.assertEqual(4, runner.count('"-B"'))
        self.assertIn("[string]$SourceRepositoryPath", runner)

    def test_publisher_and_dispatcher_have_no_checkout_or_candidate_execution(self) -> None:
        workflow = _workflow("agent-integration.yml")
        publisher = _job(workflow, "publish-attestation")
        dispatcher = _job(workflow, "dispatch-completion")

        for job in (publisher, dispatcher):
            self.assertNotIn("actions/checkout", job)
            self.assertNotIn("git checkout", job)
            self.assertNotIn("tests/run_all_tests.ps1", job)

        publisher_uses = re.findall(
            r"(?mi)^\s*(?:-\s*)?uses\s*:\s*(\S+)", publisher
        )
        self.assertEqual([self.ATTESTER_ACTION], publisher_uses)
        self.assertNotRegex(dispatcher, r"(?mi)^\s*(?:-\s*)?uses\s*:")

        self.assertRegex(
            publisher,
            r"(?m)^    permissions:\s*\{\}\s*$",
        )
        self.assertIn("environment: integration-attester", publisher)
        self.assertIn("permission-checks: write", publisher)
        self.assertIn("INTEGRATION_ATTESTER_PRIVATE_KEY", publisher)
        self.assertRegex(
            dispatcher,
            r"(?ms)^    permissions:\n      checks: read\n      contents: write\s*$",
        )
        self.assertIn("needs.publish-attestation.result == 'success'", dispatcher)
        self.assertIn('$check.status -cne "completed"', dispatcher)
        self.assertIn('$check.conclusion -cne "success"', dispatcher)
        self.assertIn("INTEGRATION_ATTESTER_APP_ID", dispatcher)
        self.assertNotIn("INTEGRATION_ATTESTER_PRIVATE_KEY", dispatcher)

    def test_protected_paths_caps_and_ruleset_source_are_consistent(self) -> None:
        controller = _workflow("agent-auto-integrator.yml")
        integration = _workflow("agent-integration.yml")
        admit = _job(controller, "admit-handoff")
        merge = _job(controller, "merge-handoff")

        inline_admit = frozenset(
            path.casefold() for path in _inline_protected_exact_paths(admit)
        )
        inline_merge = frozenset(
            path.casefold() for path in _inline_protected_exact_paths(merge)
        )
        helper_exact = _literal_collection(PROTECTED_PATH_HELPER, "PROTECTED_EXACT_PATHS")
        self.assertEqual(helper_exact, inline_admit)
        self.assertEqual(inline_admit, inline_merge)
        self.assertIn("underwater_map_workbench/tools/build_underwater_map.py", helper_exact)

        for job in (admit, merge):
            self.assertIn('.StartsWith(".github/"', job)
            self.assertIn('.StartsWith(".githooks/"', job)
            self.assertIn('.StartsWith("tools/ci_"', job)
            self.assertIn('.StartsWith("tests/ci_"', job)
            self.assertRegex(job, r"(?:-gt|exceeds).*3000|3000-file")
            self.assertIn("page -ge 30", job.lower())
            self.assertIn("strict_required_status_checks_policy", job)
            self.assertIn("required_status_checks", job)
            self.assertIn("integration_id", job)
            self.assertNotIn("bypass_actors", job)
            self.assertIn("refs/heads/main", job)
            self.assertIn("INTEGRATION_ATTESTER_APP_ID", job)
            self.assertIn("app.id", job)
            self.assertNotIn("app.slug", job)

        preflight = _job(integration, "trust-preflight")
        self.assertIn("tools/ci_protected_paths.py", preflight)
        self.assertIn("validate-diff", preflight)
        self.assertIn("INTEGRATION_ATTESTER_APP_ID", preflight)
        self.assertIn("app.id", preflight)
        self.assertNotIn("app.slug", preflight)

        combined = controller + "\n" + integration
        self.assertNotRegex(combined, r"(?m)^\s+checks:\s*write\s*$")
        self.assertEqual(2, combined.count(self.ATTESTER_ACTION))
        self.assertEqual(2, combined.count("environment: integration-attester"))
        self.assertEqual(2, combined.count("INTEGRATION_ATTESTER_PRIVATE_KEY"))
        self.assertNotIn("permission-administration: write", combined)
        self.assertEqual(2, combined.count("permission-checks: write"))
        self.assertNotRegex(combined, r"(?m)^\s+(?:owner|repositories):")
        self.assertNotIn("github-actions", combined)

    def test_ard_headers_are_unique_and_trusted_ci_is_final_ard_0110(self) -> None:
        decisions = DECISIONS_PATH.read_text(encoding="utf-8")
        headers = re.findall(r"(?m)^## ARD-(\d{4})\s+-\s+(.+?)\s*$", decisions)
        self.assertTrue(headers, "DECISIONS.md has no ARD headers")
        identifiers = [identifier for identifier, _title in headers]
        duplicates = sorted(
            identifier
            for identifier in set(identifiers)
            if identifiers.count(identifier) > 1
        )
        self.assertEqual([], duplicates, f"duplicate ARD identifiers: {duplicates}")
        self.assertEqual("0110", identifiers[-1])
        self.assertRegex(headers[-1][1].lower(), r"integr|github|zauf")
        self.assertNotIn("Trusted integration gate", decisions)
        self.assertNotIn("Trusted main audit", decisions)


if __name__ == "__main__":
    unittest.main(verbosity=2)
