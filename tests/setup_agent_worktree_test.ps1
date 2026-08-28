#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/setup_agent_worktree.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-simple-worktree-test-" + [guid]::NewGuid().ToString('N'))

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git.exe -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output | Out-String)"
    }
    return ($output | Out-String).Trim()
}

function Run-Helper {
    param([string[]]$Arguments)
    $output = @(& pwsh -NoLogo -NoProfile -File $helper @Arguments 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String).Trim() }
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
    New-Item -ItemType Directory -Path (Join-Path $seed 'tools'),(Join-Path $seed '.githooks') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/install_agent_git_hooks.ps1') -Destination (Join-Path $seed 'tools/install_agent_git_hooks.ps1')
    Copy-Item -LiteralPath (Join-Path $projectRoot '.githooks/pre-push') -Destination (Join-Path $seed '.githooks/pre-push')
    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'one' -Encoding utf8NoBOM
    Git $seed add . | Out-Null
    Git $seed commit -m initial | Out-Null
    Git $seed remote add origin $remote | Out-Null
    Git $seed push -u origin main | Out-Null
    Git $tempRoot clone $remote $primary | Out-Null
    Git $primary checkout main | Out-Null
    Set-Content -LiteralPath (Join-Path $primary 'local-untracked.txt') -Value 'preserve me' -Encoding utf8NoBOM

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

    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'two' -Encoding utf8NoBOM
    Git $seed add game.txt | Out-Null
    Git $seed commit -m second | Out-Null
    Git $seed push origin main | Out-Null
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

    $source = Get-Content -LiteralPath $helper -Raw
    foreach ($forbidden in @('CandidateReceipt', 'RunReceipt', 'assignment ack', 'last-green', 'WAITING_ACK', 'FROZEN')) {
        if ($source -match [regex]::Escape($forbidden)) {
            throw "Simple setup still contains legacy token '$forbidden'."
        }
    }
    Write-Host 'PASS setup_agent_worktree fresh-origin-main/clean-worktree/codex-branch/dirty-source-isolation contract'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
