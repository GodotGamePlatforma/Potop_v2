from __future__ import annotations

import ast
import json
import os
import re
import shutil
import subprocess
import tempfile
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

    def test_auto_integrator_accepts_real_compare_shape_and_binds_exact_head(self) -> None:
        controller = _workflow("agent-auto-integrator.yml")
        admit = _job(controller, "admit-handoff")
        merge = _job(controller, "merge-handoff")
        functions = re.findall(
            r"(?ms)^          (function Assert-ExactComparison \{.*?"
            r"^          \})\n\n^          function Test-IsProtectedPath",
            controller,
        )
        self.assertEqual(2, len(functions))
        self.assertNotIn("head_commit.sha", controller)
        exact_commit_lookup = (
            'Invoke-GitHubApi -Method GET -Path '
            '"/repos/$repository/commits/$($env:CANDIDATE_SHA)"'
        )
        for job in (admit, merge):
            self.assertEqual(1, job.count(exact_commit_lookup))
            self.assertEqual(1, job.count("Assert-ExactComparison `"))

        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        base_sha = "1" * 40
        candidate_sha = "2" * 40
        other_sha = "3" * 40
        for function in functions:
            script = f'''\
$ErrorActionPreference = "Stop"
{function}
$baseSha = "{base_sha}"
$candidateSha = "{candidate_sha}"
$comparison = [pscustomobject]@{{
  status = "ahead"
  ahead_by = 2
  behind_by = 0
  total_commits = 2
  base_commit = [pscustomobject]@{{ sha = $baseSha }}
  merge_base_commit = [pscustomobject]@{{ sha = $baseSha }}
  head_commit = $null
  commits = @(
    [pscustomobject]@{{ sha = "{other_sha}" }},
    [pscustomobject]@{{ sha = $candidateSha }}
  )
}}
$candidateCommit = [pscustomobject]@{{ sha = $candidateSha }}
Assert-ExactComparison -Comparison $comparison -CandidateCommit $candidateCommit -ExpectedBase $baseSha -ExpectedHead $candidateSha -FailureMessage "valid comparison rejected"

$rejected = $false
try {{
  Assert-ExactComparison -Comparison $comparison -CandidateCommit ([pscustomobject]@{{ sha = "{other_sha}" }}) -ExpectedBase $baseSha -ExpectedHead $candidateSha -FailureMessage "reject"
}}
catch {{
  if ($_.Exception.Message -ceq "reject") {{ $rejected = $true }} else {{ throw }}
}}
if (-not $rejected) {{ throw "A different candidate commit was accepted." }}

$inconsistent = [pscustomobject]@{{
  status = "ahead"
  ahead_by = 2
  behind_by = 0
  total_commits = 1
  base_commit = [pscustomobject]@{{ sha = $baseSha }}
  merge_base_commit = [pscustomobject]@{{ sha = $baseSha }}
  head_commit = $null
  commits = @([pscustomobject]@{{ sha = $candidateSha }})
}}
$rejected = $false
try {{
  Assert-ExactComparison -Comparison $inconsistent -CandidateCommit $candidateCommit -ExpectedBase $baseSha -ExpectedHead $candidateSha -FailureMessage "reject"
}}
catch {{
  if ($_.Exception.Message -ceq "reject") {{ $rejected = $true }} else {{ throw }}
}}
if (-not $rejected) {{ throw "An inconsistent comparison count was accepted." }}
'''
            result = subprocess.run(
                [str(powershell), "-NoProfile", "-NonInteractive", "-Command", "-"],
                input=script,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

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
            "map-authority-check",
            "shard",
            "aggregate-attestation",
        ):
            self.assertIn("- trust-preflight", _job(workflow, dependent))

    def test_only_one_custom_check_context_is_exposed(self) -> None:
        integration = _workflow("agent-integration.yml")
        controller = _workflow("agent-auto-integrator.yml")
        maintenance = _workflow("map-control-plane-maintenance.yml")
        combined = integration + "\n" + controller + "\n" + maintenance

        for workflow in (integration, controller, maintenance):
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
        authorize = _job(maintenance, "authorize")
        publisher = _job(integration, "publish-attestation")
        dispatcher = _job(integration, "dispatch-completion")
        merge = _job(controller, "merge-handoff")
        self.assertEqual(1, admit.count("New-AttesterCheckRun -Body"))
        self.assertEqual(1, authorize.count('-Uri "https://api.github.com/repos/$repository/check-runs"'))
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

    def test_map_control_plane_maintenance_is_manual_narrow_and_never_automerge(self) -> None:
        workflow = _workflow("map-control-plane-maintenance.yml")
        integration = _workflow("agent-integration.yml")
        controller = _workflow("agent-auto-integrator.yml")
        inspect = _job(workflow, "inspect")
        authorize = _job(workflow, "authorize")
        post_merge = _job(workflow, "audit-merged-main")

        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("pull_request:", workflow)
        self.assertIn("- closed", workflow)
        self.assertIn(
            "group: map-control-plane-authorize-${{ needs.inspect.outputs.pr-number }}-${{ needs.inspect.outputs.candidate-sha }}-${{ needs.inspect.outputs.authorization-sha256 }}",
            authorize,
        )
        self.assertIn(
            "group: map-control-plane-audit-${{ github.event.pull_request.number }}-${{ github.event.pull_request.head.sha }}",
            post_merge,
        )
        self.assertNotIn("group: map-control-plane-maintenance\n", workflow)
        self.assertNotIn("authorize-map-control-plane-maintenance", workflow)
        self.assertRegex(workflow, r"(?m)^permissions:\s*\{\}\s*$")
        self.assertNotIn("\n  request:\n", workflow)
        self.assertIn("ref: ${{ inputs.base_sha }}", inspect)
        self.assertIn("ref: ${{ inputs.candidate_sha }}", inspect)
        self.assertGreaterEqual(inspect.count("persist-credentials: false"), 2)
        self.assertNotIn('GITHUB_ACTOR -cne "github-actions[bot]"', inspect)
        self.assertIn("validate-map-maintenance-diff", inspect)
        self.assertIn("tools/ci_branch_owner.py", inspect)
        self.assertIn("tools/ci_python_entry.py", inspect)
        self.assertIn("--cwd $neutralCwd", inspect)
        self.assertIn("--path-executable $trustedGit", inspect)
        self.assertIn("CI_TRUSTED_GIT", inspect)
        self.assertIn("control-plane-reviewed", inspect)
        self.assertIn("map-control-plane-authorization-v1", inspect)

        self.assertIn("environment: control-plane-maintenance", authorize)
        self.assertIn("actions: read", authorize)
        self.assertIn(self.ATTESTER_ACTION, authorize)
        self.assertIn("permission-checks: write", authorize)
        self.assertIn("required_reviewers", authorize)
        self.assertIn("prevent_self_review", authorize)
        self.assertIn("repositoryOwner", authorize)
        self.assertIn("permit an explicit self-review", authorize)
        self.assertIn('event_type = "verify-map-control-plane-candidate"', authorize)
        self.assertIn('name = $requiredCheck', authorize)
        self.assertIn('$decision.action -ceq "dispatch"', authorize)
        self.assertIn('manual retry creates a newer Check Run', authorize)
        self.assertNotIn("$certified", authorize)
        self.assertNotIn('$family[0].status -ceq "in_progress"', authorize)
        self.assertIn('status = "in_progress"', authorize)
        self.assertLess(
            authorize.index('event_type = "verify-map-control-plane-candidate"'),
            authorize.index('status = "in_progress"'),
        )
        self.assertNotIn("actions/checkout", authorize)
        self.assertNotIn("git ", authorize)
        self.assertNotRegex(authorize, r"/pulls/[^\r\n]*/merge")
        self.assertNotIn("-Method PUT", authorize)
        self.assertNotIn("merge_method", authorize)
        self.assertNotIn("AUTO_INTEGRATOR_ENABLED", workflow)
        self.assertNotIn("complete-agent-handoff", workflow)
        self.assertNotIn("verify-map-control-plane-candidate", controller)
        self.assertIn("github.event.pull_request.merged == true", post_merge)
        self.assertIn(
            "startsWith(github.event.pull_request.head.ref, 'codex/map/')",
            post_merge,
        )
        self.assertIn(
            "contains(github.event.pull_request.labels.*.name, "
            "'control-plane-reviewed')",
            post_merge,
        )
        self.assertIn(
            "Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw",
            post_merge,
        )
        self.assertNotIn(
            "$env:GITHUB_EVENT_PATH | Get-Content",
            post_merge,
        )
        self.assertIn("control-plane-v2:", post_merge)
        self.assertIn("control-plane-handoff-v1:", post_merge)
        self.assertIn("one to three unique, non-renamed files", post_merge)
        self.assertIn("Sort-Object -Property @{ Expression = { [long]$_.id } } -Descending", post_merge)
        self.assertIn('$family[0].status -cne "completed"', post_merge)
        self.assertIn('event_type = "verify-integrated-main"', post_merge)
        self.assertIn("merge_base_commit.sha", post_merge)
        self.assertNotRegex(post_merge, r"/pulls/[^\r\n]*/merge")
        self.assertNotIn("merge_method", post_merge)

        preflight = _job(integration, "trust-preflight")
        map_check = _job(integration, "map-authority-check")
        aggregate = _job(integration, "aggregate-attestation")
        publisher = _job(integration, "publish-attestation")
        dispatcher = _job(integration, "dispatch-completion")
        self.assertIn("- verify-map-control-plane-candidate", integration)
        self.assertIn("validate-map-maintenance-diff", preflight)
        self.assertIn("control-plane-handoff-v1", preflight)
        self.assertIn("map-control-plane-authorization-v1", preflight)
        self.assertIn("Authorized map verifier hashes differ", preflight)
        self.assertIn("authorization-sha256=$authorizationSha", preflight)
        self.assertIn("AUTHORIZED_BUILDER_SHA256", map_check)
        self.assertIn("--authorization-sha256 $env:AUTHORIZATION_SHA256", map_check)
        self.assertIn("--authorization-sha256 $env:AUTHORIZATION_SHA256", aggregate)
        self.assertIn("control-plane-receipt-set-v1", publisher)
        self.assertIn("control-plane-v2:$pullNumber", publisher)
        self.assertIn('needs.publish-attestation.outputs.mode == \'candidate\'', dispatcher)

        exact_paths = _literal_collection(
            PROTECTED_PATH_HELPER, "MAP_MAINTENANCE_EXACT_PATHS"
        )
        self.assertEqual(
            {
                "underwater_map_workbench/tools/build_underwater_map.py",
                "underwater_map_workbench/tests/portal_backdrop_clearance_test.py",
                "underwater_map_workbench/tests/underwater_map_smoke_test.gd",
            },
            exact_paths,
        )

    def test_map_maintenance_post_merge_reads_the_real_event_file(self) -> None:
        post_merge = _job(
            _workflow("map-control-plane-maintenance.yml"), "audit-merged-main"
        )
        parser = re.search(
            r"(?m)^\s*(\$pull = Get-Content -LiteralPath "
            r"\$env:GITHUB_EVENT_PATH -Raw \| ConvertFrom-Json \| "
            r"Select-Object -ExpandProperty pull_request)\s*$",
            post_merge,
        )
        self.assertIsNotNone(parser, "exact event-file parser is missing")
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        payload = {
            "pull_request": {
                "number": 17,
                "merged": True,
                "head": {"ref": "codex/map/verifier-fix"},
            }
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            event_path = Path(temporary_directory) / "event.json"
            event_path.write_text(json.dumps(payload), encoding="utf-8")
            environment = os.environ.copy()
            environment["GITHUB_EVENT_PATH"] = str(event_path)
            script = "\n".join(
                (
                    '$ErrorActionPreference = "Stop"',
                    parser.group(1),
                    'if ([int]$pull.number -ne 17) { throw "event parse mismatch" }',
                )
            )
            result = subprocess.run(
                [str(powershell), "-NoProfile", "-NonInteractive", "-Command", "-"],
                input=script,
                text=True,
                capture_output=True,
                env=environment,
                check=False,
            )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_map_maintenance_post_merge_requires_the_review_label(self) -> None:
        post_merge = _job(
            _workflow("map-control-plane-maintenance.yml"), "audit-merged-main"
        )
        eligibility = re.search(r"(?m)^\s*if:\s*(.+)$", post_merge)
        self.assertIsNotNone(eligibility, "post-merge job eligibility is missing")
        condition = eligibility.group(1)
        self.assertIn("github.event.pull_request.merged == true", condition)
        self.assertIn(
            "startsWith(github.event.pull_request.head.ref, 'codex/map/')",
            condition,
        )
        self.assertIn(
            "contains(github.event.pull_request.labels.*.name, "
            "'control-plane-reviewed')",
            condition,
        )

        def qualifies(*, merged: bool, branch: str, labels: set[str]) -> bool:
            return (
                merged
                and branch.startswith("codex/map/")
                and "control-plane-reviewed" in labels
            )

        self.assertFalse(
            qualifies(merged=True, branch="codex/map/ordinary-art", labels=set()),
            "An ordinary merged map PR must leave the maintenance job skipped.",
        )
        self.assertTrue(
            qualifies(
                merged=True,
                branch="codex/map/verifier-fix",
                labels={"control-plane-reviewed"},
            ),
            "A reviewed maintenance PR must qualify for the exact-main audit.",
        )

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
        success_external = f"main-lkg-v3:{base_sha}:{'2' * 64}"
        failed_external = f"main-lkg-v3:{base_sha}:failed:11"

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
            f"^candidate-v3:owner/repository:7:{base_sha}:{candidate_sha}:"
            "([0-9a-f]{64})$"
        )
        success_external = (
            f"candidate-v3:owner/repository:7:{base_sha}:{candidate_sha}:"
            f"{'3' * 64}"
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

    def test_maintenance_retry_uses_only_newest_family_and_recovers_stale_lease(self) -> None:
        authorize = _job(_workflow("map-control-plane-maintenance.yml"), "authorize")
        match = re.search(
            r"(?ms)^          (function Get-MaintenanceFamilyDecision \{.*?"
            r"^          \})\n^          \$encodedCheck",
            authorize,
        )
        self.assertIsNotNone(match)
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        candidate_sha = "2" * 40
        handoff_external = (
            f"control-plane-handoff-v1:7:{'1' * 40}:{candidate_sha}:{'3' * 64}"
        )
        success_pattern = (
            f"^control-plane-v2:7:{'1' * 40}:{candidate_sha}:{'3' * 64}:"
            "[0-9a-f]{64}$"
        )
        family_handoff_pattern = (
            f"^control-plane-handoff-v1:7:{'1' * 40}:{candidate_sha}:"
            "[0-9a-f]{64}$"
        )
        family_success_pattern = (
            f"^control-plane-v2:7:{'1' * 40}:{candidate_sha}:"
            "[0-9a-f]{64}:[0-9a-f]{64}$"
        )
        success_external = (
            f"control-plane-v2:7:{'1' * 40}:{candidate_sha}:{'3' * 64}:"
            f"{'4' * 64}"
        )
        script = f'''\
$ErrorActionPreference = "Stop"
$requiredCheck = "integration-green"
{match.group(1)}
$olderSuccessNewerFailure = @(
  [pscustomobject]@{{ id = 10L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{success_external}"; status = "completed"; conclusion = "success"; app = [pscustomobject]@{{ id = 77L }} }},
  [pscustomobject]@{{ id = 11L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{handoff_external}"; status = "completed"; conclusion = "failure"; app = [pscustomobject]@{{ id = 77L }} }}
)
$failed = Get-MaintenanceFamilyDecision -CheckRuns $olderSuccessNewerFailure -CandidateSha "{candidate_sha}" -HandoffExternalId "{handoff_external}" -SuccessPattern "{success_pattern}" -FamilyHandoffPattern "{family_handoff_pattern}" -FamilySuccessPattern "{family_success_pattern}" -ExpectedAppId 77
if ($failed.action -cne "queue" -or $null -ne $failed.check) {{ throw "Older success was replayed over newer maintenance failure." }}

$staleLease = @(
  [pscustomobject]@{{ id = 12L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{handoff_external}"; status = "in_progress"; conclusion = $null; app = [pscustomobject]@{{ id = 77L }} }}
)
$stale = Get-MaintenanceFamilyDecision -CheckRuns $staleLease -CandidateSha "{candidate_sha}" -HandoffExternalId "{handoff_external}" -SuccessPattern "{success_pattern}" -FamilyHandoffPattern "{family_handoff_pattern}" -FamilySuccessPattern "{family_success_pattern}" -ExpectedAppId 77
if ($stale.action -cne "queue" -or $null -ne $stale.check) {{ throw "Stale maintenance lease was not recoverable." }}

$queuedLease = @(
  [pscustomobject]@{{ id = 13L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{handoff_external}"; status = "queued"; conclusion = $null; app = [pscustomobject]@{{ id = 77L }} }}
)
$queued = Get-MaintenanceFamilyDecision -CheckRuns $queuedLease -CandidateSha "{candidate_sha}" -HandoffExternalId "{handoff_external}" -SuccessPattern "{success_pattern}" -FamilyHandoffPattern "{family_handoff_pattern}" -FamilySuccessPattern "{family_success_pattern}" -ExpectedAppId 77
if ($queued.action -cne "dispatch" -or [long]$queued.check.id -ne 13L) {{ throw "Queued crash-window lease was not redispatched." }}

$newestSuccess = @(
  [pscustomobject]@{{ id = 14L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{success_external}"; status = "completed"; conclusion = "success"; app = [pscustomobject]@{{ id = 77L }} }}
)
$complete = Get-MaintenanceFamilyDecision -CheckRuns $newestSuccess -CandidateSha "{candidate_sha}" -HandoffExternalId "{handoff_external}" -SuccessPattern "{success_pattern}" -FamilyHandoffPattern "{family_handoff_pattern}" -FamilySuccessPattern "{family_success_pattern}" -ExpectedAppId 77
if ($complete.action -cne "certified" -or [long]$complete.check.id -ne 14L) {{ throw "Newest successful maintenance family was not accepted." }}

$otherAuthorization = "{'5' * 64}"
$otherHandoff = "control-plane-handoff-v1:7:{'1' * 40}:{candidate_sha}:$otherAuthorization"
$newerOtherAuthorization = @(
  [pscustomobject]@{{ id = 14L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = "{success_external}"; status = "completed"; conclusion = "success"; app = [pscustomobject]@{{ id = 77L }} }},
  [pscustomobject]@{{ id = 15L; name = "integration-green"; head_sha = "{candidate_sha}"; external_id = $otherHandoff; status = "queued"; conclusion = $null; app = [pscustomobject]@{{ id = 77L }} }}
)
$other = Get-MaintenanceFamilyDecision -CheckRuns $newerOtherAuthorization -CandidateSha "{candidate_sha}" -HandoffExternalId "{handoff_external}" -SuccessPattern "{success_pattern}" -FamilyHandoffPattern "{family_handoff_pattern}" -FamilySuccessPattern "{family_success_pattern}" -ExpectedAppId 77
if ($other.action -cne "queue" -or $null -ne $other.check) {{ throw "A newer different authorization did not fence an older success." }}
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
            f"^candidate-v3:owner/repository:7:{base_sha}:{candidate_sha}:"
            "[0-9a-f]{64}$"
        )
        success_external = (
            f"candidate-v3:owner/repository:7:{base_sha}:{candidate_sha}:"
            f"{'3' * 64}"
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

    def test_v3_external_ids_bind_candidate_aggregate_and_map_receipts(self) -> None:
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

        self.assertIn("Hash the fresh verified receipt set", aggregate)
        self.assertIn("candidate-receipt-sha256=$candidateSha", aggregate)
        self.assertIn("aggregate-receipt-sha256=$aggregateSha", aggregate)
        self.assertIn("map-receipt-sha256=$mapSha", aggregate)
        self.assertIn("integration-receipt-set-v1", aggregate)
        self.assertIn("candidate=$candidateSha", aggregate)
        self.assertIn("aggregate=$aggregateSha", aggregate)
        self.assertIn("map=$mapSha", aggregate)
        self.assertIn("receipt-set-sha256=$receiptSetSha", aggregate)
        self.assertIn("$aggregateCanonicalSha = $Matches[1]", aggregate)
        self.assertIn("aggregate-canonical-sha256=$aggregateCanonicalSha", aggregate)
        self.assertIn(
            "needs.aggregate-attestation.outputs.candidate-receipt-sha256",
            publisher,
        )
        self.assertIn(
            "needs.aggregate-attestation.outputs.aggregate-receipt-sha256",
            publisher,
        )
        self.assertIn(
            "needs.aggregate-attestation.outputs.map-receipt-sha256",
            publisher,
        )
        self.assertIn(
            "needs.aggregate-attestation.outputs.receipt-set-sha256",
            publisher,
        )
        self.assertIn("$recomputedReceiptSetSha", publisher)
        self.assertIn("Receipt-set commitment does not match", publisher)
        self.assertRegex(
            publisher,
            r"candidate-v3:[^\"\r\n]*\$receiptSetSha",
        )
        self.assertRegex(
            publisher,
            r"main-lkg-v3:[^\"\r\n]*\$receiptSetSha",
        )
        self.assertRegex(
            admit,
            r"candidate-v3:[^\"\r\n]*\(\[0-9a-f\]\{64\}\)\$",
        )
        real_max_pr_external_id = (
            "candidate-v3:Siwy55p/Potop_v2:999999:"
            + "a" * 40
            + ":"
            + "b" * 40
            + ":"
            + "c" * 64
        )
        self.assertLessEqual(len(real_max_pr_external_id), 255)
        control_plane_external_id = (
            "control-plane-v2:999999:"
            + "a" * 40
            + ":"
            + "b" * 40
            + ":"
            + "c" * 64
            + ":"
            + "d" * 64
        )
        self.assertLessEqual(len(control_plane_external_id), 255)
        self.assertNotRegex(combined, r"(?<!control-plane-)handoff-v1:")
        for obsolete in (
            "candidate-v1:",
            "main-audit-v1:",
            "main-lkg-v1:",
            "candidate-v2:",
            "main-lkg-v2:",
        ):
            self.assertNotIn(obsolete, combined)

    def test_four_headless_one_native_and_central_lfs_plan(self) -> None:
        workflow = _workflow("agent-integration.yml")
        plan = _job(workflow, "prepare-lfs-plan")
        shard = _job(workflow, "shard")
        runner = RUNNER_PATH.read_text(encoding="utf-8")

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

        smoke_target = "underwater_map_workbench/tests/underwater_map_smoke_test.gd"
        quick_match = re.search(
            r"(?ms)\$quickHeadlessScriptTests\s*=\s*@\((.*?)^\)", runner
        )
        full_match = re.search(
            r"(?ms)\$fullHeadlessScriptTests\s*=\s*@\((.*?)^\)", runner
        )
        self.assertIsNotNone(quick_match)
        self.assertIsNotNone(full_match)
        self.assertNotIn(smoke_target, quick_match.group(1))
        self.assertEqual(1, full_match.group(1).count(f'"{smoke_target}"'))

    def test_trusted_map_check_and_smoke_are_fail_closed(self) -> None:
        workflow = _workflow("agent-integration.yml")
        infra = _job(workflow, "infra-contracts")
        plan = _job(workflow, "prepare-lfs-plan")
        map_check = _job(workflow, "map-authority-check")
        shard = _job(workflow, "shard")
        aggregate = _job(workflow, "aggregate-attestation")

        portal_contract = (
            "underwater_map_workbench/tests/portal_backdrop_clearance_test.py"
        )
        self.assertEqual(1, infra.count(portal_contract))
        self.assertIn('$portalContractRoot = if ($env:VERIFICATION_MODE -ceq "control-plane")', infra)
        self.assertIn(f'(Join-Path $portalContractRoot "{portal_contract}")', infra)

        trusted_dependencies = (
            "tools/workbench_contract.py",
            "tools/workbench_lock.py",
        )
        dependency_match = re.search(
            r"(?ms)\$trustedMapFiles\s*=\s*@\((.*?)^\s*\)", map_check
        )
        self.assertIsNotNone(dependency_match)
        self.assertEqual(
            set(trusted_dependencies),
            set(re.findall(r'"([^"\r\n]+)"', dependency_match.group(1))),
        )
        self.assertIn("Get-FileHash -Algorithm SHA256 -LiteralPath $trustedPath", map_check)
        self.assertIn("Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath", map_check)
        self.assertIn("$candidateSha -cne $trustedSha", map_check)
        self.assertIn("$candidateBuilderSha -cne $env:AUTHORIZED_BUILDER_SHA256", map_check)
        self.assertIn('$env:VERIFICATION_MODE -ceq "control-plane"', map_check)
        self.assertIn("--authorization-sha256 $env:AUTHORIZATION_SHA256", map_check)
        self.assertIn("$candidateHead -cne $env:EXPECTED_HEAD_SHA", map_check)
        self.assertIn('(Join-Path $trustedRoot "tools/ci_python_entry.py")', map_check)
        self.assertIn(
            '--preload ("workbench_lock=" + (Join-Path $trustedRoot "tools/workbench_lock.py"))',
            map_check,
        )
        self.assertIn(
            '--preload ("workbench_contract=" + (Join-Path $trustedRoot "tools/workbench_contract.py"))',
            map_check,
        )
        self.assertIn(
            '--script $candidateBuilder',
            map_check,
        )
        self.assertIn("-- --check", map_check)
        self.assertNotRegex(
            map_check,
            r"&\s+python\s+-I\s+-B\s+\(Join-Path \$candidateRoot [^\n]*build_underwater_map\.py",
        )
        self.assertNotIn("-- --build", map_check)
        self.assertIn("Trusted map authority check changed the exact candidate", map_check)
        self.assertIn("tools/ci_map_check_receipt.py", map_check)
        self.assertIn("map-authority-check.receipt", map_check)
        self.assertIn("map-check-artifact.outputs.artifact-id", map_check)
        self.assertIn("map-check-receipt.outputs.map-receipt-sha256", map_check)

        self.assertNotIn("build_underwater_map.py", plan)
        self.assertIn("- prepare-lfs-plan", map_check)
        self.assertNotIn("- shard", map_check)
        self.assertNotIn("- map-authority-check", shard)
        self.assertIn("- map-authority-check", aggregate)
        self.assertIn("needs.map-authority-check.outputs.artifact-id", aggregate)
        self.assertIn("needs.map-authority-check.outputs.artifact-digest", aggregate)
        self.assertIn("needs.map-authority-check.outputs.map-receipt-sha256", aggregate)
        self.assertIn("$mapSha -cne $env:EXPECTED_MAP_RECEIPT_SHA256", aggregate)
        self.assertIn("map-receipt-sha256=$mapSha", aggregate)
        self.assertIn("tools/ci_map_check_receipt.py", aggregate)

    def test_artifacts_are_bound_by_exact_id_digest_and_run(self) -> None:
        workflow = _workflow("agent-integration.yml")
        plan = _job(workflow, "prepare-lfs-plan")
        shard = _job(workflow, "shard")
        aggregate = _job(workflow, "aggregate-attestation")

        self.assertEqual(5, workflow.count("actions/download-artifact@"))
        self.assertEqual(5, workflow.count("artifact-ids:"))
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
        self.assertIn("EXPECTED_ARTIFACT_ID", _job(workflow, "map-authority-check"))
        self.assertIn("EXPECTED_ARTIFACT_DIGEST", _job(workflow, "map-authority-check"))
        self.assertIn("needs.map-authority-check.outputs.artifact-id", aggregate)
        self.assertIn("needs.map-authority-check.outputs.artifact-digest", aggregate)
        self.assertIn("$nameMatches.Count -ne 1", aggregate)
        self.assertIn("Unique map-check artifact name", aggregate)
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
            "map-authority-check",
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
        self.assertIn("map-receipt-sha256", aggregate)
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
            "map-authority-check",
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
        self.assertIn(
            "underwater_map_workbench/tests/portal_backdrop_clearance_test.py",
            helper_exact,
        )
        self.assertIn(
            "underwater_map_workbench/tests/underwater_map_smoke_test.gd",
            helper_exact,
        )

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

    def test_ard_headers_are_unique_and_ard_0110_remains_trusted_ci(self) -> None:
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
        headers_by_identifier = dict(headers)
        self.assertIn("0110", headers_by_identifier)
        self.assertRegex(headers_by_identifier["0110"].lower(), r"integr|github|zauf")
        self.assertNotIn("Trusted integration gate", decisions)
        self.assertNotIn("Trusted main audit", decisions)


if __name__ == "__main__":
    unittest.main(verbosity=2)
