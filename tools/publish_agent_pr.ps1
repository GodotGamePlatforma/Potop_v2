#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [string]$Title = '',
    [string]$Body = '',

    [ValidateRange(30, 1800)]
    [int]$WaitForMergeSeconds = 300,

    [switch]$WaitForMerge,
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

function Get-CurrentAssignment {
    param([Parameter(Mandatory = $true)][string]$Repository)
    $contract = Join-Path $Repository 'tools/workbench_contract.py'
    $response = Invoke-Native -FilePath python -Arguments @(
        '-B', $contract, '--repo', $Repository,
        'assignment', 'current', '--json'
    )
    try {
        $status = ConvertFrom-Json -InputObject $response.Output
    }
    catch {
        throw "Current assignment did not return valid JSON: $($response.Output)"
    }
    if ([string]$status.state -cne 'RUNNING' -or $null -eq $status.assignment) {
        throw 'The current worktree does not have exactly one RUNNING assignment.'
    }
    return $status
}

function Close-CurrentAssignment {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][object]$Assignment,
        [Parameter(Mandatory = $true)][string]$Reason
    )
    $contract = Join-Path $Repository 'tools/workbench_contract.py'
    $closed = Invoke-Native -FilePath python -Arguments @(
        '-B', $contract, '--repo', $Repository,
        'assignment', 'close',
        '--task-id', [string]$Assignment.task_id,
        '--assignment-id', [string]$Assignment.assignment_id,
        '--thread-id', [string]$Assignment.thread_id,
        '--reason', $Reason,
        '--json'
    )
    $closedStatus = ConvertFrom-Json -InputObject $closed.Output
    if ([string]$closedStatus.state -cne 'CLOSED') {
        throw 'Assignment did not close after immutable PR handoff.'
    }
    return $closedStatus
}

function Assert-RepositoryIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$ExpectedHead,
        [Parameter(Mandatory = $true)][string]$ExpectedBase
    )
    $actualHead = (Invoke-Native -FilePath git -Arguments @(
        '-C', $Repository, 'rev-parse', '--verify', 'HEAD^{commit}'
    )).Output
    $actualBase = (Invoke-Native -FilePath git -Arguments @(
        '-C', $Repository, 'rev-parse', '--verify',
        'refs/remotes/origin/main^{commit}'
    )).Output
    $actualMergeBase = (Invoke-Native -FilePath git -Arguments @(
        '-C', $Repository, 'merge-base', $actualHead,
        'refs/remotes/origin/main'
    )).Output
    if (
        $actualHead -cne $ExpectedHead -or
        $actualBase -cne $ExpectedBase -or
        $actualMergeBase -cne $ExpectedBase
    ) {
        throw "Repository identity changed: head=$actualHead origin/main=$actualBase merge-base=$actualMergeBase."
    }
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

# Crash-safe recovery is intentionally evaluated before fresh-base admission.
# A squash merge moves main to a non-ancestor of the original PR head, but the
# exact merged PR remains an immutable handoff that must release its assignment.
$mergedLookup = Invoke-Native -FilePath gh -Arguments @(
    'pr', 'list', '--repo', $githubRepo, '--state', 'merged',
    '--base', 'main', '--head', $branch, '--limit', '100',
    '--json', 'number,url,headRefOid,headRefName,baseRefName,mergedAt,state'
) -AllowFailure
if ($mergedLookup.ExitCode -eq 0 -and
    -not [string]::IsNullOrWhiteSpace($mergedLookup.Output)) {
    $mergedPulls = @(@(ConvertFrom-Json -InputObject $mergedLookup.Output) |
        Where-Object {
            $null -ne $_ -and
            $null -ne $_.PSObject.Properties['headRefOid'] -and
            $null -ne $_.PSObject.Properties['headRefName'] -and
            $null -ne $_.PSObject.Properties['baseRefName'] -and
            $null -ne $_.PSObject.Properties['mergedAt'] -and
            $null -ne $_.PSObject.Properties['state'] -and
            [string]$_.headRefOid -ceq $head -and
            [string]$_.headRefName -ceq $branch -and
            [string]$_.baseRefName -ceq 'main' -and
            $null -ne $_.mergedAt -and [string]$_.state -ceq 'MERGED'
        })
    if ($mergedPulls.Count -gt 1) {
        throw "More than one merged PR is bound to exact branch head $head."
    }
    if ($mergedPulls.Count -eq 1) {
        $recoveryStatus = Get-CurrentAssignment -Repository $repo
        $recoveryAssignment = $recoveryStatus.assignment
        $assignmentHead = [string]$recoveryAssignment.head
        $assignmentAncestor = Invoke-Native -FilePath git -Arguments @(
            '-C', $repo, 'merge-base', '--is-ancestor', $assignmentHead, $head
        ) -AllowFailure
        if ([string]$recoveryAssignment.branch -cne $branch -or
            $assignmentHead -cnotmatch '^[0-9a-f]{40}$' -or
            $assignmentAncestor.ExitCode -ne 0) {
            throw 'Merged-PR recovery does not match the current assignment branch/baseline ancestry.'
        }
        $recoveryContract = Join-Path $repo 'tools/workbench_contract.py'
        $recoveryValidation = Invoke-Native -FilePath python -Arguments @(
            '-B', $recoveryContract, '--repo', $repo, 'validate',
            '--owner', [string]$recoveryAssignment.owner,
            '--base', $assignmentHead,
            '--assignment', [string]$recoveryAssignment.assignment_id,
            '--task-id', [string]$recoveryAssignment.task_id,
            '--thread-id', [string]$recoveryAssignment.thread_id,
            '--json'
        )
        try {
            $recoveryValidationResult = ConvertFrom-Json `
                -InputObject $recoveryValidation.Output
        }
        catch {
            throw 'Merged-PR recovery assignment validation did not return JSON.'
        }
        if ($recoveryValidationResult.ready -ne $true -or
            [string]$recoveryValidationResult.assignment_state -cne 'RUNNING') {
            throw 'Merged-PR recovery diff is outside its RUNNING assignment.'
        }
        Close-CurrentAssignment -Repository $repo `
            -Assignment $recoveryAssignment `
            -Reason "immutable_pr_merged_recovery:$($mergedPulls[0].number):$head" |
            Out-Null
        Write-Output (
            "PR_MERGED_RECOVERED number=$($mergedPulls[0].number) " +
            "url=$($mergedPulls[0].url) head=$head assignment_state=CLOSED"
        )
        return
    }
}

Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'fetch', '--no-tags', 'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null
$originMain = (Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'rev-parse', '--verify',
    'refs/remotes/origin/main^{commit}'
)).Output
if ($originMain -cnotmatch '^[0-9a-f]{40}$') {
    throw "Cannot resolve exact origin/main commit: $originMain"
}
Assert-RepositoryIdentity -Repository $repo -ExpectedHead $head -ExpectedBase $originMain

$assignmentStatus = Get-CurrentAssignment -Repository $repo
$assignment = $assignmentStatus.assignment
$assignmentId = [string]$assignment.assignment_id
$assignmentDigest = [string]$assignment.assignment_digest
$taskId = [string]$assignment.task_id
$threadId = [string]$assignment.thread_id
$owner = [string]$assignment.owner

$contract = Join-Path $repo 'tools/workbench_contract.py'
Invoke-Native -FilePath python -Arguments @(
    '-B', $contract, '--repo', $repo, 'eol-check'
) | Out-Null
$validation = Invoke-Native -FilePath python -Arguments @(
    '-B', $contract, '--repo', $repo, 'validate',
    '--owner', $owner, '--base', $originMain,
    '--assignment', $assignmentId,
    '--task-id', $taskId,
    '--thread-id', $threadId,
    '--json'
)
try {
    $validationResult = ConvertFrom-Json -InputObject $validation.Output
}
catch {
    throw "Assignment-scoped validation did not return JSON: $($validation.Output)"
}
if ($validationResult.ready -ne $true -or
    [string]$validationResult.assignment_state -cne 'RUNNING') {
    throw 'Assignment-scoped owner/write-set validation is not ready.'
}

$recheckedAssignment = Get-CurrentAssignment -Repository $repo
if (
    [string]$recheckedAssignment.assignment.assignment_id -cne $assignmentId -or
    [string]$recheckedAssignment.assignment.assignment_digest -cne $assignmentDigest
) {
    throw 'Assignment identity changed during publication validation.'
}
Assert-RepositoryIdentity -Repository $repo -ExpectedHead $head -ExpectedBase $originMain

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = (Invoke-Native -FilePath git -Arguments @(
        '-C', $repo, 'log', '-1', '--format=%s'
    )).Output
}
if ([string]::IsNullOrWhiteSpace($Body)) {
    $Body = "Automated assigned handoff from ``$branch`` at ``$head``."
}

$autoState = Invoke-Native -FilePath gh -Arguments @(
    'variable', 'get', 'AUTO_INTEGRATOR_ENABLED', '--repo', $githubRepo,
    '--json', 'value', '--jq', '.value'
) -AllowFailure
if ($autoState.ExitCode -ne 0 -or
    [string]$autoState.Output.Trim() -cne 'true') {
    throw (
        'Trusted automatic admission is not enabled. Keep the branch and ' +
        'assignment immutable until the CI-S1A bootstrap/canary completes.'
    )
}

if (-not $PSCmdlet.ShouldProcess(
        $branch,
        'push exact HEAD, create PR, request trusted fast-green and enable merge queue'
    )) {
    Write-Output (
        "PLAN branch=$branch head=$head base=$originMain " +
        "assignment=$assignmentId auto_merge=native-queue-squash"
    )
    return
}

Invoke-Native -FilePath git -Arguments @(
    '-C', $repo, 'push', '--set-upstream', 'origin',
    "${head}:refs/heads/$branch"
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
    '--json', 'number,url,headRefOid,baseRefOid,mergedAt,state'
) -AllowFailure
$exactPulls = @()
if ($existing.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($existing.Output)) {
    $listedPulls = ConvertFrom-Json -InputObject $existing.Output
    $exactPulls = @(@($listedPulls) | Where-Object {
        [string]$_.headRefOid -ceq $head -and [string]$_.baseRefOid -ceq $originMain
    })
}
if ($exactPulls.Count -gt 1) {
    throw "More than one PR is bound to exact branch head/base $head/$originMain."
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
        '--json', 'number,url,headRefOid,baseRefOid,mergedAt,state'
    )).Output | ConvertFrom-Json
}
if ([string]$pull.headRefOid -cne $head -or [string]$pull.baseRefOid -cne $originMain) {
    throw 'PR identity moved before trusted admission.'
}
if ($null -ne $pull.mergedAt) {
    Close-CurrentAssignment -Repository $repo -Assignment $assignment `
        -Reason "immutable_pr_merged:$($pull.number):$head" | Out-Null
    Write-Output (
        "PR_MERGED number=$($pull.number) url=$($pull.url) " +
        'assignment_state=CLOSED'
    )
    return
}
if ([string]$pull.state -cne 'OPEN') {
    throw "Exact PR #$($pull.number) is closed without merge."
}

Invoke-Native -FilePath gh -Arguments @(
    'api', '--method', 'POST', "repos/$githubRepo/dispatches",
    '-f', 'event_type=verify-fast-pr',
    '-f', 'client_payload[kind]=pull_request',
    '-F', "client_payload[pr_number]=$($pull.number)",
    '-f', "client_payload[base_sha]=$originMain",
    '-f', "client_payload[head_sha]=$head",
    '-f', "client_payload[target_sha]=$head",
    '-f', "client_payload[branch]=$branch"
) | Out-Null

Invoke-Native -FilePath gh -Arguments @(
    'pr', 'merge', [string]$pull.number, '--repo', $githubRepo,
    '--auto', '--squash', '--match-head-commit', $head
) | Out-Null

Close-CurrentAssignment -Repository $repo -Assignment $assignment `
    -Reason "immutable_pr_handoff:$($pull.number):$head" | Out-Null

Write-Output (
    "PR_READY number=$($pull.number) url=$($pull.url) head=$head " +
    "assignment=$assignmentId assignment_state=CLOSED auto_merge=native-queue-squash"
)

if ($NoWait -or -not $WaitForMerge) {
    Write-Output 'Trusted fast-green was requested; GitHub will queue and squash after all exact checks pass.'
    return
}

$deadline = [DateTime]::UtcNow.AddSeconds($WaitForMergeSeconds)
do {
    $state = (Invoke-Native -FilePath gh -Arguments @(
        'pr', 'view', [string]$pull.number, '--repo', $githubRepo,
        '--json', 'headRefOid,mergedAt,url,statusCheckRollup'
    )).Output | ConvertFrom-Json
    if ([string]$state.headRefOid -cne $head) {
        throw 'PR head changed while waiting.'
    }
    if ($null -ne $state.mergedAt) {
        Write-Output "PR_MERGED number=$($pull.number) url=$($pull.url)"
        return
    }
    $failed = @($state.statusCheckRollup | Where-Object {
        $_.conclusion -in @('FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED')
    })
    if ($failed.Count -gt 0) {
        $names = ($failed | ForEach-Object { $_.name }) -join ', '
        throw "PR checks failed: $names."
    }
    Start-Sleep -Seconds 5
} while ([DateTime]::UtcNow -lt $deadline)

throw "PR did not merge within $WaitForMergeSeconds seconds: $($pull.url)"
