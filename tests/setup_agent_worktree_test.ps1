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
$faultWorktree = Join-Path $testRoot 'fault-worktree'
$unavailableWorktree = Join-Path $testRoot 'unavailable-worktree'
$mismatchRunWorktree = Join-Path $testRoot 'mismatch-run-worktree'
$failedRunWorktree = Join-Path $testRoot 'failed-run-worktree'
$candidateReceipt = Join-Path $testRoot 'candidate-receipt.json'
$unavailableReceipt = Join-Path $testRoot 'unavailable-receipt.json'
$runReceipt = Join-Path $testRoot 'run-receipt.json'
$mismatchRunReceipt = Join-Path $testRoot 'mismatch-run-receipt.json'
$failedRunReceipt = Join-Path $testRoot 'failed-run-receipt.json'
$inputList = Join-Path $testRoot 'inputs.txt'
$outputList = Join-Path $testRoot 'outputs.txt'
$parallelReadyA = Join-Path $testRoot 'parallel-a.ready'
$parallelReadyB = Join-Path $testRoot 'parallel-b.ready'
$parallelStartGate = Join-Path $testRoot 'parallel.start'
$parallelJobs = @()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)

    [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
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
    Invoke-Git $repository commit -q -m candidate | Out-Null

    Write-Utf8NoBom -Path $inputList -Value "src/input.txt`n"
    Write-Utf8NoBom -Path $outputList -Value "build/output.txt`n"
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

    Push-Location $repository
    try {
        $plan = & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
            -Owner root `
            -TaskSlug plan-a -Destination $worktreeA 2>&1 | Out-String
        if ($plan -notmatch 'PLAN ONLY' -or
            $plan -notmatch 'codex/root/plan-a' -or
            $plan -notmatch 'candidate-receipt' -or
            $plan -notmatch 'run-receipt') {
            throw "Plan output is incomplete: $plan"
        }
        $legacyReceiptAdjective = 'gr' + 'een'
        if ($plan -match "(?i)$legacyReceiptAdjective") {
            throw "Plan uses the forbidden legacy receipt adjective: $plan"
        }
        if (Test-Path -LiteralPath $worktreeA) {
            throw "Plan-only mode created a worktree unexpectedly: $worktreeA"
        }

        $mismatchRunRejected = $false
        try {
            & $helper -CandidateReceipt $candidateReceipt `
                -RunReceipt $mismatchRunReceipt -Owner root `
                -TaskSlug mismatch-run -Destination $mismatchRunWorktree `
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
                -TaskSlug failed-run -Destination $failedRunWorktree `
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
                -TaskSlug invalid-ref -Destination $worktreeA `
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
            -TaskSlug actual-a -Destination $worktreeA -Create | Out-Null
    }
    finally {
        Pop-Location
    }

    Write-Utf8NoBom -Path (Join-Path $repository 'src/input.txt') -Value "dirty-caller`n"
    Write-Utf8NoBom -Path (Join-Path $repository 'untracked-caller.txt') -Value "untracked-caller`n"

    $faultRejected = $false
    Push-Location $repository
    try {
        try {
            & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
                -Owner root `
                -TaskSlug fault-a -Destination $faultWorktree -Create `
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

    $parallelWorker = {
        param(
            [string]$Helper,
            [string]$Repository,
            [string]$CandidateReceipt,
            [string]$RunReceipt,
            [string]$Destination,
            [string]$ReadyPath,
            [string]$StartGate
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
                $output = & $Helper -CandidateReceipt $CandidateReceipt `
                    -RunReceipt $RunReceipt -Owner root `
                    -TaskSlug parallel-race -Destination $Destination -Create `
                    2>&1 | Out-String
                return [pscustomobject]@{
                    Succeeded = $true
                    ProcessId = $PID
                    Output = $output
                }
            }
            catch {
                return [pscustomobject]@{
                    Succeeded = $false
                    ProcessId = $PID
                    Output = (($_ | Out-String) + $_.Exception.Message)
                }
            }
        }
        finally {
            Pop-Location
        }
    }

    $parallelJobs += Start-Job -ScriptBlock $parallelWorker -ArgumentList @(
        $helper, $repository, $candidateReceipt, $runReceipt,
        $parallelWorktree, $parallelReadyA, $parallelStartGate
    )
    $parallelJobs += Start-Job -ScriptBlock $parallelWorker -ArgumentList @(
        $helper, $repository, $candidateReceipt, $runReceipt,
        $parallelWorktree, $parallelReadyB, $parallelStartGate
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

    Push-Location $repository
    try {
        & $helper -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt `
            -Owner root `
            -TaskSlug actual-b -Destination $worktreeB -Create | Out-Null
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
                -TaskSlug unavailable -Destination $unavailableWorktree 2>&1 | Out-Null
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
    foreach ($parallelJob in @($parallelJobs)) {
        if ($parallelJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $parallelJob -ErrorAction SilentlyContinue
        }
        Remove-Job -Job $parallelJob -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $repository '.git')) {
        foreach ($candidateWorktree in @(
            $worktreeA, $worktreeB, $parallelWorktree, $faultWorktree, $unavailableWorktree,
            $mismatchRunWorktree, $failedRunWorktree
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
