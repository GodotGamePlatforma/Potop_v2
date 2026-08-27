$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'tools\publish_agent_pr.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw
[void][scriptblock]::Create($text)

$required = @(
    "'pr', 'list', '--repo', `$githubRepo, '--state', 'all'",
    "'merge-base', `$head, 'refs/remotes/origin/main'",
    "'tools/ci_branch_owner.py'",
    "'--expected-head', `$head",
    "'--expected-base', `$mergeBase",
    "'--auto', '--merge', '--match-head-commit', `$head",
    "if (`$remoteHead -cne `$head)",
    "if (`$null -ne `$state.mergedAt)",
    "if (`$null -ne `$pull.mergedAt)"
)
foreach ($marker in $required) {
    if (-not $text.Contains($marker)) {
        throw "publish_agent_pr.ps1 is missing required marker: $marker"
    }
}

$forbidden = @(
    '--admin',
    '--force',
    'integration-ready',
    'control-plane-reviewed',
    'repository_dispatch',
    'assignment current',
    'assignment close',
    'ci_protected_paths.py',
    '[string]$TaskId',
    '[string]$ThreadId',
    '[string]$AssignmentId',
    '[string]$Owner'
)
foreach ($marker in $forbidden) {
    if ($text.Contains($marker)) {
        throw "publish_agent_pr.ps1 contains forbidden marker: $marker"
    }
}

$validationOffset = $text.IndexOf("'tools/ci_branch_owner.py'")
$pushOffset = $text.IndexOf("'push', '--set-upstream'")
$mergeOffset = $text.IndexOf("'--auto', '--merge'")
if (-not (0 -le $validationOffset -and $validationOffset -lt $pushOffset -and
    $pushOffset -lt $mergeOffset)) {
    throw 'Owner validation, exact push and native auto-merge are not ordered safely.'
}

Write-Output 'publish_agent_pr_test PASS'
