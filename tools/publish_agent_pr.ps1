#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [string]$Title = '',
    [string]$Body = '',

    [ValidateRange(30, 1800)]
    [int]$WaitForMergeSeconds = 300,

    [switch]$NoWait
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    $text = ($output | Out-String).Trim()
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed ($exitCode): $text"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $text }
}

$repo = (Invoke-Native -FilePath git -Arguments @(
    'rev-parse', '--show-toplevel'
)).Output
$branch = (Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'branch', '--show-current'
)).Output
if ($branch -cnotmatch '^codex/.+') {
    throw "Only a codex/* task branch can be published: $branch"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'status', '--porcelain=v1', '--untracked-files=all'
)).Output)) {
    throw 'Commit all assigned changes before opening the PR.'
}
$head = (Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'rev-parse', 'HEAD^{commit}'
)).Output
$githubRepo = (Invoke-Native -FilePath gh -Arguments @(
    'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'
)).Output
if ($githubRepo -cnotmatch '^[^/]+/[^/]+$') {
    throw "Cannot resolve GitHub repository identity: $githubRepo"
}

Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'fetch', '--no-tags', 'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null

$contract = Join-Path $repo 'tools/workbench_contract.py'
$assignmentStatus = (Invoke-Native -FilePath python -Arguments @(
    '-B', $contract, '--repo', $repo,
    'assignment', 'current', '--json'
)).Output | ConvertFrom-Json
$assignment = $assignmentStatus.assignment
$Owner = [string]$assignment.owner
$TaskId = [string]$assignment.task_id
$ThreadId = [string]$assignment.thread_id
$AssignmentId = [string]$assignment.assignment_id

function Close-CurrentAssignment {
    param([string]$Reason)
    Invoke-Native -FilePath python -Arguments @(
        '-B', $contract, '--repo', $repo, 'assignment', 'close',
        '--task-id', $TaskId, '--assignment-id', $AssignmentId,
        '--thread-id', $ThreadId, '--reason', $Reason
    ) | Out-Null
}

Invoke-Native -FilePath python -Arguments @(
    '-B', $contract, '--repo', $repo, 'eol-check'
) | Out-Null
$mergeBase = (Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'merge-base', $head, 'refs/remotes/origin/main'
)).Output
if ($mergeBase -cnotmatch '^[0-9a-f]{40}$') {
    throw "Cannot resolve exact branch/main merge-base: $mergeBase"
}
Invoke-Native -FilePath python -Arguments @(
    '-B', $contract, '--repo', $repo, 'validate', '--owner', $Owner,
    '--assignment', $AssignmentId, '--task-id', $TaskId,
    '--thread-id', $ThreadId, '--base', $mergeBase
) | Out-Null

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = (Invoke-Native -FilePath git -Arguments @(
        '-C', $repo, 'log', '-1', '--format=%s'
    )).Output
}
if ([string]::IsNullOrWhiteSpace($Body)) {
    $Body = "Automated agent handoff from ``$branch`` at ``$head``."
}

if (-not $PSCmdlet.ShouldProcess($branch, 'push exact HEAD, open ordinary PR and enable native auto-merge')) {
    Write-Output "PLAN branch=$branch head=$head base=main auto_merge=native"
    return
}

Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'push', '--set-upstream', 'origin',
    "HEAD:refs/heads/$branch"
) | Out-Null
$remoteHeadLine = (Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'ls-remote', '--heads', 'origin', "refs/heads/$branch"
)).Output
$remoteHead = ($remoteHeadLine -split "\s+")[0]
if ($remoteHead -cne $head) {
    throw "Remote branch does not match immutable local HEAD: local=$head remote=$remoteHead"
}

$existing = Invoke-Native -FilePath gh -Arguments @(
    'pr', 'list', '--repo', $githubRepo, '--state', 'all',
    '--base', 'main', '--head', $branch, '--limit', '100',
    '--json', 'number,url,headRefOid,mergedAt,state'
) -AllowFailure
$exactPulls = @()
if ($existing.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($existing.Output)) {
    $exactPulls = @($existing.Output | ConvertFrom-Json | Where-Object {
        [string]$_.headRefOid -ceq $head
    })
}
if ($exactPulls.Count -gt 1) {
    throw "More than one PR is bound to exact branch head $head."
}
if ($exactPulls.Count -eq 1) {
    $pull = $exactPulls[0]
}
else {
    $url = (Invoke-Native -FilePath gh -Arguments @(
        'pr', 'create', '--repo', $githubRepo, '--base', 'main',
        '--head', $branch, '--title', $Title, '--body', $Body
    )).Output
    $pull = (Invoke-Native -FilePath gh -Arguments @(
        'pr', 'view', $url, '--repo', $githubRepo,
        '--json', 'number,url,headRefOid,mergedAt,state'
    )).Output | ConvertFrom-Json
}
if ([string]$pull.headRefOid -cne $head) {
    throw "PR head moved before auto-merge admission: expected=$head actual=$($pull.headRefOid)"
}
if ($null -ne $pull.mergedAt) {
    Close-CurrentAssignment -Reason "merged PR #$($pull.number)"
    Write-Output "PR_MERGED number=$($pull.number) url=$($pull.url) assignment=CLOSED"
    return
}
if ([string]$pull.state -cne 'OPEN') {
    throw "Exact PR #$($pull.number) is closed without merge; assignment stays RUNNING."
}

Invoke-Native -FilePath gh -Arguments @(
    'pr', 'merge', [string]$pull.number, '--repo', $githubRepo,
    '--auto', '--merge', '--match-head-commit', $head
) | Out-Null
Write-Output "PR_READY number=$($pull.number) url=$($pull.url) head=$head auto_merge=native"

if ($NoWait) {
    Write-Output 'Assignment remains RUNNING until the PR is merged.'
    return
}

$deadline = [DateTime]::UtcNow.AddSeconds($WaitForMergeSeconds)
do {
    $state = (Invoke-Native -FilePath gh -Arguments @(
        'pr', 'view', [string]$pull.number, '--repo', $githubRepo,
        '--json', 'headRefOid,mergedAt,url,statusCheckRollup'
    )).Output | ConvertFrom-Json
    if ([string]$state.headRefOid -cne $head) {
        throw 'PR head changed while waiting; assignment stays RUNNING.'
    }
    if ($null -ne $state.mergedAt) {
        Close-CurrentAssignment -Reason "merged PR #$($pull.number)"
        Write-Output "PR_MERGED number=$($pull.number) url=$($pull.url) assignment=CLOSED"
        return
    }
    $failed = @($state.statusCheckRollup | Where-Object {
        $_.conclusion -in @('FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED')
    })
    if ($failed.Count -gt 0) {
        $names = ($failed | ForEach-Object { $_.name }) -join ', '
        throw "PR checks failed: $names. Assignment stays RUNNING."
    }
    Start-Sleep -Seconds 5
} while ([DateTime]::UtcNow -lt $deadline)

throw "PR did not merge within $WaitForMergeSeconds seconds. Assignment stays RUNNING: $($pull.url)"
