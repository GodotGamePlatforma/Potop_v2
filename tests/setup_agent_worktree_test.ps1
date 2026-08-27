$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/setup_agent_worktree.ps1'
$contract = Join-Path $projectRoot 'tools/workbench_contract.py'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $systemTemp ("codex-setup-agent-worktree-test-" + [guid]::NewGuid().ToString('N'))
$repository = Join-Path $testRoot 'repository'
$worktreeA = Join-Path $testRoot 'worktree-a'
$worktreeB = Join-Path $testRoot 'worktree-b'
$parallelWorktree = Join-Path $testRoot 'parallel-worktree'
$crossDestinationWorktree = Join-Path $testRoot 'cross-destination-worktree'
$crossBranchWorktreeA = Join-Path $testRoot 'cross-branch-worktree-a'
$crossBranchWorktreeB = Join-Path $testRoot 'cross-branch-worktree-b'
$faultWorktree = Join-Path $testRoot 'fault-worktree'
$overlapWorktree = Join-Path $testRoot 'overlap-worktree'
$lkgRaceWorktree = Join-Path $testRoot 'lkg-race-worktree'
$unavailableWorktree = Join-Path $testRoot 'unavailable-worktree'
$mismatchRunWorktree = Join-Path $testRoot 'mismatch-run-worktree'
$failedRunWorktree = Join-Path $testRoot 'failed-run-worktree'
$missingLkgWorktree = Join-Path $testRoot 'missing-lkg-worktree'
$legacyWorktree = Join-Path $testRoot 'legacy-worktree'
$candidateReceipt = Join-Path $testRoot 'candidate-receipt.json'
$legacyReceipt = Join-Path $testRoot 'legacy-receipt.json'
$unavailableReceipt = Join-Path $testRoot 'unavailable-receipt.json'
$runReceipt = Join-Path $testRoot 'run-receipt.json'
$mismatchRunReceipt = Join-Path $testRoot 'mismatch-run-receipt.json'
$failedRunReceipt = Join-Path $testRoot 'failed-run-receipt.json'
$legacyRunReceipt = Join-Path $testRoot 'legacy-run-receipt.json'
$inputList = Join-Path $testRoot 'inputs.txt'
$outputList = Join-Path $testRoot 'outputs.txt'
$parallelReadyA = Join-Path $testRoot 'parallel-a.ready'
$parallelReadyB = Join-Path $testRoot 'parallel-b.ready'
$parallelStartGate = Join-Path $testRoot 'parallel.start'
$parallelJobs = @()
$lkgRaceJob = $null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)

    [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
}

function New-TestWriteSet {
    param([string]$TaskSlug)

    $path = Join-Path $testRoot "write-set-$TaskSlug.txt"
    Write-Utf8NoBom -Path $path -Value "src/assignment-$TaskSlug.txt`n"
    return $path
}

function Get-TestAssignmentRecord {
    param([string]$Repo, [string]$TaskId)

    $commonDirectory = Invoke-Git $Repo rev-parse --path-format=absolute --git-common-dir
    $store = Join-Path $commonDirectory 'codex-agent-assignments/v1'
    $matches = @()
    if (Test-Path -LiteralPath $store -PathType Container) {
        foreach ($path in @(Get-ChildItem -LiteralPath $store -Recurse `
            -Filter assignment.json -File)) {
            $record = Get-Content -LiteralPath $path.FullName -Raw | ConvertFrom-Json
            if ([string]$record.task_id -eq $TaskId) {
                $matches += [pscustomobject]@{
                    Bundle = $path.Directory.FullName
                    Record = $record
                }
            }
        }
    }
    if ($matches.Count -ne 1) {
        throw "Expected one assignment for $TaskId, found $($matches.Count)."
    }
    return $matches[0]
}

function Invoke-Git {
    param([string]$Repo, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Repo @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $output"
    }
    return ($output | Out-String).Trim()
}

function Test-BranchExists {
    param([string]$Repo, [string]$Branch)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $Repo show-ref --verify --quiet "refs/heads/$Branch" 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -notin @(0, 1)) {
        throw "Cannot inspect branch $Branch"
    }
    return $exitCode -eq 0
}

function Test-WorktreeRegistered {
    param([string]$Repo, [string]$Path)

    $expected = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $porcelain = Invoke-Git $Repo worktree list --porcelain
    foreach ($line in ($porcelain -split "`r?`n")) {
        if (-not $line.StartsWith('worktree ')) {
            continue
        }
        $actual = [System.IO.Path]::GetFullPath(
            $line.Substring('worktree '.Length)
        ).TrimEnd('\', '/')
        if ([string]::Equals(
            $expected,
            $actual,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }
    return $false
}

function Assert-NoCallerLeakage {
    param([string]$Worktree)

    if ((Get-Content -LiteralPath (Join-Path $Worktree 'src/input.txt') -Raw) -match 'dirty-caller' -or
        (Test-Path -LiteralPath (Join-Path $Worktree 'untracked-caller.txt'))) {
        throw "Dirty or untracked caller state leaked into $Worktree"
    }
}

try {
    New-Item -ItemType Directory -Path $repository -Force | Out-Null
    & git init -q $repository
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    Invoke-Git $repository config user.email 'worktree-test@example.invalid' | Out-Null
    Invoke-Git $repository config user.name 'Worktree Test' | Out-Null
    Invoke-Git $repository config core.autocrlf false | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repository 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repository 'build') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repository 'tests') -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $repository 'src/input.txt') -Value "input-v1`n"
    Write-Utf8NoBom -Path (Join-Path $repository 'build/output.txt') -Value "output-v1`n"
    Write-Utf8NoBom -Path (Join-Path $repository 'tests/run_all_tests.ps1') -Value @'
#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$VerifyRunReceipt,
    [string]$CandidateReceipt
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSBoundParameters.Count -ne 2 -or
    [string]::IsNullOrWhiteSpace($VerifyRunReceipt) -or
    [string]::IsNullOrWhiteSpace($CandidateReceipt)) {
    throw 'Both receipt verifier arguments are required and exclusive.'
}
if (-not (Test-Path -LiteralPath $VerifyRunReceipt -PathType Leaf) -or
    -not (Test-Path -LiteralPath $CandidateReceipt -PathType Leaf)) {
    throw 'A receipt path is unavailable.'
}

$candidate = Get-Content -LiteralPath $CandidateReceipt -Raw | ConvertFrom-Json
$run = Get-Content -LiteralPath $VerifyRunReceipt -Raw | ConvertFrom-Json
$repo = Split-Path -Parent $PSScriptRoot
$head = (& git -C $repo rev-parse HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve candidate HEAD.' }
$tree = (& git -C $repo rev-parse 'HEAD^{tree}' 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve candidate tree.' }
$status = (& git -C $repo status --porcelain --untracked-files=all 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($status)) {
    throw 'Candidate verifier requires a clean exact worktree.'
}
if ($candidate.status -ne 'PUBLICATION_READY' -or
    [int]$candidate.schema_version -ne 1 -or
    [string]$candidate.head -ne $head -or
    [string]$candidate.tree -ne $tree) {
    throw 'Candidate receipt does not bind this HEAD/tree.'
}
$requiredRunFields = @(
    'head', 'tree', 'suite_mode', 'target_scope', 'overall',
    'fail_count', 'skip_count', 'blocking_failure_count'
)
foreach ($field in $requiredRunFields) {
    if ($run.PSObject.Properties.Name -notcontains $field) {
        throw "Run receipt lacks required field: $field"
    }
}
if ([string]$run.head -ne $head -or [string]$run.tree -ne $tree -or
    [string]$run.suite_mode -notin @('full', 'full-with-snapshots') -or
    [string]$run.target_scope -ne 'full' -or [string]$run.overall -ne 'PASS' -or
    [int]$run.fail_count -ne 0 -or [int]$run.skip_count -ne 0 -or
    [int]$run.blocking_failure_count -ne 0) {
    throw 'Run receipt is not the exact required full-suite PASS.'
}
Write-Output "RUN RECEIPT VERIFIED: $head/$tree"
'@
    Invoke-Git $repository add src/input.txt build/output.txt tests/run_all_tests.ps1 | Out-Null
    Invoke-Git $repository commit -q -m 'legacy candidate without LKG resolver' | Out-Null

    Write-Utf8NoBom -Path $inputList -Value "src/input.txt`n"
    Write-Utf8NoBom -Path $outputList -Value "build/output.txt`n"
    & python -B $contract --repo $repository publication create `
        --input-list $inputList --output-list $outputList `
        --input-root src --output-root build --receipt $legacyReceipt
    if ($LASTEXITCODE -ne 0) { throw 'legacy publication receipt create failed' }
    $legacyReceiptData = Get-Content -LiteralPath $legacyReceipt -Raw | ConvertFrom-Json
    $legacyRunData = [ordered]@{
        head = [string]$legacyReceiptData.head
        tree = [string]$legacyReceiptData.tree
        suite_mode = 'full'
        target_scope = 'full'
        overall = 'PASS'
        fail_count = 0
        skip_count = 0
        blocking_failure_count = 0
    }
    Write-Utf8NoBom -Path $legacyRunReceipt -Value (
        ($legacyRunData | ConvertTo-Json -Depth 10) + "`n"
    )

    New-Item -ItemType Directory -Path (Join-Path $repository 'tools') -Force | Out-Null
    Copy-Item -LiteralPath $contract `
        -Destination (Join-Path $repository 'tools/workbench_contract.py')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/workbench_lock.py') `
        -Destination (Join-Path $repository 'tools/workbench_lock.py')
    Invoke-Git $repository add `
        tools/workbench_contract.py tools/workbench_lock.py | Out-Null
    Invoke-Git $repository commit -q -m 'candidate with LKG resolver' | Out-Null

    & python -B $contract --repo $repository publication create `
        --input-list $inputList --output-list $outputList `
        --input-root src --output-root build --receipt $candidateReceipt
    if ($LASTEXITCODE -ne 0) { throw 'publication receipt create failed' }
    $receiptData = Get-Content -LiteralPath $candidateReceipt -Raw | ConvertFrom-Json
    $runReceiptData = [ordered]@{
        head = [string]$receiptData.head
        tree = [string]$receiptData.tree
        suite_mode = 'full'
        target_scope = 'full'
        overall = 'PASS'
        fail_count = 0
        skip_count = 0
        blocking_failure_count = 0
    }
    Write-Utf8NoBom -Path $runReceipt -Value (
        ($runReceiptData | ConvertTo-Json -Depth 10) + "`n"
    )

    $mismatchRunData = Get-Content -LiteralPath $runReceipt -Raw | ConvertFrom-Json
    $mismatchRunData.tree = '0' * ([string]$mismatchRunData.tree).Length
    Write-Utf8NoBom -Path $mismatchRunReceipt -Value (
        ($mismatchRunData | ConvertTo-Json -Depth 10) + "`n"
    )
    $failedRunData = Get-Content -LiteralPath $runReceipt -Raw | ConvertFrom-Json
    $failedRunData.overall = 'FAIL'
    $failedRunData.fail_count = 1
    Write-Utf8NoBom -Path $failedRunReceipt -Value (
        ($failedRunData | ConvertTo-Json -Depth 10) + "`n"
    )

    $missingLkgRejected = $false
    Push-Location $repository
    try {
        try {
            & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
                -Owner root -TaskSlug missing-lkg `
                -TaskId 'task/missing-lkg' -ThreadId 'thread/missing-lkg' `
                -TaskBrief 'missing LKG rejection' `
                -WriteSet (New-TestWriteSet -TaskSlug 'missing-lkg') `
                -Destination $missingLkgWorktree 2>&1 | Out-Null
        }
        catch {
            $missingLkgRejected = $_.Exception.Message -match 'last-green ref is missing'
        }
    }
    finally {
        Pop-Location
    }
    if (-not $missingLkgRejected -or (Test-Path -LiteralPath $missingLkgWorktree)) {
        throw 'Setup accepted a candidate while authoritative local LKG was missing.'
    }

    Invoke-Git $repository update-ref refs/last-green/integration `
        ([string]$legacyReceiptData.head) | Out-Null
    $legacyRejected = $false
    $legacyFailure = ''
    Push-Location $repository
    try {
        try {
            & $helper -CandidateReceipt $legacyReceipt `
                -RunReceipt $legacyRunReceipt -Owner root `
                -TaskSlug legacy-candidate -TaskId 'task/legacy-candidate' `
                -ThreadId 'thread/legacy-candidate' `
                -TaskBrief 'legacy candidate rejection' `
                -WriteSet (New-TestWriteSet -TaskSlug 'legacy-candidate') `
                -Destination $legacyWorktree 2>&1 | Out-Null
        }
        catch {
            $legacyRejected = $true
            $legacyFailure = $_.Exception.Message
        }
    }
    finally {
        Pop-Location
    }
    if (-not $legacyRejected -or $legacyFailure -notmatch 'no workbench contract' -or
        (Test-Path -LiteralPath $legacyWorktree)) {
        throw 'Historical candidate without the LKG resolver did not fail closed.'
    }

    & python -B $contract --repo $repository lkg promote `
        --candidate-receipt $candidateReceipt --run-receipt $runReceipt `
        --expected-old ([string]$legacyReceiptData.head)
    if ($LASTEXITCODE -ne 0) { throw 'LKG CAS promotion failed' }

    Push-Location $repository
    try {
        $plan = & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
            -Owner root `
            -TaskSlug plan-a -TaskId 'task/plan-a' -ThreadId 'thread/plan-a' `
            -TaskBrief 'plan assignment' `
            -WriteSet (New-TestWriteSet -TaskSlug 'plan-a') `
            -Destination $worktreeA 2>&1 | Out-String
        if ($plan -notmatch 'PLAN ONLY' -or
            $plan -notmatch 'codex/root/plan-a' -or
            $plan -notmatch 'task/plan-a' -or
            $plan -notmatch 'thread/plan-a' -or
            $plan -notmatch 'prospective WAITING_ACK' -or
            $plan -notmatch 'candidate-receipt' -or
            $plan -notmatch 'run-receipt' -or
            $plan -notmatch 'refs/last-green/integration') {
            throw "Plan output is incomplete: $plan"
        }
        if ($plan -match '(?i)green[- ]?(baseline|receipt)') {
            throw "Plan uses a forbidden legacy receipt label: $plan"
        }
        if (Test-Path -LiteralPath $worktreeA) {
            throw "Plan-only mode created a worktree unexpectedly: $worktreeA"
        }

        $mismatchRunRejected = $false
        try {
            & $helper -CandidateReceipt $candidateReceipt `
                -RunReceipt $mismatchRunReceipt -Owner root `
                -TaskSlug mismatch-run -TaskId 'task/mismatch-run' `
                -ThreadId 'thread/mismatch-run' -TaskBrief 'mismatch run' `
                -WriteSet (New-TestWriteSet -TaskSlug 'mismatch-run') `
                -Destination $mismatchRunWorktree `
                2>&1 | Out-Null
        }
        catch {
            $mismatchRunRejected = $true
        }
        if (-not $mismatchRunRejected -or
            (Test-Path -LiteralPath $mismatchRunWorktree) -or
            (Test-WorktreeRegistered -Repo $repository -Path $mismatchRunWorktree) -or
            (Test-BranchExists -Repo $repository -Branch 'codex/root/mismatch-run')) {
            throw 'Run receipt with mismatched tree was accepted.'
        }

        $failedRunRejected = $false
        try {
            & $helper -CandidateReceipt $candidateReceipt `
                -RunReceipt $failedRunReceipt -Owner root `
                -TaskSlug failed-run -TaskId 'task/failed-run' `
                -ThreadId 'thread/failed-run' -TaskBrief 'failed run' `
                -WriteSet (New-TestWriteSet -TaskSlug 'failed-run') `
                -Destination $failedRunWorktree `
                2>&1 | Out-Null
        }
        catch {
            $failedRunRejected = $true
        }
        if (-not $failedRunRejected -or
            (Test-Path -LiteralPath $failedRunWorktree) -or
            (Test-WorktreeRegistered -Repo $repository -Path $failedRunWorktree) -or
            (Test-BranchExists -Repo $repository -Branch 'codex/root/failed-run')) {
            throw 'Non-PASS full run receipt was accepted.'
        }

        $invalidRefRejected = $false
        try {
            & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
                -Owner root `
                -TaskSlug invalid-ref -TaskId 'task/invalid-ref' `
                -ThreadId 'thread/invalid-ref' -TaskBrief 'invalid ref' `
                -WriteSet (New-TestWriteSet -TaskSlug 'invalid-ref') `
                -Destination $worktreeA `
                -Branch 'codex/root/bad..ref' 2>&1 | Out-Null
        }
        catch {
            $invalidRefRejected = $true
        }
        if (-not $invalidRefRejected) {
            throw 'Invalid Git branch ref was accepted.'
        }

        & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
            -Owner root `
            -TaskSlug actual-a -TaskId 'task/actual-a' -ThreadId 'thread/actual-a' `
            -TaskBrief 'actual assignment A' `
            -WriteSet (New-TestWriteSet -TaskSlug 'actual-a') `
            -Destination $worktreeA -Create | Out-Null
    }
    finally {
        Pop-Location
    }

    # A created worktree is only WAITING_ACK. The exact task must acknowledge
    # from that clean destination before any authoring is considered RUNNING.
    $assignmentA = Get-TestAssignmentRecord -Repo $repository -TaskId 'task/actual-a'
    if (-not (Test-Path -LiteralPath (Join-Path $assignmentA.Bundle 'assignment.json') `
        -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $assignmentA.Bundle 'ack.json'))) {
        throw 'Setup did not leave one immutable WAITING_ACK assignment bundle.'
    }
    $actualAWriteSet = New-TestWriteSet -TaskSlug 'actual-a'
    $worktreeAContract = Join-Path $worktreeA 'tools/workbench_contract.py'
    $ackOutput = & python -B $worktreeAContract --repo $worktreeA `
        assignment ack --task-id 'task/actual-a' `
        --assignment-id ([string]$assignmentA.Record.assignment_id) `
        --thread-id 'thread/actual-a' --owner root `
        --write-set $actualAWriteSet --json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $ackOutput -notmatch '"state": "RUNNING"' -or
        -not (Test-Path -LiteralPath (Join-Path $assignmentA.Bundle 'ack.json') `
            -PathType Leaf)) {
        throw "Exact assignment ACK failed: $ackOutput"
    }
    $assignmentValidate = & python -B $worktreeAContract --repo $worktreeA `
        validate --owner root --assignment ([string]$assignmentA.Record.assignment_id) `
        --task-id 'task/actual-a' --thread-id 'thread/actual-a' --diff 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $assignmentValidate -notmatch 'PASS owner=root paths=0') {
        throw "Acknowledged assignment did not validate its clean diff: $assignmentValidate"
    }

    # An overlapping active write-set is detected only after the second exact
    # worktree exists; setup must roll back only that invocation and preserve
    # the running winner and its immutable bundle.
    $overlapRejected = $false
    Push-Location $repository
    try {
        try {
            & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
                -Owner root -TaskSlug overlap-a -TaskId 'task/overlap-a' `
                -ThreadId 'thread/overlap-a' -TaskBrief 'overlap rollback' `
                -WriteSet $actualAWriteSet -Destination $overlapWorktree `
                -Create 2>&1 | Out-Null
        }
        catch {
            $overlapRejected = $_.Exception.Message -match 'overlaps'
        }
    }
    finally {
        Pop-Location
    }
    if (-not $overlapRejected -or (Test-Path -LiteralPath $overlapWorktree) -or
        (Test-WorktreeRegistered -Repo $repository -Path $overlapWorktree) -or
        (Test-BranchExists -Repo $repository -Branch 'codex/root/overlap-a') -or
        -not (Test-WorktreeRegistered -Repo $repository -Path $worktreeA) -or
        -not (Test-Path -LiteralPath (Join-Path $assignmentA.Bundle 'ack.json'))) {
        throw 'Assignment overlap rollback damaged the running winning worktree.'
    }

    Write-Utf8NoBom -Path (Join-Path $repository 'src/input.txt') -Value "dirty-caller`n"
    Write-Utf8NoBom -Path (Join-Path $repository 'untracked-caller.txt') -Value "untracked-caller`n"

    $faultRejected = $false
    Push-Location $repository
    try {
        try {
            & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
                -Owner root `
                -TaskSlug fault-a -TaskId 'task/fault-a' -ThreadId 'thread/fault-a' `
                -TaskBrief 'fault rollback' `
                -WriteSet (New-TestWriteSet -TaskSlug 'fault-a') `
                -Destination $faultWorktree -Create `
                -FaultInjection AfterGitWorktreeAdd 2>&1 | Out-Null
        }
        catch {
            $faultRejected = $true
        }
    }
    finally {
        Pop-Location
    }
    if (-not $faultRejected) {
        throw 'Controlled post-add fault injection did not fail.'
    }
    if ((Test-Path -LiteralPath $faultWorktree) -or
        (Test-WorktreeRegistered -Repo $repository -Path $faultWorktree) -or
        (Test-BranchExists -Repo $repository -Branch 'codex/root/fault-a')) {
        throw 'Partial git worktree add was not fully rolled back.'
    }

    $lkgRaceWorker = {
        param(
            [string]$Helper,
            [string]$Repository,
            [string]$CandidateReceipt,
            [string]$RunReceipt,
            [string]$Destination,
            [string]$WriteSetPath
        )

        $ErrorActionPreference = 'Stop'
        Push-Location $Repository
        try {
            try {
                $output = & $Helper -CandidateReceipt $CandidateReceipt `
                    -RunReceipt $RunReceipt -Owner root -TaskSlug lkg-race `
                    -TaskId 'task/lkg-race' -ThreadId 'thread/lkg-race' `
                    -TaskBrief 'LKG race rollback' -WriteSet $WriteSetPath `
                    -Destination $Destination -Create 2>&1 | Out-String
                return [pscustomobject]@{ Succeeded = $true; Output = $output }
            }
            catch {
                return [pscustomobject]@{
                    Succeeded = $false
                    Output = (($_ | Out-String) + $_.Exception.Message)
                }
            }
        }
        finally {
            Pop-Location
        }
    }
    $lkgRaceJob = Start-Job -ScriptBlock $lkgRaceWorker -ArgumentList @(
        $helper, $repository, $candidateReceipt, $runReceipt, $lkgRaceWorktree,
        (New-TestWriteSet -TaskSlug 'lkg-race')
    )
    $lkgRaceDeadline = [System.DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-BranchExists -Repo $repository -Branch 'codex/root/lkg-race')) {
        if ($lkgRaceJob.State -in @('Completed', 'Failed', 'Stopped')) {
            break
        }
        if ([System.DateTime]::UtcNow -ge $lkgRaceDeadline) {
            throw 'Timed out waiting for post-materialization LKG race window.'
        }
        Start-Sleep -Milliseconds 10
    }
    Invoke-Git $repository update-ref refs/last-green/integration `
        ([string]$legacyReceiptData.head) ([string]$receiptData.head) | Out-Null
    Wait-Job -Job $lkgRaceJob -Timeout 30 | Out-Null
    if ($lkgRaceJob.State -notin @('Completed', 'Failed')) {
        throw 'LKG race setup process did not finish within 30 seconds.'
    }
    $lkgRaceResult = Receive-Job -Job $lkgRaceJob
    if ($null -eq $lkgRaceResult -or $lkgRaceResult.Succeeded -eq $true -or
        [string]$lkgRaceResult.Output -notmatch 'last-green|Last-green' -or
        (Test-Path -LiteralPath $lkgRaceWorktree) -or
        (Test-WorktreeRegistered -Repo $repository -Path $lkgRaceWorktree) -or
        (Test-BranchExists -Repo $repository -Branch 'codex/root/lkg-race')) {
        throw 'Post-materialization LKG race did not fail closed and roll back.'
    }
    Remove-Job -Job $lkgRaceJob -Force -ErrorAction SilentlyContinue
    $lkgRaceJob = $null
    Invoke-Git $repository update-ref refs/last-green/integration `
        ([string]$receiptData.head) ([string]$legacyReceiptData.head) | Out-Null

    $parallelWorker = {
        param(
            [string]$Helper,
            [string]$Repository,
            [string]$CandidateReceipt,
            [string]$RunReceipt,
            [string]$Destination,
            [string]$ReadyPath,
            [string]$StartGate,
            [string]$WorkerTaskSlug,
            [string]$WorkerBranch,
            [string]$WriteSetPath
        )

        $ErrorActionPreference = 'Stop'
        Set-StrictMode -Version Latest
        [System.IO.File]::WriteAllText($ReadyPath, [string]$PID)
        $startDeadline = [System.DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path -LiteralPath $StartGate -PathType Leaf)) {
            if ([System.DateTime]::UtcNow -ge $startDeadline) {
                throw 'Timed out waiting for the parallel process start gate.'
            }
            Start-Sleep -Milliseconds 20
        }

        Push-Location $Repository
        try {
            try {
                $helperArguments = @{
                    CandidateReceipt = $CandidateReceipt
                    RunReceipt = $RunReceipt
                    Owner = 'root'
                    TaskSlug = $WorkerTaskSlug
                    TaskId = "task/$WorkerTaskSlug"
                    ThreadId = "thread/$WorkerTaskSlug"
                    TaskBrief = "parallel setup $WorkerTaskSlug"
                    WriteSet = $WriteSetPath
                    Destination = $Destination
                    Create = $true
                }
                if (-not [string]::IsNullOrWhiteSpace($WorkerBranch)) {
                    $helperArguments.Branch = $WorkerBranch
                }
                $output = & $Helper @helperArguments 2>&1 | Out-String
                return [pscustomobject]@{
                    Succeeded = $true
                    ProcessId = $PID
                    Output = $output
                    Destination = $Destination
                    TaskSlug = $WorkerTaskSlug
                    Branch = $WorkerBranch
                }
            }
            catch {
                return [pscustomobject]@{
                    Succeeded = $false
                    ProcessId = $PID
                    Output = (($_ | Out-String) + $_.Exception.Message)
                    Destination = $Destination
                    TaskSlug = $WorkerTaskSlug
                    Branch = $WorkerBranch
                }
            }
        }
        finally {
            Pop-Location
        }
    }

    function Invoke-CrossAxisSetupRace {
        param(
            [string]$CaseName,
            [string]$DestinationA,
            [string]$DestinationB,
            [string]$TaskSlugA,
            [string]$TaskSlugB,
            [string]$BranchA = '',
            [string]$BranchB = ''
        )

        $readyA = Join-Path $testRoot "$CaseName-a.ready"
        $readyB = Join-Path $testRoot "$CaseName-b.ready"
        $startGate = Join-Path $testRoot "$CaseName.start"
        $jobs = @()
        try {
            $jobs += Start-Job -ScriptBlock $parallelWorker -ArgumentList @(
                $helper, $repository, $candidateReceipt, $runReceipt,
                $DestinationA, $readyA, $startGate, $TaskSlugA, $BranchA,
                (New-TestWriteSet -TaskSlug $TaskSlugA)
            )
            $jobs += Start-Job -ScriptBlock $parallelWorker -ArgumentList @(
                $helper, $repository, $candidateReceipt, $runReceipt,
                $DestinationB, $readyB, $startGate, $TaskSlugB, $BranchB,
                (New-TestWriteSet -TaskSlug $TaskSlugB)
            )
            $readyDeadline = [System.DateTime]::UtcNow.AddSeconds(15)
            while (-not (
                (Test-Path -LiteralPath $readyA -PathType Leaf) -and
                (Test-Path -LiteralPath $readyB -PathType Leaf)
            )) {
                if ([System.DateTime]::UtcNow -ge $readyDeadline) {
                    throw "$CaseName workers did not reach their shared start gate."
                }
                Start-Sleep -Milliseconds 20
            }
            Write-Utf8NoBom -Path $startGate -Value "start`n"
            Wait-Job -Job $jobs -Timeout 60 | Out-Null
            if (@($jobs | Where-Object {
                $_.State -notin @('Completed', 'Failed')
            }).Count -gt 0) {
                throw "$CaseName workers did not finish within 60 seconds."
            }
            $results = @(Receive-Job -Job $jobs -ErrorAction SilentlyContinue)
            $successes = @($results | Where-Object { $_.Succeeded -eq $true })
            $failures = @($results | Where-Object { $_.Succeeded -ne $true })
            if ($successes.Count -ne 1 -or $failures.Count -ne 1) {
                throw (
                    "$CaseName must produce one winner and one loser. " +
                    (($results | ForEach-Object { $_.Output }) -join "`n")
                )
            }
            $winner = $successes[0]
            $loser = $failures[0]
            $winnerBranch = if ([string]::IsNullOrWhiteSpace($winner.Branch)) {
                "codex/root/$($winner.TaskSlug)"
            }
            else {
                [string]$winner.Branch
            }
            if ([string]$loser.Output -notmatch 'Shared worktree reservation' -or
                -not (Test-Path -LiteralPath $winner.Destination -PathType Container) -or
                -not (Test-WorktreeRegistered -Repo $repository `
                    -Path $winner.Destination) -or
                -not (Test-BranchExists -Repo $repository -Branch $winnerBranch) -or
                ((Test-Path -LiteralPath $loser.Destination -PathType Container) -and
                    [string]$loser.Destination -ne [string]$winner.Destination)) {
                throw "$CaseName loser damaged or bypassed the winning resource."
            }
        }
        finally {
            foreach ($job in @($jobs)) {
                if ($job.State -notin @('Completed', 'Failed', 'Stopped')) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                }
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $parallelJobs += Start-Job -ScriptBlock $parallelWorker -ArgumentList @(
        $helper, $repository, $candidateReceipt, $runReceipt,
        $parallelWorktree, $parallelReadyA, $parallelStartGate,
        'parallel-race', '', (New-TestWriteSet -TaskSlug 'parallel-race')
    )
    $parallelJobs += Start-Job -ScriptBlock $parallelWorker -ArgumentList @(
        $helper, $repository, $candidateReceipt, $runReceipt,
        $parallelWorktree, $parallelReadyB, $parallelStartGate,
        'parallel-race', '', (New-TestWriteSet -TaskSlug 'parallel-race')
    )

    $readyDeadline = [System.DateTime]::UtcNow.AddSeconds(15)
    while (-not (
        (Test-Path -LiteralPath $parallelReadyA -PathType Leaf) -and
        (Test-Path -LiteralPath $parallelReadyB -PathType Leaf)
    )) {
        if ([System.DateTime]::UtcNow -ge $readyDeadline) {
            throw 'Two PowerShell worker processes did not reach the parallel start gate.'
        }
        Start-Sleep -Milliseconds 20
    }
    $parallelProcessIds = @(
        (Get-Content -LiteralPath $parallelReadyA -Raw).Trim(),
        (Get-Content -LiteralPath $parallelReadyB -Raw).Trim()
    )
    if (@($parallelProcessIds | Select-Object -Unique).Count -ne 2) {
        throw 'The concurrency regression did not use two distinct processes.'
    }
    Write-Utf8NoBom -Path $parallelStartGate -Value "start`n"

    Wait-Job -Job $parallelJobs -Timeout 60 | Out-Null
    if (@($parallelJobs | Where-Object { $_.State -notin @('Completed', 'Failed') }).Count -gt 0) {
        throw 'Parallel setup processes did not finish within 60 seconds.'
    }
    $parallelResults = @(
        Receive-Job -Job $parallelJobs -ErrorAction SilentlyContinue
    )
    if ($parallelResults.Count -ne 2) {
        $jobReasons = @(
            $parallelJobs | ForEach-Object {
                if ($null -ne $_.ChildJobs[0].JobStateInfo.Reason) {
                    $_.ChildJobs[0].JobStateInfo.Reason.Message
                }
            }
        ) -join '; '
        throw "Parallel setup processes did not return two results: $jobReasons"
    }
    $parallelSuccesses = @(
        $parallelResults | Where-Object { $_.Succeeded -eq $true }
    )
    $parallelFailures = @(
        $parallelResults | Where-Object { $_.Succeeded -ne $true }
    )
    if ($parallelSuccesses.Count -ne 1 -or $parallelFailures.Count -ne 1) {
        throw (
            "Parallel setup must produce exactly one success and one failure. " +
            (($parallelResults | ForEach-Object { $_.Output }) -join "`n")
        )
    }
    if ([string]$parallelFailures[0].Output -notmatch 'Shared worktree reservation') {
        throw "Parallel loser did not report a clear reservation conflict: $($parallelFailures[0].Output)"
    }
    if (-not (Test-Path -LiteralPath $parallelWorktree -PathType Container) -or
        -not (Test-WorktreeRegistered -Repo $repository -Path $parallelWorktree) -or
        -not (Test-BranchExists -Repo $repository -Branch 'codex/root/parallel-race')) {
        throw 'Parallel loser removed or invalidated the winning worktree resource.'
    }
    $parallelHead = Invoke-Git $parallelWorktree rev-parse HEAD
    $parallelTree = Invoke-Git $parallelWorktree rev-parse 'HEAD^{tree}'
    $parallelBranch = Invoke-Git $parallelWorktree branch --show-current
    if ($parallelHead -ne [string]$receiptData.head -or
        $parallelTree -ne [string]$receiptData.tree -or
        $parallelBranch -ne 'codex/root/parallel-race') {
        throw 'Winning parallel worktree does not match the candidate HEAD/tree/branch.'
    }
    Assert-NoCallerLeakage -Worktree $parallelWorktree

    Invoke-CrossAxisSetupRace -CaseName 'cross-destination' `
        -DestinationA $crossDestinationWorktree `
        -DestinationB $crossDestinationWorktree `
        -TaskSlugA 'cross-dest-a' -TaskSlugB 'cross-dest-b'
    Invoke-CrossAxisSetupRace -CaseName 'cross-branch' `
        -DestinationA $crossBranchWorktreeA `
        -DestinationB $crossBranchWorktreeB `
        -TaskSlugA 'cross-branch-a' -TaskSlugB 'cross-branch-b' `
        -BranchA 'codex/root/shared-cross-branch' `
        -BranchB 'codex/root/shared-cross-branch'

    Push-Location $repository
    try {
        & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
            -Owner root `
            -TaskSlug actual-b -TaskId 'task/actual-b' -ThreadId 'thread/actual-b' `
            -TaskBrief 'actual assignment B' `
            -WriteSet (New-TestWriteSet -TaskSlug 'actual-b') `
            -Destination $worktreeB -Create | Out-Null
    }
    finally {
        Pop-Location
    }

    $expectedHead = [string]$receiptData.head
    $expectedTree = [string]$receiptData.tree
    foreach ($record in @(
        @{ Path = $worktreeA; Branch = 'codex/root/actual-a' },
        @{ Path = $worktreeB; Branch = 'codex/root/actual-b' },
        @{ Path = $parallelWorktree; Branch = 'codex/root/parallel-race' }
    )) {
        $actualHead = Invoke-Git $record.Path rev-parse HEAD
        $actualTree = Invoke-Git $record.Path rev-parse 'HEAD^{tree}'
        $actualBranch = Invoke-Git $record.Path branch --show-current
        if ($actualHead -ne $expectedHead -or
            $actualTree -ne $expectedTree -or
            $actualBranch -ne $record.Branch) {
            throw "Candidate worktree does not match receipt HEAD/tree/branch: $($record.Path)"
        }
        Assert-NoCallerLeakage -Worktree $record.Path
    }

    $sourceCommon = Invoke-Git $repository rev-parse --path-format=absolute --git-common-dir
    foreach ($candidateWorktree in @($worktreeA, $worktreeB, $parallelWorktree)) {
        $candidateCommon = Invoke-Git $candidateWorktree rev-parse --path-format=absolute --git-common-dir
        if ([System.IO.Path]::GetFullPath($sourceCommon) -ne
            [System.IO.Path]::GetFullPath($candidateCommon)) {
            throw "Candidate worktree does not share Git common-dir: $candidateWorktree"
        }
    }

    $callerStatus = Invoke-Git $repository status --porcelain
    if ($callerStatus -notmatch 'src/input.txt' -or
        $callerStatus -notmatch 'untracked-caller.txt') {
        throw 'Helper unexpectedly cleaned or transferred caller changes.'
    }

    $unavailable = Get-Content -LiteralPath $candidateReceipt -Raw | ConvertFrom-Json
    $unavailable.head = '0' * ([string]$unavailable.head).Length
    Write-Utf8NoBom -Path $unavailableReceipt -Value (
        ($unavailable | ConvertTo-Json -Depth 20) + "`n"
    )
    $unavailableRejected = $false
    Push-Location $repository
    try {
        try {
            & $helper -CandidateReceipt $unavailableReceipt -RunReceipt $runReceipt `
                -Owner root `
                -TaskSlug unavailable -TaskId 'task/unavailable' `
                -ThreadId 'thread/unavailable' -TaskBrief 'unavailable commit' `
                -WriteSet (New-TestWriteSet -TaskSlug 'unavailable') `
                -Destination $unavailableWorktree 2>&1 | Out-Null
        }
        catch {
            $unavailableRejected = $true
        }
    }
    finally {
        Pop-Location
    }
    if (-not $unavailableRejected -or
        (Test-Path -LiteralPath $unavailableWorktree) -or
        (Test-BranchExists -Repo $repository -Branch 'codex/root/unavailable')) {
        throw 'Receipt with an unavailable commit object was accepted.'
    }

    Write-Host 'PASS setup_agent_worktree candidate/full-run receipts/parallel reservation/dirty isolation/rollback contract'
}
finally {
    if ($null -ne $lkgRaceJob) {
        if ($lkgRaceJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $lkgRaceJob -ErrorAction SilentlyContinue
        }
        Remove-Job -Job $lkgRaceJob -Force -ErrorAction SilentlyContinue
    }
    foreach ($parallelJob in @($parallelJobs)) {
        if ($parallelJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $parallelJob -ErrorAction SilentlyContinue
        }
        Remove-Job -Job $parallelJob -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $repository '.git')) {
        foreach ($candidateWorktree in @(
            $worktreeA, $worktreeB, $parallelWorktree,
            $crossDestinationWorktree, $crossBranchWorktreeA,
            $crossBranchWorktreeB, $faultWorktree, $overlapWorktree,
            $lkgRaceWorktree, $unavailableWorktree,
            $mismatchRunWorktree, $failedRunWorktree, $missingLkgWorktree,
            $legacyWorktree
        )) {
            if (Test-Path -LiteralPath $candidateWorktree) {
                $removeResult = & git -C $repository worktree remove --force $candidateWorktree 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Final test cleanup could not unregister $candidateWorktree`: $removeResult"
                }
            }
        }
        & git -C $repository worktree prune 2>&1 | Out-Null
    }
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith(
        $systemTemp + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -and [System.IO.Path]::GetFileName($resolvedTestRoot).StartsWith(
        'codex-setup-agent-worktree-test-'
    )) {
        if (Test-Path -LiteralPath $resolvedTestRoot) {
            Get-ChildItem -LiteralPath $resolvedTestRoot -Force -Recurse |
                ForEach-Object { $_.Attributes = [System.IO.FileAttributes]::Normal }
            Remove-Item -LiteralPath $resolvedTestRoot -Force -Recurse
        }
    }
}
