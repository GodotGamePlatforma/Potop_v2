[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$CandidateReceipt,

    [string]$RunReceipt,

    [switch]$FromOriginMain,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(root|map|diver|integration|structure:[a-z][a-z0-9_]*)$')]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9._-]*$')]
    [string]$TaskSlug,

    [string]$TaskId = '',

    [string]$ThreadId = '',

    [string]$TaskBrief = '',

    [string]$WriteSet = '',

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$Branch,

    [ValidateRange(30, 86400)]
    [int]$AckTimeoutSeconds = 300,

    [switch]$Create,

    [ValidateSet(
        '',
        'AfterGitWorktreeAdd',
        'WaitAfterGitWorktreeAdd',
        'AfterAssignmentPublicationProcessFailure'
    )]
    [string]$FaultInjection = '',

    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$FaultInjectionToken = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:GitSafeDirectory = ''
$script:LastGreenRef = 'refs/last-green/integration'

function Invoke-NativeResult {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $effectiveArguments = $Arguments
        if ($FilePath -eq 'git' -and
            -not [string]::IsNullOrWhiteSpace($script:GitSafeDirectory)) {
            $effectiveArguments = @(
                '-c', "safe.directory=$script:GitSafeDirectory"
            ) + $Arguments
        }
        $output = & $FilePath @effectiveArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
    }
}

function Invoke-GitText {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $result = Invoke-NativeResult -FilePath 'git' -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($result.Output)"
    }
    return $result.Output
}

function Get-NormalizedPath {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Find-InvokingGitBoundary {
    param([string]$StartPath)

    $cursor = [System.IO.DirectoryInfo]::new(
        [System.IO.Path]::GetFullPath($StartPath)
    )
    while ($null -ne $cursor) {
        # A linked worktree has a .git file; a primary worktree normally has a
        # .git directory. Either is a sufficient, filesystem-only boundary for
        # applying a narrowly scoped safe.directory override before asking Git.
        if (Test-Path -LiteralPath (Join-Path $cursor.FullName '.git')) {
            return $cursor.FullName
        }
        $cursor = $cursor.Parent
    }
    throw "Current directory is not inside a Git worktree: $StartPath"
}

function Test-SamePath {
    param([string]$Left, [string]$Right)

    return [string]::Equals(
        (Get-NormalizedPath -Path $Left),
        (Get-NormalizedPath -Path $Right),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-WriteSetPaths {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::UTF8.GetString($raw)
    $records = if ([Array]::IndexOf($raw, [byte]0) -ge 0) {
        $text.Split([char[]]@([char]0), [System.StringSplitOptions]::None)
    }
    else {
        $text -split "`r?`n"
    }
    $paths = @()
    foreach ($record in $records) {
        $candidate = ([string]$record).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate) -or
            $candidate.StartsWith('#')) {
            continue
        }
        $paths += $candidate.Replace('\', '/')
    }
    return @($paths | Sort-Object -Unique -CaseSensitive)
}

function Test-ExactPublishedAssignment {
    param(
        [string]$Contract,
        [string]$Repository,
        [string]$TaskId,
        [string]$ThreadId,
        [string]$Owner,
        [string]$Brief,
        [string]$Destination,
        [string]$CommonDirectory,
        [string]$BranchName,
        [string]$Head,
        [string]$Tree,
        [string]$WriteSetPath,
        [bool]$OriginMain
    )

    $statusResult = Invoke-NativeResult -FilePath 'python' -Arguments @(
        '-B', $Contract, '--repo', $Repository,
        'assignment', 'status', '--task-id', $TaskId, '--json'
    )
    if ($statusResult.ExitCode -ne 0 -or
        [string]::IsNullOrWhiteSpace($statusResult.Output)) {
        return $false
    }
    try { $status = ConvertFrom-Json -InputObject $statusResult.Output }
    catch { return $false }
    if ([string]$status.state -cne 'WAITING_ACK' -or
        $null -eq $status.assignment) {
        return $false
    }
    $assignment = $status.assignment
    $expectedSchema = if ($OriginMain) { 2 } else { 1 }
    $expectedBaseline = if ($OriginMain) { 'origin-main' } else { '' }
    if ([int]$assignment.schema_version -ne $expectedSchema -or
        [string]$assignment.task_id -cne $TaskId -or
        [string]$assignment.thread_id -cne $ThreadId -or
        [string]$assignment.owner -cne $Owner -or
        [string]$assignment.brief -cne $Brief.Trim() -or
        [string]$assignment.branch -cne $BranchName -or
        [string]$assignment.head -cne $Head -or
        [string]$assignment.tree -cne $Tree -or
        -not (Test-SamePath -Left ([string]$assignment.destination) -Right $Destination) -or
        -not (Test-SamePath -Left ([string]$assignment.common_git_dir) -Right $CommonDirectory) -or
        ($OriginMain -and
            [string]$assignment.baseline_kind -cne $expectedBaseline)) {
        return $false
    }
    $expectedPaths = @(Get-WriteSetPaths -Path $WriteSetPath)
    $actualPaths = @(@($assignment.write_set) | ForEach-Object {
        ([string]$_).Replace('\', '/')
    } | Sort-Object -Unique -CaseSensitive)
    return @(
        Compare-Object -ReferenceObject $expectedPaths `
            -DifferenceObject $actualPaths -CaseSensitive
    ).Count -eq 0
}

function Test-IsWithinPath {
    param([string]$Candidate, [string]$Parent)

    $candidateFull = Get-NormalizedPath -Path $Candidate
    $parentFull = Get-NormalizedPath -Path $Parent
    return $candidateFull -eq $parentFull -or $candidateFull.StartsWith(
        $parentFull + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-RegisteredWorktreePaths {
    param([string]$Repository)

    $porcelain = Invoke-GitText -Arguments @(
        '-C', $Repository, 'worktree', 'list', '--porcelain'
    )
    $paths = @()
    foreach ($line in ($porcelain -split "`r?`n")) {
        if ($line.StartsWith('worktree ')) {
            $paths += $line.Substring('worktree '.Length)
        }
    }
    return @($paths)
}

function Test-RegisteredWorktree {
    param([string]$Repository, [string]$Path)

    foreach ($registeredPath in @(Get-RegisteredWorktreePaths -Repository $Repository)) {
        if (Test-SamePath -Left $registeredPath -Right $Path) {
            return $true
        }
    }
    return $false
}

function Test-LocalBranch {
    param([string]$Repository, [string]$BranchName)

    $result = Invoke-NativeResult -FilePath 'git' -Arguments @(
        '-C', $Repository, 'show-ref', '--verify', '--quiet',
        "refs/heads/$BranchName"
    )
    if ($result.ExitCode -notin @(0, 1)) {
        throw "Cannot inspect branch: $BranchName"
    }
    return $result.ExitCode -eq 0
}

function Get-LastGreenHead {
    param([string]$Repository)

    $symbolic = Invoke-NativeResult -FilePath 'git' -Arguments @(
        '-C', $Repository, 'symbolic-ref', '--quiet', $script:LastGreenRef
    )
    if ($symbolic.ExitCode -eq 0) {
        throw (
            "$($script:LastGreenRef) must be a direct ref, not a symbolic " +
            "ref to $($symbolic.Output)."
        )
    }
    if ($symbolic.ExitCode -notin @(1, 128)) {
        throw "Cannot inspect $($script:LastGreenRef): $($symbolic.Output)"
    }
    $result = Invoke-NativeResult -FilePath 'git' -Arguments @(
        '-C', $Repository, 'rev-parse', '--verify', '--quiet',
        $script:LastGreenRef
    )
    if ($result.ExitCode -eq 1) {
        throw "Authoritative last-green ref is missing: $($script:LastGreenRef)"
    }
    if ($result.ExitCode -ne 0) {
        throw "Cannot read $($script:LastGreenRef): $($result.Output)"
    }
    $commit = Invoke-GitText -Arguments @(
        '-C', $Repository, 'rev-parse', '--verify', "$($result.Output)^{commit}"
    )
    if ($commit -ne $result.Output) {
        throw "$($script:LastGreenRef) must point directly to a commit."
    }
    return $commit
}

function Get-WorktreeReservationPath {
    param(
        [string]$CommonDirectory,
        [string]$ResourceKind,
        [string]$ResourceIdentity
    )

    $reservationDirectory = Join-Path $CommonDirectory 'codex-worktree-reservations'
    [System.IO.Directory]::CreateDirectory($reservationDirectory) | Out-Null

    $reservationIdentity = $ResourceKind + "`n" + $ResourceIdentity
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($reservationIdentity)
        )
    }
    finally {
        $sha256.Dispose()
    }
    $key = -join @($digest | ForEach-Object { $_.ToString('x2') })
    return Join-Path $reservationDirectory "$ResourceKind-$key.lock"
}

function Get-WorktreeReservationPaths {
    param(
        [string]$CommonDirectory,
        [string]$DestinationPath,
        [string]$BranchName
    )

    # Destination and branch are independent Git resources. Locking their
    # pair would let same-path/different-branch and same-branch/different-path
    # requests race. A stable ordering prevents deadlocks while preserving
    # parallel setup for requests whose two resources are both disjoint.
    $destinationIdentity = (
        Get-NormalizedPath -Path $DestinationPath
    ).ToLowerInvariant()
    $branchIdentity = $BranchName.ToLowerInvariant()
    return @(
        (Get-WorktreeReservationPath -CommonDirectory $CommonDirectory `
            -ResourceKind 'destination' -ResourceIdentity $destinationIdentity),
        (Get-WorktreeReservationPath -CommonDirectory $CommonDirectory `
            -ResourceKind 'branch' -ResourceIdentity $branchIdentity)
    ) | Sort-Object -Unique
}

function Enter-WorktreeReservation {
    param(
        [string]$CommonDirectory,
        [string]$DestinationPath,
        [string]$BranchName,
        [int]$WaitSeconds = 30
    )

    $reservationPaths = @(Get-WorktreeReservationPaths `
        -CommonDirectory $CommonDirectory `
        -DestinationPath $DestinationPath `
        -BranchName $BranchName)
    $deadline = [System.DateTime]::UtcNow.AddSeconds($WaitSeconds)
    $waitWasReported = $false
    $lastSharingError = ''

    while ($true) {
        $streams = @()
        try {
            foreach ($reservationPath in $reservationPaths) {
                $streams += [System.IO.File]::Open(
                    $reservationPath,
                    [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )
            }
        }
        catch [System.IO.IOException] {
            foreach ($stream in @($streams)) {
                $stream.Dispose()
            }
            $lastSharingError = $_.Exception.Message
            if ([System.DateTime]::UtcNow -ge $deadline) {
                throw (
                    "Timed out waiting for shared worktree reservations " +
                    "$($reservationPaths -join ', ') for destination $DestinationPath and " +
                    "branch $BranchName. Last lock error: $lastSharingError"
                )
            }
            if (-not $waitWasReported) {
                Write-Warning (
                    "Shared worktree reservation is busy; waiting up to " +
                    "$WaitSeconds seconds for destination $DestinationPath " +
                    "and branch $BranchName."
                )
                $waitWasReported = $true
            }
            Start-Sleep -Milliseconds 100
            continue
        }
        catch {
            foreach ($stream in @($streams)) {
                $stream.Dispose()
            }
            throw
        }

        try {
            $token = [guid]::NewGuid().ToString('N')
            $metadata = (
                "token=$token`n" +
                "pid=$PID`n" +
                "destination=$DestinationPath`n" +
                "branch=$BranchName`n"
            )
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($metadata)
            foreach ($stream in @($streams)) {
                $stream.SetLength(0)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            }
            return [pscustomobject]@{
                Paths = $reservationPaths
                Token = $token
                Streams = $streams
            }
        }
        catch {
            foreach ($stream in @($streams)) {
                $stream.Dispose()
            }
            throw
        }
    }
}

function Exit-WorktreeReservation {
    param($Reservation)

    if ($null -ne $Reservation -and $null -ne $Reservation.Streams) {
        foreach ($stream in @($Reservation.Streams)) {
            $stream.Dispose()
        }
    }
}

function Assert-WorktreeTargetAvailable {
    param(
        [string]$Repository,
        [string]$DestinationPath,
        [string]$BranchName
    )

    foreach ($existingWorktree in @(
        Get-RegisteredWorktreePaths -Repository $Repository
    )) {
        if (Test-IsWithinPath -Candidate $DestinationPath -Parent $existingWorktree) {
            throw (
                "Shared worktree reservation conflict: destination must be " +
                "outside every existing worktree: $existingWorktree"
            )
        }
    }
    if (Test-Path -LiteralPath $DestinationPath) {
        throw (
            "Shared worktree reservation conflict: destination already exists: " +
            $DestinationPath
        )
    }
    if (Test-LocalBranch -Repository $Repository -BranchName $BranchName) {
        throw (
            "Shared worktree reservation conflict: branch already exists: " +
            $BranchName
        )
    }
}

function Write-AgentWorktreePlan {
    param(
        [string]$PlanOwner,
        [string]$PlanTaskSlug,
        [string]$PlanTaskId,
        [string]$PlanThreadId,
        [string]$PlanTaskBrief,
        [string]$PlanWriteSet,
        [int]$PlanAckTimeoutSeconds,
        [string]$PlanBaselineKind,
        [string]$PlanReceiptPath,
        [string]$PlanRunReceiptPath,
        [string]$PlanBaseline,
        [string]$PlanTree,
        [string]$PlanLastGreenRef,
        [string]$PlanBranch,
        [string]$PlanDestinationPath,
        [string]$PlanCommonDirectory,
        [string]$PlanPublicationLock
    )

    Write-Output "Agent worktree plan"
    Write-Output "  owner:       $PlanOwner"
    Write-Output "  task:        $PlanTaskSlug"
    Write-Output "  baseline:     $PlanBaselineKind"
    if ($PlanBaselineKind -eq 'verified-lkg') {
        Write-Output "  task-id:     $PlanTaskId"
        Write-Output "  thread-id:   $PlanThreadId"
        Write-Output "  brief:       $PlanTaskBrief"
        Write-Output "  write-set:   $PlanWriteSet"
        Write-Output "  ACK timeout: $PlanAckTimeoutSeconds seconds"
        Write-Output "  assignment:  prospective WAITING_ACK (created only with -Create)"
        Write-Output "  candidate-receipt: $PlanReceiptPath"
        Write-Output "  run-receipt:       $PlanRunReceiptPath"
        Write-Output "  last-green:  $PlanLastGreenRef -> $PlanBaseline"
    }
    else {
        Write-Output "  origin/main:  $PlanBaseline"
    }
    Write-Output "  candidate:   $PlanBaseline"
    Write-Output "  tree:        $PlanTree"
    Write-Output "  branch:      $PlanBranch"
    Write-Output "  destination: $PlanDestinationPath"
    Write-Output "  common-dir:  $PlanCommonDirectory"
    Write-Output "  publish-lock:$PlanPublicationLock"
}

function Remove-ExactDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Attributes = [System.IO.FileAttributes]::Normal }
    Remove-Item -LiteralPath $Path -Force -Recurse
}

function Remove-WorktreeAttempt {
    param(
        [string]$Repository,
        [string]$Path,
        [string]$BranchName = ''
    )

    if (Test-RegisteredWorktree -Repository $Repository -Path $Path) {
        Invoke-NativeResult -FilePath 'git' -Arguments @(
            '-C', $Repository, 'worktree', 'remove', '--force', $Path
        ) | Out-Null
    }
    Invoke-NativeResult -FilePath 'git' -Arguments @(
        '-C', $Repository, 'worktree', 'prune'
    ) | Out-Null

    if (Test-Path -LiteralPath $Path) {
        Remove-ExactDirectory -Path $Path
    }
    Invoke-NativeResult -FilePath 'git' -Arguments @(
        '-C', $Repository, 'worktree', 'prune'
    ) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($BranchName) -and
        (Test-LocalBranch -Repository $Repository -BranchName $BranchName)) {
        Invoke-NativeResult -FilePath 'git' -Arguments @(
            '-C', $Repository, 'branch', '-D', $BranchName
        ) | Out-Null
    }

    $postconditionFailures = @()
    if (Test-RegisteredWorktree -Repository $Repository -Path $Path) {
        $postconditionFailures += "worktree metadata remains for $Path"
    }
    if (Test-Path -LiteralPath $Path) {
        $postconditionFailures += "worktree path remains at $Path"
    }
    if (-not [string]::IsNullOrWhiteSpace($BranchName) -and
        (Test-LocalBranch -Repository $Repository -BranchName $BranchName)) {
        $postconditionFailures += "branch remains at refs/heads/$BranchName"
    }
    if ($postconditionFailures.Count -gt 0) {
        throw "Worktree cleanup postcondition failed: $($postconditionFailures -join '; ')"
    }
}

function Test-CandidateReceiptsAtCommit {
    param(
        [string]$Repository,
        [string]$ReceiptPath,
        [string]$RunReceiptPath,
        [string]$Commit
    )

    $verificationPath = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ("codex-candidate-receipt-verify-" + [guid]::NewGuid().ToString('N'))
    try {
        $addResult = Invoke-NativeResult -FilePath 'git' -Arguments @(
            '-C', $Repository, 'worktree', 'add', '--detach',
            $verificationPath, $Commit
        )
        if ($addResult.ExitCode -ne 0) {
            throw "Cannot materialize immutable candidate commit: $($addResult.Output)"
        }
        $candidateContract = Join-Path $verificationPath 'tools/workbench_contract.py'
        if (-not (Test-Path -LiteralPath $candidateContract -PathType Leaf)) {
            throw "Candidate commit has no workbench contract: $candidateContract"
        }
        $verifyResult = Invoke-NativeResult -FilePath 'python' -Arguments @(
            '-B', $candidateContract, '--repo', $verificationPath,
            'lkg', 'resolve', '--candidate-receipt', $ReceiptPath,
            '--run-receipt', $RunReceiptPath
        )
        if ($verifyResult.ExitCode -ne 0) {
            throw "Last-green candidate resolution failed: $($verifyResult.Output)"
        }
    }
    finally {
        Remove-WorktreeAttempt -Repository $Repository -Path $verificationPath
    }
}

$invocationDirectory = [System.IO.Path]::GetFullPath((Get-Location).Path)
$script:GitSafeDirectory = Find-InvokingGitBoundary -StartPath $invocationDirectory
$repoRoot = Invoke-GitText -Arguments @(
    '-C', $script:GitSafeDirectory, 'rev-parse', '--show-toplevel'
)
$script:GitSafeDirectory = $repoRoot
$contractTool = Join-Path $PSScriptRoot 'workbench_contract.py'
if (-not (Test-Path -LiteralPath $contractTool -PathType Leaf)) {
    throw "Missing ownership tool: $contractTool"
}

$baselineKind = if ($FromOriginMain) { 'origin-main' } else { 'verified-lkg' }
$receiptPath = ''
$runReceiptPath = ''
foreach ($assignmentField in @{
    TaskId = $TaskId
    ThreadId = $ThreadId
    TaskBrief = $TaskBrief
    WriteSet = $WriteSet
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$assignmentField.Value)) {
        throw "$($assignmentField.Key) is required for assignment setup."
    }
}
if ($FromOriginMain) {
    if (-not [string]::IsNullOrWhiteSpace($CandidateReceipt) -or
        -not [string]::IsNullOrWhiteSpace($RunReceipt)) {
        throw '-FromOriginMain cannot be combined with candidate/run receipts.'
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($CandidateReceipt) -or
        [string]::IsNullOrWhiteSpace($RunReceipt)) {
        throw 'CandidateReceipt and RunReceipt are required unless -FromOriginMain is used.'
    }
    $receiptPath = [System.IO.Path]::GetFullPath($CandidateReceipt)
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "Candidate publication receipt does not exist: $receiptPath"
    }
    $runReceiptPath = [System.IO.Path]::GetFullPath($RunReceipt)
    if (-not (Test-Path -LiteralPath $runReceiptPath -PathType Leaf)) {
        throw "Candidate full run receipt does not exist: $runReceiptPath"
    }
}
$writeSetPath = [System.IO.Path]::GetFullPath($WriteSet)
if (-not (Test-Path -LiteralPath $writeSetPath -PathType Leaf)) {
    throw "Closed assignment write-set does not exist: $writeSetPath"
}
$writeSetValidation = Invoke-NativeResult -FilePath 'python' -Arguments @(
    '-B', $contractTool, '--repo', $repoRoot, 'validate',
    '--owner', $Owner, '--write-set', $writeSetPath
)
if ($writeSetValidation.ExitCode -ne 0) {
    throw "Closed assignment write-set failed owner validation: $($writeSetValidation.Output)"
}
$expectedLastGreen = ''
if ($FromOriginMain) {
    $fetch = Invoke-NativeResult -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'fetch', '--no-tags', 'origin',
        '+refs/heads/main:refs/remotes/origin/main'
    )
    if ($fetch.ExitCode -ne 0) {
        throw "Cannot fetch exact origin/main: $($fetch.Output)"
    }
    $baseline = Invoke-GitText -Arguments @(
        '-C', $repoRoot, 'rev-parse', '--verify',
        'refs/remotes/origin/main^{commit}'
    )
    $tree = Invoke-GitText -Arguments @(
        '-C', $repoRoot, 'rev-parse', "$baseline`^{tree}"
    )
}
else {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.status -ne 'PUBLICATION_READY' -or
        [string]::IsNullOrWhiteSpace([string]$receipt.head) -or
        [string]::IsNullOrWhiteSpace([string]$receipt.tree)) {
        throw "Receipt is not a PUBLICATION_READY candidate."
    }
    $baseline = Invoke-GitText -Arguments @(
        '-C', $repoRoot, 'rev-parse', '--verify', "$($receipt.head)`^{commit}"
    )
    $tree = Invoke-GitText -Arguments @(
        '-C', $repoRoot, 'rev-parse', "$baseline`^{tree}"
    )
    if ($baseline -ne [string]$receipt.head -or $tree -ne [string]$receipt.tree) {
        throw "Candidate receipt HEAD/tree differs from the available Git object."
    }
    $expectedLastGreen = Get-LastGreenHead -Repository $repoRoot
    if ($expectedLastGreen -ne $baseline) {
        throw (
            "Candidate receipt HEAD $baseline differs from authoritative " +
            "$($script:LastGreenRef) $expectedLastGreen."
        )
    }
}

$safeOwner = $Owner.Replace(':', '-')
if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = "codex/$safeOwner/$TaskSlug"
}
$branchCheck = Invoke-NativeResult -FilePath 'git' -Arguments @(
    '-C', $repoRoot, 'check-ref-format', '--branch', $Branch
)
if ($branchCheck.ExitCode -ne 0 -or -not $Branch.StartsWith('codex/')) {
    throw "Branch must be a valid Git branch below codex/: $Branch"
}

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
foreach ($existingWorktree in @(Get-RegisteredWorktreePaths -Repository $repoRoot)) {
    if (Test-IsWithinPath -Candidate $destinationPath -Parent $existingWorktree) {
        throw "Destination must be outside every existing worktree: $existingWorktree"
    }
}

$commonDir = Get-NormalizedPath -Path (Invoke-GitText -Arguments @(
    '-C', $repoRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir'
))
$lockResult = Invoke-NativeResult -FilePath 'python' -Arguments @(
    '-B', $contractTool, '--repo', $repoRoot, 'lock-path'
)
if ($lockResult.ExitCode -ne 0) {
    throw "Cannot resolve the shared publication lock."
}
$lockPath = $lockResult.Output

if (-not $Create) {
    # Both verifiers deliberately run in a detached worktree materialized from
    # the receipt commit. The candidate's own runner verifies the full run
    # receipt. Dirty caller state does not participate in either proof.
    if (-not $FromOriginMain) {
        Test-CandidateReceiptsAtCommit -Repository $repoRoot `
            -ReceiptPath $receiptPath `
            -RunReceiptPath $runReceiptPath -Commit $baseline
    }
    Write-AgentWorktreePlan -PlanOwner $Owner -PlanTaskSlug $TaskSlug `
        -PlanTaskId $TaskId -PlanThreadId $ThreadId `
        -PlanTaskBrief $TaskBrief -PlanWriteSet $writeSetPath `
        -PlanAckTimeoutSeconds $AckTimeoutSeconds -PlanBaselineKind $baselineKind `
        -PlanReceiptPath $receiptPath -PlanRunReceiptPath $runReceiptPath `
        -PlanBaseline $baseline -PlanTree $tree `
        -PlanLastGreenRef $script:LastGreenRef -PlanBranch $Branch `
        -PlanDestinationPath $destinationPath `
        -PlanCommonDirectory $commonDir -PlanPublicationLock $lockPath
    Write-Output "PLAN ONLY: pass -Create (or use -WhatIf with -Create) after reviewing the exact baseline and assignment."
    return
}

if ($WhatIfPreference) {
    if (-not $FromOriginMain) {
        Test-CandidateReceiptsAtCommit -Repository $repoRoot `
            -ReceiptPath $receiptPath `
            -RunReceiptPath $runReceiptPath -Commit $baseline
    }
    Write-AgentWorktreePlan -PlanOwner $Owner -PlanTaskSlug $TaskSlug `
        -PlanTaskId $TaskId -PlanThreadId $ThreadId `
        -PlanTaskBrief $TaskBrief -PlanWriteSet $writeSetPath `
        -PlanAckTimeoutSeconds $AckTimeoutSeconds -PlanBaselineKind $baselineKind `
        -PlanReceiptPath $receiptPath -PlanRunReceiptPath $runReceiptPath `
        -PlanBaseline $baseline -PlanTree $tree `
        -PlanLastGreenRef $script:LastGreenRef -PlanBranch $Branch `
        -PlanDestinationPath $destinationPath `
        -PlanCommonDirectory $commonDir -PlanPublicationLock $lockPath
}

Assert-WorktreeTargetAvailable -Repository $repoRoot `
    -DestinationPath $destinationPath -BranchName $Branch

$description = "create $Owner/$TaskSlug worktree at $destinationPath from exact $baselineKind $baseline"
if ($PSCmdlet.ShouldProcess($repoRoot, $description)) {
    $reservation = $null
    try {
        $reservation = Enter-WorktreeReservation -CommonDirectory $commonDir `
            -DestinationPath $destinationPath -BranchName $Branch
        Write-Output (
            "Shared worktree reservations acquired: " +
            ($reservation.Paths -join ', ')
        )

        # The optimistic checks above keep common failures cheap. These checks
        # are authoritative: they run after acquiring the reservation shared by
        # every linked worktree and before this invocation owns any resource.
        Assert-WorktreeTargetAvailable -Repository $repoRoot `
            -DestinationPath $destinationPath -BranchName $Branch
        if ($FromOriginMain) {
            $reservedMain = Invoke-GitText -Arguments @(
                '-C', $repoRoot, 'rev-parse', '--verify',
                'refs/remotes/origin/main^{commit}'
            )
            if ($reservedMain -ne $baseline) {
                throw "origin/main moved before materialization; rerun setup."
            }
        }
        else {
            $reservedLastGreen = Get-LastGreenHead -Repository $repoRoot
            if ($reservedLastGreen -ne $expectedLastGreen) {
                throw (
                    "$($script:LastGreenRef) moved before materialization: " +
                    "expected $expectedLastGreen, actual $reservedLastGreen."
                )
            }
        }

        # The reservation covers verification as well as final creation. This
        # prevents duplicate create processes from colliding in the verifier's
        # own shared Git/publication locks before one request is selected.
        if (-not $FromOriginMain) {
            Test-CandidateReceiptsAtCommit -Repository $repoRoot `
                -ReceiptPath $receiptPath `
                -RunReceiptPath $runReceiptPath -Commit $baseline
        }
        Write-AgentWorktreePlan -PlanOwner $Owner -PlanTaskSlug $TaskSlug `
            -PlanTaskId $TaskId -PlanThreadId $ThreadId `
            -PlanTaskBrief $TaskBrief -PlanWriteSet $writeSetPath `
            -PlanAckTimeoutSeconds $AckTimeoutSeconds -PlanBaselineKind $baselineKind `
            -PlanReceiptPath $receiptPath -PlanRunReceiptPath $runReceiptPath `
            -PlanBaseline $baseline -PlanTree $tree `
            -PlanLastGreenRef $script:LastGreenRef -PlanBranch $Branch `
            -PlanDestinationPath $destinationPath `
            -PlanCommonDirectory $commonDir -PlanPublicationLock $lockPath

        $worktreeCreatedByInvocation = $false
        $assignmentPublished = $false
        try {
            $addResult = Invoke-NativeResult -FilePath 'git' -Arguments @(
                '-C', $repoRoot, 'worktree', 'add', '-b', $Branch,
                $destinationPath, $baseline
            )
            if ($addResult.ExitCode -ne 0) {
                throw "git worktree add failed: $($addResult.Output)"
            }
            # Only a successful `git worktree add` proves this invocation owns
            # the new path and branch. A failed Git command may have raced with
            # an uncoordinated external creator, so cleanup must fail safe and
            # never delete resources whose ownership cannot be proven.
            $worktreeCreatedByInvocation = $true
            if ($FaultInjection -eq 'AfterGitWorktreeAdd') {
                throw "Injected failure after git worktree add."
            }
            if ($FaultInjection -eq 'WaitAfterGitWorktreeAdd') {
                if ([string]::IsNullOrWhiteSpace($FaultInjectionToken)) {
                    throw 'WaitAfterGitWorktreeAdd requires one unique ownership token.'
                }
                $faultReadyPath = "$destinationPath.setup-$FaultInjectionToken.ready"
                $faultContinuePath = "$destinationPath.setup-$FaultInjectionToken.continue"
                $faultEncoding = New-Object System.Text.UTF8Encoding($false)
                try {
                    $readyBytes = $faultEncoding.GetBytes($FaultInjectionToken)
                    $readyStream = [System.IO.File]::Open(
                        $faultReadyPath,
                        [System.IO.FileMode]::CreateNew,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::None
                    )
                    try {
                        $readyStream.Write($readyBytes, 0, $readyBytes.Length)
                        $readyStream.Flush($true)
                    }
                    finally { $readyStream.Dispose() }
                    $faultDeadline = [System.DateTime]::UtcNow.AddSeconds(30)
                    while ($true) {
                        if (Test-Path -LiteralPath $faultContinuePath -PathType Leaf) {
                            $continueToken = [System.IO.File]::ReadAllText(
                                $faultContinuePath,
                                $faultEncoding
                            )
                            if ($continueToken -cne $FaultInjectionToken) {
                                throw 'Controlled synchronization token does not match its owner.'
                            }
                            break
                        }
                        if ([System.DateTime]::UtcNow -ge $faultDeadline) {
                            throw 'Timed out at the controlled post-add synchronization point.'
                        }
                        Start-Sleep -Milliseconds 20
                    }
                }
                finally {
                    foreach ($ownedPath in @($faultReadyPath, $faultContinuePath)) {
                        if (Test-Path -LiteralPath $ownedPath -PathType Leaf) {
                            try {
                                if ([System.IO.File]::ReadAllText(
                                        $ownedPath,
                                        $faultEncoding
                                    ) -ceq $FaultInjectionToken) {
                                    Remove-Item -LiteralPath $ownedPath -Force
                                }
                            }
                            catch {
                                # Never delete a synchronization file whose
                                # ownership cannot be proven by exact content.
                            }
                        }
                    }
                }
            }

            $newContract = Join-Path $destinationPath 'tools/workbench_contract.py'
            $newHead = Invoke-GitText -Arguments @(
                '-C', $destinationPath, 'rev-parse', 'HEAD'
            )
            $newTree = Invoke-GitText -Arguments @(
                '-C', $destinationPath, 'rev-parse', 'HEAD^{tree}'
            )
            $postBaseline = if ($FromOriginMain) {
                Invoke-GitText -Arguments @(
                    '-C', $repoRoot, 'rev-parse', '--verify',
                    'refs/remotes/origin/main^{commit}'
                )
            }
            else {
                Get-LastGreenHead -Repository $repoRoot
            }
            if ($newHead -ne $baseline -or $newTree -ne $tree -or
                $postBaseline -ne $baseline) {
                throw (
                    "Post-materialization identity mismatch: baseline=$baseline/$tree " +
                    "worktree=$newHead/$newTree authority=$postBaseline."
                )
            }

            $doctorOwner = if ($Owner -eq 'integration') { 'integration' } else { $Owner }
            $doctorIntent = if ($Owner -eq 'integration') { 'integration' } else { 'author' }
            $doctorArguments = @(
                '-B', $newContract, '--repo', $destinationPath,
                'doctor', '--owner', $doctorOwner, '--intent', $doctorIntent
            )
            if ($Owner.StartsWith('structure:')) {
                $doctorArguments += '--allow-staging'
            }
            $doctorResult = Invoke-NativeResult -FilePath 'python' -Arguments $doctorArguments
            if ($doctorResult.ExitCode -ne 0) {
                throw "The new worktree failed its ownership doctor check."
            }

            # The immutable WAITING_ACK bundle is the final durable marker for
            # both baselines. No authoring is permitted before a separate ACK.
            # The verified-LKG create command also performs the final receipt
            # verification, so setup never runs the expensive resolver twice.
            $ackDeadline = [System.DateTime]::UtcNow.AddSeconds(
                $AckTimeoutSeconds
            ).ToString(
                'yyyy-MM-ddTHH:mm:ssZ',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            $assignmentCommand = if ($FromOriginMain) { 'create-main' } else { 'create' }
            $assignmentArguments = @(
                '-B', $newContract, '--repo', $destinationPath,
                'assignment', $assignmentCommand,
                '--task-id', $TaskId,
                '--thread-id', $ThreadId,
                '--owner', $Owner,
                '--brief', $TaskBrief,
                '--destination', $destinationPath,
                '--common-dir', $commonDir,
                '--branch', $Branch,
                '--head', $newHead,
                '--tree', $newTree,
                '--write-set', $writeSetPath,
                '--ack-deadline', $ackDeadline,
                '--json'
            )
            if (-not $FromOriginMain) {
                $assignmentArguments += @(
                    '--candidate-receipt', $receiptPath,
                    '--run-receipt', $runReceiptPath
                )
            }
            $assignmentResult = Invoke-NativeResult -FilePath 'python' `
                -Arguments $assignmentArguments
            if ($assignmentResult.ExitCode -eq 0 -and
                $FaultInjection -eq 'AfterAssignmentPublicationProcessFailure') {
                $assignmentResult = [pscustomobject]@{
                    ExitCode = 79
                    Output = 'Injected child-process failure after durable publication.'
                }
            }
            if ($assignmentResult.ExitCode -ne 0) {
                # A child can publish the immutable bundle and then die before
                # its JSON/exit status reaches setup. Re-resolve that exact
                # task and preserve resources only when every immutable field
                # matches this invocation; otherwise normal owned cleanup is safe.
                $assignmentPublished = Test-ExactPublishedAssignment `
                    -Contract $newContract -Repository $destinationPath `
                    -TaskId $TaskId -ThreadId $ThreadId -Owner $Owner `
                    -Brief $TaskBrief -Destination $destinationPath `
                    -CommonDirectory $commonDir -BranchName $Branch `
                    -Head $newHead -Tree $newTree -WriteSetPath $writeSetPath `
                    -OriginMain ([bool]$FromOriginMain)
                throw "Durable assignment creation failed: $($assignmentResult.Output)"
            }
            $assignmentPublished = $true
            Write-Output $assignmentResult.Output
            Write-Output (
                "ASSIGNMENT CREATED: WAITING_ACK. Dispatch the exact destination, " +
                "branch, HEAD/tree, owner, thread-id and write-set to the named task; " +
                "only `assignment ack` changes it to RUNNING."
            )
        }
        catch {
            $failure = $_.Exception.Message
            if ($assignmentPublished) {
                throw (
                    "Worktree setup reached its durable assignment marker; " +
                    "the assigned worktree and branch were preserved: $failure"
                )
            }
            if (-not $worktreeCreatedByInvocation) {
                throw (
                    "Worktree creation failed before this invocation proved " +
                    "ownership; no cleanup was attempted: $failure"
                )
            }
            try {
                Remove-WorktreeAttempt -Repository $repoRoot -Path $destinationPath `
                    -BranchName $Branch
            }
            catch {
                throw "Worktree creation failed: $failure Cleanup failed: $($_.Exception.Message)"
            }
            throw "Worktree creation rolled back after verification failure: $failure"
        }
    }
    finally {
        Exit-WorktreeReservation -Reservation $reservation
    }
}
