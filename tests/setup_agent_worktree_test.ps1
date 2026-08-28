#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/setup_agent_worktree.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-simple-worktree-test-" + [guid]::NewGuid().ToString('N'))
$hostPowerShell = if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Join-Path $PSHOME 'powershell.exe'
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}

function Git-Result {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git.exe -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = Git-Result $Repository @Arguments
    if ($result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($result.Output)"
    }
    return $result.Output
}

function Run-Helper {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $hostPowerShell -NoLogo -NoProfile -File $helper @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $remote = Join-Path $tempRoot 'origin.git'
    $seed = Join-Path $tempRoot 'seed'
    $primary = Join-Path $tempRoot 'primary'
    Git $tempRoot init --bare $remote | Out-Null
    Git $tempRoot init -b main $seed | Out-Null
    Git $seed config user.email 'agent-test@example.invalid' | Out-Null
    Git $seed config user.name 'Agent Test' | Out-Null
    Git $seed lfs install --local | Out-Null
    Git $seed lfs track '*.bin' | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $seed 'tools'),(Join-Path $seed '.githooks') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/install_agent_git_hooks.ps1') -Destination (Join-Path $seed 'tools/install_agent_git_hooks.ps1')
    Copy-Item -LiteralPath (Join-Path $projectRoot '.githooks/pre-push') -Destination (Join-Path $seed '.githooks/pre-push')
    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'one' -Encoding UTF8
    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('first-lfs-payload')
    )
    Git $seed add . | Out-Null
    Git $seed commit -m initial | Out-Null
    Git $seed remote add origin $remote | Out-Null
    Git $seed push -u origin main | Out-Null
    Git $seed lfs push origin main | Out-Null
    Git $tempRoot clone $remote $primary | Out-Null
    Git $primary checkout main | Out-Null
    Git $primary config --local lfs.fetchexclude '*' | Out-Null
    Set-Content -LiteralPath (Join-Path $primary 'local-untracked.txt') -Value 'preserve me' -Encoding UTF8

    $firstDestination = Join-Path $tempRoot 'worktrees/first'
    $plan = Run-Helper @(
        '-Repository', $primary,
        '-TaskSlug', 'first-task',
        '-OwnerSegment', 'root',
        '-Destination', $firstDestination
    )
    if ($plan.ExitCode -ne 0 -or $plan.Output -notmatch 'PLAN ONLY' -or (Test-Path -LiteralPath $firstDestination)) {
        throw "Plan-only setup failed: $($plan.Output)"
    }

    $created = Run-Helper @(
        '-Repository', $primary,
        '-TaskSlug', 'first-task',
        '-OwnerSegment', 'root',
        '-Destination', $firstDestination,
        '-Create'
    )
    if ($created.ExitCode -ne 0 -or $created.Output -notmatch 'CREATED') {
        throw "Worktree creation failed: $($created.Output)"
    }
    $expectedFirst = (Git $primary rev-parse refs/remotes/origin/main).Trim()
    if ((Git $firstDestination rev-parse HEAD).Trim() -cne $expectedFirst -or
        (Git $firstDestination branch --show-current).Trim() -cne 'codex/root/first-task' -or
        -not [string]::IsNullOrWhiteSpace((Git $firstDestination status --porcelain=v1 --untracked-files=all))) {
        throw 'First worktree is not exact origin/main, on the expected branch, and clean.'
    }
    if ([System.Text.Encoding]::UTF8.GetString(
        [System.IO.File]::ReadAllBytes((Join-Path $firstDestination 'asset.bin'))
    ) -cne 'first-lfs-payload') {
        throw 'First worktree retained an LFS pointer under lfs.fetchexclude=*.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $primary 'local-untracked.txt'))) {
        throw 'Dirty source checkout content was modified by setup.'
    }
    if ((Git $primary config --local --get core.hooksPath).Trim() -cne '.githooks') {
        throw 'Shared repository hook path was not installed.'
    }

    $duplicate = Run-Helper @(
        '-Repository', $primary,
        '-TaskSlug', 'first-task',
        '-OwnerSegment', 'root',
        '-Destination', (Join-Path $tempRoot 'worktrees/duplicate'),
        '-Create'
    )
    if ($duplicate.ExitCode -eq 0 -or $duplicate.Output -notmatch 'Branch already exists') {
        throw 'Duplicate branch was not rejected.'
    }

    Git $primary push origin "${expectedFirst}:refs/heads/codex/root/remote-only" | Out-Null
    $remoteOnly = Run-Helper @(
        '-Repository', $primary,
        '-TaskSlug', 'remote-only',
        '-OwnerSegment', 'root',
        '-Destination', (Join-Path $tempRoot 'worktrees/remote-only'),
        '-Create'
    )
    if ($remoteOnly.ExitCode -eq 0 -or $remoteOnly.Output -notmatch 'Remote branch already exists') {
        throw 'A remote-only branch collision was not rejected.'
    }

    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'two' -Encoding UTF8
    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('second-lfs-payload')
    )
    Git $seed add game.txt asset.bin | Out-Null
    Git $seed commit -m second | Out-Null
    Git $seed push origin main | Out-Null
    Git $seed lfs push origin main | Out-Null
    $secondDestination = Join-Path $tempRoot 'worktrees/second'
    $second = Run-Helper @(
        '-Repository', $primary,
        '-TaskSlug', 'second-task',
        '-OwnerSegment', 'map',
        '-Destination', $secondDestination,
        '-Create'
    )
    if ($second.ExitCode -ne 0) { throw "Second setup failed: $($second.Output)" }
    $expectedSecond = (Git $primary rev-parse refs/remotes/origin/main).Trim()
    if ($expectedSecond -ceq $expectedFirst -or (Git $secondDestination rev-parse HEAD).Trim() -cne $expectedSecond) {
        throw 'Second worktree did not use the freshly fetched origin/main.'
    }
    if ((Git $secondDestination branch --show-current).Trim() -cne 'codex/map/second-task') {
        throw 'Owner segment did not route to the expected codex/* branch.'
    }
    if ([System.Text.Encoding]::UTF8.GetString(
        [System.IO.File]::ReadAllBytes((Join-Path $secondDestination 'asset.bin'))
    ) -cne 'second-lfs-payload' -or
        (Git $primary config --local --get lfs.fetchexclude).Trim() -cne '*') {
        throw 'Exact second-revision LFS hydration did not override fetchexclude only for its commands.'
    }

    Git $seed rm tools/install_agent_git_hooks.ps1 | Out-Null
    Git $seed commit -m 'missing installer rollback fixture' | Out-Null
    Git $seed push origin main | Out-Null
    $rollbackDestination = Join-Path $tempRoot 'worktrees/rollback'
    $rollback = Run-Helper @(
        '-Repository', $primary,
        '-TaskSlug', 'rollback',
        '-OwnerSegment', 'root',
        '-Destination', $rollbackDestination,
        '-Create'
    )
    if ($rollback.ExitCode -eq 0 -or $rollback.Output -notmatch 'installer is missing' -or
        (Test-Path -LiteralPath $rollbackDestination) -or
        (Git-Result $primary show-ref --verify --quiet refs/heads/codex/root/rollback).ExitCode -eq 0) {
        throw "Failed setup did not remove its unchanged exact-base branch/worktree: $($rollback.Output)"
    }

    $rollbackBase = (Git $primary rev-parse refs/remotes/origin/main).Trim()
    $rollbackTree = (Git $primary rev-parse "$rollbackBase`^{tree}").Trim()
    $advancedOutput = @(
        "competing writer`n" | & git.exe -C $primary `
            -c user.name='Competing Writer' `
            -c user.email='competing@example.invalid' `
            commit-tree $rollbackTree -p $rollbackBase 2>&1
    )
    if ($LASTEXITCODE -ne 0) { throw "commit-tree fixture failed: $($advancedOutput | Out-String)" }
    $advanced = ($advancedOutput | Out-String).Trim()
    if ($advanced -ceq $rollbackBase) { throw 'Competing commit fixture did not advance the ref.' }
    Git $primary update-ref refs/heads/codex/root/atomic-cleanup $advanced | Out-Null
    Git-Result -Repository $primary -Arguments @(
        'update-ref', '-d', 'refs/heads/codex/root/atomic-cleanup', $rollbackBase
    ) | Out-Null
    $afterGuard = Git-Result $primary rev-parse refs/heads/codex/root/atomic-cleanup
    if ($afterGuard.ExitCode -ne 0 -or $afterGuard.Output.Trim() -cne $advanced) {
        throw "Expected-old update-ref deletion did not preserve a competing branch generation. base=$rollbackBase advanced=$advanced after=$($afterGuard.Output)"
    }

    $source = Get-Content -LiteralPath $helper -Raw
    foreach ($forbidden in @('CandidateReceipt', 'RunReceipt', 'assignment ack', 'last-green', 'WAITING_ACK', 'FROZEN')) {
        if ($source -match [regex]::Escape($forbidden)) {
            throw "Simple setup still contains legacy token '$forbidden'."
        }
    }
    $atomicDelete = "'update-ref', '-d', `"refs/heads/`$targetBranch`", `$baseSha"
    if ($source -match "@\('branch', '-D'" -or -not $source.Contains($atomicDelete)) {
        throw 'Setup cleanup is not an exact expected-old update-ref deletion.'
    }
    foreach ($required in @(
        "'lfs', 'fetch', 'origin', `$baseSha",
        "'lfs', 'checkout'",
        "'lfs', 'ls-files', '--json'",
        'lfs.fetchinclude=',
        'lfs.fetchexclude=',
        'version https://git-lfs.github.com/spec/v1'
    )) {
        if (-not $source.Contains($required)) {
            throw "Setup does not prove exact LFS hydration: '$required'."
        }
    }
    Write-Host 'PASS setup_agent_worktree fresh-origin-main/clean-worktree/codex-branch/exact-LFS/fetchexclude-override/dirty-source-isolation/atomic-cleanup contract'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
