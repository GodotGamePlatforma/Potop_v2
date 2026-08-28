#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/sync_play_main.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-sync-main-test-" + [guid]::NewGuid().ToString('N'))

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git.exe -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($output | Out-String)" }
    return ($output | Out-String).Trim()
}

function Run-Sync {
    param([string]$Repository)
    $output = @(& pwsh -NoLogo -NoProfile -File $tool -Repository $Repository 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String).Trim() }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $remote = Join-Path $tempRoot 'origin.git'
    $seed = Join-Path $tempRoot 'seed'
    $play = Join-Path $tempRoot 'play'
    Git $tempRoot init --bare $remote | Out-Null
    Git $tempRoot init -b main $seed | Out-Null
    Git $seed config user.email 'sync-test@example.invalid' | Out-Null
    Git $seed config user.name 'Sync Test' | Out-Null
    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'one' -Encoding utf8NoBOM
    Git $seed add game.txt | Out-Null
    Git $seed commit -m one | Out-Null
    Git $seed remote add origin $remote | Out-Null
    Git $seed push -u origin main | Out-Null
    Git $tempRoot clone $remote $play | Out-Null
    Git $play checkout main | Out-Null

    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'two' -Encoding utf8NoBOM
    Git $seed add game.txt | Out-Null
    Git $seed commit -m two | Out-Null
    Git $seed push origin main | Out-Null
    $expected = (Git $seed rev-parse HEAD).Trim()

    $synced = Run-Sync $play
    if ($synced.ExitCode -ne 0 -or $synced.Output -notmatch 'SYNC PASS') {
        throw "Clean main sync failed: $($synced.Output)"
    }
    if ((Git $play rev-parse HEAD).Trim() -cne $expected -or
        -not [string]::IsNullOrWhiteSpace((Git $play status --porcelain=v1 --untracked-files=all))) {
        throw 'Play checkout is not clean at exact fetched origin/main.'
    }
    Set-Content -LiteralPath (Join-Path $play 'dirty.txt') -Value 'preserve' -Encoding utf8NoBOM
    $dirtyHead = (Git $play rev-parse HEAD).Trim()
    $dirty = Run-Sync $play
    if ($dirty.ExitCode -eq 0 -or $dirty.Output -notmatch 'dirty' -or
        -not (Test-Path -LiteralPath (Join-Path $play 'dirty.txt')) -or (Git $play rev-parse HEAD).Trim() -cne $dirtyHead) {
        throw 'Dirty main was not rejected without mutation.'
    }
    Remove-Item -LiteralPath (Join-Path $play 'dirty.txt')

    Git $play checkout -b codex/root/not-main | Out-Null
    $wrongBranch = Run-Sync $play
    if ($wrongBranch.ExitCode -eq 0 -or $wrongBranch.Output -notmatch 'must be on main') {
        throw 'Non-main checkout was accepted by source sync.'
    }

    $source = Get-Content -LiteralPath $tool -Raw
    if ($source -notmatch [regex]::Escape("@('lfs', 'pull', 'origin', `$targetSha)")) {
        throw 'Source sync does not pin Git LFS pull to the exact fetched SHA.'
    }
    foreach ($forbidden in @('reset --hard', 'builds/current', 'Godot', 'export', 'smoke')) {
        if ($source -match [regex]::Escape($forbidden)) { throw "Source sync contains builder/destructive token '$forbidden'." }
    }
    Write-Host 'PASS sync_play_main clean-main/fetch/exact-pin/ff-only/LFS/dirty-preservation/source-only contract'
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
