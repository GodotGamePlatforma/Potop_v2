$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'tools/publish_agent_pr.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw
[void][scriptblock]::Create($text)

$required = @(
    "'assignment', 'current', '--json'",
    "'pr', 'list', '--repo', `$githubRepo, '--state', 'all'",
    "'--assignment', `$AssignmentId",
    "'merge-base', `$head, 'refs/remotes/origin/main'",
    "'--auto', '--merge', '--match-head-commit', `$head",
    "if (`$remoteHead -cne `$head)",
    "if (`$null -ne `$state.mergedAt)",
    "if (`$null -ne `$pull.mergedAt)",
    "'assignment', 'close'",
    'Assignment remains RUNNING until the PR is merged.'
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
    'repository_dispatch',
    'refs/heads/main"',
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

$currentOffset = $text.IndexOf("'assignment', 'current', '--json'")
$validationOffset = $text.IndexOf("'--assignment', `$AssignmentId")
$pushOffset = $text.IndexOf("'push', '--set-upstream'")
$mergeOffset = $text.IndexOf("'--auto', '--merge'")
$closeOffset = $text.IndexOf('Close-CurrentAssignment -Reason')
if (-not (0 -le $currentOffset -and $currentOffset -lt $validationOffset -and
    $validationOffset -lt $pushOffset -and $pushOffset -lt $mergeOffset -and
    $pushOffset -lt $closeOffset)) {
    throw 'Validation, push, native auto-merge and close are not ordered safely.'
}

Write-Output 'publish_agent_pr_test PASS'
