from __future__ import annotations

import ast
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "agent-auto-integrator.yml"
PROTECTED_PATH_HELPER = REPOSITORY_ROOT / "tools" / "ci_protected_paths.py"


def _workflow() -> str:
    return WORKFLOW_PATH.read_text(encoding="utf-8")


def _job(workflow: str, job_id: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        workflow,
    )
    if match is None:
        raise AssertionError(f"workflow job is missing: {job_id}")
    return match.group("body")


def _literal_collection(variable_name: str) -> frozenset[str]:
    module = ast.parse(
        PROTECTED_PATH_HELPER.read_text(encoding="utf-8"),
        filename=str(PROTECTED_PATH_HELPER),
    )
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
    raise AssertionError(f"{variable_name} is missing")


def _inline_exact_paths(job: str) -> frozenset[str]:
    match = re.search(r"(?ms)\$exact\s*=\s*@\((?P<body>.*?)^\s*\)", job)
    if match is None:
        raise AssertionError("inline protected exact-path set is missing")
    return frozenset(path.lower() for path in re.findall(r'"([^"\r\n]+)"', match.group("body")))


def _embedded_run_script(job: str) -> str:
    match = re.search(r"(?ms)^        run: \|\n(?P<body>.*)\Z", job)
    if match is None:
        raise AssertionError("embedded PowerShell run block is missing")
    lines = match.group("body").splitlines()
    return "\n".join(line[10:] if line.startswith("          ") else line for line in lines) + "\n"


def _powershell_function(script: str, name: str) -> str:
    start = script.find(f"function {name} {{")
    if start < 0:
        raise AssertionError(f"PowerShell function is missing: {name}")
    next_function = script.find("\nfunction ", start + 1)
    return script[start:] if next_function < 0 else script[start:next_function]


class AutoAdmissionWorkflowTest(unittest.TestCase):
    maxDiff = None

    def test_trusted_default_branch_events_are_narrow_and_serialized(self) -> None:
        workflow = _workflow()
        self.assertIn(
            "pull_request_target:\n"
            "    types:\n"
            "      - opened\n"
            "      - reopened\n"
            "      - synchronize\n"
            "      - ready_for_review",
            workflow,
        )
        self.assertIn(
            "workflow_run:\n"
            "    workflows:\n"
            "      - Agent branch validation\n"
            "    types:\n"
            "      - completed",
            workflow,
        )
        self.assertRegex(workflow, r"(?m)^permissions:\s*\{\}\s*$")
        self.assertIn("github.event.pull_request.head.repo.full_name", workflow)
        self.assertIn("github.event.pull_request.head.ref", workflow)
        self.assertIn("github.event.workflow_run.head_repository.full_name", workflow)
        self.assertIn("github.event.workflow_run.head_branch", workflow)
        self.assertNotIn("github.event.pull_request.head.sha || github.event.workflow_run.head_sha", workflow)
        self.assertIn("cancel-in-progress: false", workflow)

    def test_intake_is_api_only_and_least_privileged(self) -> None:
        job = _job(_workflow(), "auto-admit-standard-pr")
        self.assertRegex(
            job,
            r"(?ms)^    permissions:\n"
            r"      actions: read\n"
            r"      checks: read\n"
            r"      contents: write\n"
            r"      pull-requests: write\s*$",
        )
        self.assertIn("vars.AUTO_INTEGRATOR_ENABLED == 'true'", job)
        self.assertIn("workflow_run.conclusion == 'success'", job)
        self.assertIn("pull_request.draft == false", job)
        self.assertNotRegex(job, r"(?mi)^\s*(?:-\s*)?uses\s*:")
        for forbidden in (
            "actions/checkout",
            "actions/download-artifact",
            "git checkout",
            "git fetch",
            "gh pr checkout",
            "Invoke-Expression",
            "Start-Process",
            "INTEGRATION_ATTESTER_PRIVATE_KEY",
        ):
            self.assertNotIn(forbidden, job)
        self.assertEqual(
            {
                "EVENT_NAME",
                "EVENT_PR_NUMBER",
                "EVENT_WORKFLOW_RUN_ID",
                "EXPECTED_ATTESTER_APP_ID",
                "GITHUB_TOKEN",
            },
            set(re.findall(r"(?m)^          ([A-Z][A-Z0-9_]+):", job)),
        )

    def test_intake_binds_same_repo_current_main_exact_head_and_fast_success(self) -> None:
        job = _job(_workflow(), "auto-admit-standard-pr")
        required_fragments = (
            '$workflowRun.name -cne $fastWorkflowName',
            '$workflowRun.conclusion -cne "success"',
            '$workflowRun.repository.full_name -cne $repository',
            '$workflowRun.head_repository.full_name -cne $repository',
            '$pullRequest.state -cne "open" -or $pullRequest.draft',
            '$pullRequest.base.ref -cne "main"',
            '$pullRequest.head.repo.full_name -cne $repository',
            '$pullRequest.head.sha -cne $candidateSha',
            "^codex/(root|map|diver|integration|structure-",
            '"/repos/$repository/commits/main"',
            '$pullRequest.base.sha -cne $baseSha',
            '$comparison.status -cne "ahead"',
            '[int]$comparison.behind_by -ne 0',
            '$comparison.merge_base_commit.sha -cne $baseSha',
            '$_.head_sha -ceq $CandidateSha',
            '$latestFastRun.conclusion -cne "success"',
        )
        for fragment in required_fragments:
            self.assertIn(fragment, job)
        self.assertRegex(job, r"workflow_runs \|\s*\n\s*Where-Object")
        self.assertIn("Sort-Object -Property", job)
        self.assertIn("-Descending", job)

    def test_all_protected_path_policies_remain_identical_and_bounded(self) -> None:
        workflow = _workflow()
        expected = frozenset(path.lower() for path in _literal_collection("PROTECTED_EXACT_PATHS"))
        for job_id in ("auto-admit-standard-pr", "admit-handoff", "merge-handoff"):
            job = _job(workflow, job_id)
            self.assertEqual(expected, _inline_exact_paths(job), job_id)
            for prefix in ('.github/', '.githooks/', 'tools/ci_', 'tests/ci_'):
                self.assertIn(f'StartsWith("{prefix}"', job)

        intake = _job(workflow, "auto-admit-standard-pr")
        self.assertIn("previous_filename", intake)
        self.assertIn("$inspected -gt 3000", intake)
        self.assertIn("$page -ge 30", intake)
        self.assertIn("$inspected -eq 0", intake)

    def test_label_is_a_recoverable_claim_and_dispatch_is_exact(self) -> None:
        job = _job(_workflow(), "auto-admit-standard-pr")
        self.assertIn("function Get-LatestCandidateClaim", job)
        self.assertIn("function Get-CandidateClaimState", job)
        self.assertIn('$Claim.status -ceq "in_progress"', job)
        self.assertIn('$Claim.status -ceq "completed"', job)
        self.assertIn('$Claim.status -cne "queued"', job)
        self.assertIn('$claimRun.event -cne "repository_dispatch"', job)
        self.assertIn('$claimRun.path -cne ".github/workflows/agent-auto-integrator.yml"', job)
        self.assertIn('return "complete"', job)
        self.assertIn('return "retry"', job)
        self.assertIn("$alreadyLabeled = $requiredLabel -cin $labels", job)
        self.assertIn("if (-not $alreadyLabeled)", job)
        self.assertIn("$labelAdded = $true", job)
        self.assertIn('if ($claimState -ceq "active")', job)
        self.assertIn('event_type = "integrate-agent-handoff"', job)
        self.assertIn("pr_number = $pullNumber", job)
        self.assertIn("base_sha = $baseSha", job)
        self.assertIn("candidate_sha = $candidateSha", job)
        self.assertIn("if ($labelAdded)", job)
        self.assertIn("-Method DELETE", job)
        self.assertIn("$attempt -lt 12", job)
        self.assertIn("Start-Sleep -Seconds 2", job)
        self.assertIn("if (-not $claimObserved)", job)
        self.assertLess(job.index("issues/$pullNumber/labels"), job.index('event_type = "integrate-agent-handoff"'))

        merge = _job(_workflow(), "merge-handoff")
        self.assertIn('sha = $env:CANDIDATE_SHA', merge)
        self.assertIn('merge_method = "merge"', merge)
        self.assertIn('event_type = "verify-integrated-main"', merge)

    def test_embedded_powershell_parses_on_the_supported_host(self) -> None:
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        script = _embedded_run_script(_job(_workflow(), "auto-admit-standard-pr"))
        with tempfile.TemporaryDirectory() as temporary_directory:
            script_path = Path(temporary_directory) / "auto-admission.ps1"
            script_path.write_text(script, encoding="utf-8", newline="\n")
            parser = r'''
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
  $env:CI_AUTO_ADMISSION_SCRIPT,
  [ref]$tokens,
  [ref]$errors
)
if ($errors.Count -gt 0) {
  $errors | ForEach-Object { [Console]::Error.WriteLine($_.Message) }
  exit 1
}
'''
            result = subprocess.run(
                [
                    str(powershell),
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    parser,
                ],
                env={**os.environ, "CI_AUTO_ADMISSION_SCRIPT": str(script_path)},
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_candidate_claim_state_machine_is_idempotent_and_retryable(self) -> None:
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        self.assertIsNotNone(powershell, "PowerShell is required for workflow policy tests")
        embedded = _embedded_run_script(_job(_workflow(), "auto-admit-standard-pr"))
        function = _powershell_function(embedded, "Get-CandidateClaimState")
        script = f'''\
$ErrorActionPreference = "Stop"
$repository = "Siwy55p/Potop_v2"
$env:GITHUB_SERVER_URL = "https://github.com"
$script:claimRun = $null
function Invoke-GitHubApi {{ return $script:claimRun }}
{function}
function Assert-State([string]$Name, [object]$Claim, [string]$Expected) {{
  $actual = Get-CandidateClaimState -Claim $Claim
  if ($actual -ne $Expected) {{ throw "$Name expected=$Expected actual=$actual" }}
}}
Assert-State "missing" $null "retry"
Assert-State "active" ([pscustomobject]@{{ status = "in_progress" }}) "active"
Assert-State "green" ([pscustomobject]@{{ status = "completed"; conclusion = "success" }}) "complete"
Assert-State "red" ([pscustomobject]@{{ status = "completed"; conclusion = "failure" }}) "retry"
$queued = [pscustomobject]@{{ status = "queued"; details_url = "https://github.com/Siwy55p/Potop_v2/actions/runs/123" }}
$script:claimRun = [pscustomobject]@{{
  name = "Agent auto-integrator"
  event = "repository_dispatch"
  repository = [pscustomobject]@{{ full_name = $repository }}
  path = ".github/workflows/agent-auto-integrator.yml"
  status = "in_progress"
  conclusion = $null
}}
Assert-State "admission-running" $queued "active"
$script:claimRun.status = "completed"
$script:claimRun.conclusion = "success"
Assert-State "admission-dispatched" $queued "active"
$script:claimRun.conclusion = "failure"
Assert-State "admission-retry" $queued "retry"
$rejected = $false
try {{
  Get-CandidateClaimState -Claim ([pscustomobject]@{{ status = "queued"; details_url = "https://example.invalid/actions/runs/123" }}) | Out-Null
}}
catch {{ $rejected = $true }}
if (-not $rejected) {{ throw "Untrusted queued claim URL was accepted." }}
'''
        result = subprocess.run(
            [str(powershell), "-NoProfile", "-NonInteractive", "-Command", "-"],
            input=script,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
