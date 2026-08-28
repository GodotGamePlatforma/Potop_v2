#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/sync_play_main.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-sync-main-test-" + [guid]::NewGuid().ToString('N'))
$hostPowerShell = if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Join-Path $PSHOME 'powershell.exe'
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}
$realGitPath = @(Get-Command git.exe -CommandType Application)[0].Source

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git.exe -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "git failed: $($output | Out-String)" }
    return ($output | Out-String).Trim()
}

function Run-Sync {
    param([string]$Repository)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $hostPowerShell -NoLogo -NoProfile -File $tool -Repository $Repository 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
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
    Git $seed lfs install --local | Out-Null
    Git $seed lfs track '*.bin' | Out-Null
    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'one' -Encoding UTF8
    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('sync-lfs-one')
    )
    Git $seed add game.txt asset.bin .gitattributes | Out-Null
    Git $seed commit -m one | Out-Null
    Git $seed remote add origin $remote | Out-Null
    Git $seed push -u origin main | Out-Null
    Git $seed lfs push origin main | Out-Null
    Git $tempRoot clone $remote $play | Out-Null
    Git $play checkout main | Out-Null

    Set-Content -LiteralPath (Join-Path $seed 'game.txt') -Value 'two' -Encoding UTF8
    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('sync-lfs-two')
    )
    Git $seed add game.txt asset.bin | Out-Null
    Git $seed commit -m two | Out-Null
    Git $seed push origin main | Out-Null
    Git $seed lfs push origin main | Out-Null
    $expected = (Git $seed rev-parse HEAD).Trim()
    Git $play config --local lfs.fetchexclude '*' | Out-Null

    $synced = Run-Sync $play
    if ($synced.ExitCode -ne 0 -or $synced.Output -notmatch 'SYNC PASS') {
        throw "Clean main sync failed: $($synced.Output)"
    }
    if ((Git $play rev-parse HEAD).Trim() -cne $expected -or
        -not [string]::IsNullOrWhiteSpace((Git $play status --porcelain=v1 --untracked-files=all))) {
        throw 'Play checkout is not clean at exact fetched origin/main.'
    }
    if ([System.Text.Encoding]::UTF8.GetString(
        [System.IO.File]::ReadAllBytes((Join-Path $play 'asset.bin'))
    ) -cne 'sync-lfs-two' -or
        (Git $play config --local --get lfs.fetchexclude).Trim() -cne '*') {
        throw 'Source sync did not hydrate the exact LFS object while preserving fetchexclude=*.'
    }

    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('sync-lfs-three')
    )
    Git $seed add asset.bin | Out-Null
    Git $seed commit -m three | Out-Null
    Git $seed push origin main | Out-Null
    Git $seed lfs push origin main | Out-Null

    $gitBin = Join-Path $tempRoot 'git-bin'
    New-Item -ItemType Directory -Path $gitBin | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $gitBin 'git.ps1'),
        @'
if ($env:MOCK_SYNC_FAIL_LFS_CHECKOUT -eq '1' -and
    ($args -join ' ') -match '(?:^| )lfs checkout(?: |$)') {
    [Console]::Error.WriteLine('injected post-merge lfs checkout failure')
    exit 23
}
& $env:MOCK_SYNC_REAL_GIT @args
exit $LASTEXITCODE
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    $beforeRollback = (Git $play rev-parse HEAD).Trim()
    $oldPath = $env:PATH
    try {
        $env:MOCK_SYNC_REAL_GIT = $realGitPath
        $env:MOCK_SYNC_FAIL_LFS_CHECKOUT = '1'
        $env:PATH = "$gitBin;$oldPath"
        $postMergeFailure = Run-Sync $play
    }
    finally {
        $env:PATH = $oldPath
        Remove-Item Env:MOCK_SYNC_REAL_GIT,Env:MOCK_SYNC_FAIL_LFS_CHECKOUT -ErrorAction SilentlyContinue
    }
    if ($postMergeFailure.ExitCode -eq 0 -or
        $postMergeFailure.Output -notmatch 'injected post-merge lfs checkout failure' -or
        (Git $play rev-parse HEAD).Trim() -cne $beforeRollback -or
        -not [string]::IsNullOrWhiteSpace((Git $play status --porcelain=v1 --untracked-files=all)) -or
        [System.Text.Encoding]::UTF8.GetString(
            [System.IO.File]::ReadAllBytes((Join-Path $play 'asset.bin'))
        ) -cne 'sync-lfs-two') {
        throw "Post-merge failure did not restore exact original main: $($postMergeFailure.Output)"
    }

    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('missing-remote-lfs-object')
    )
    Git $seed add asset.bin | Out-Null
    Git $seed commit -m 'missing remote LFS object' | Out-Null
    Git $seed push --no-verify origin main | Out-Null
    $beforeMissingObject = (Git $play rev-parse HEAD).Trim()
    $missingObject = Run-Sync $play
    if ($missingObject.ExitCode -eq 0 -or
        (Git $play rev-parse HEAD).Trim() -cne $beforeMissingObject -or
        -not [string]::IsNullOrWhiteSpace((Git $play status --porcelain=v1 --untracked-files=all)) -or
        [System.Text.Encoding]::UTF8.GetString(
            [System.IO.File]::ReadAllBytes((Join-Path $play 'asset.bin'))
        ) -cne 'sync-lfs-two') {
        throw "Missing exact LFS object did not fail before changing current main: $($missingObject.Output)"
    }
    Set-Content -LiteralPath (Join-Path $play 'dirty.txt') -Value 'preserve' -Encoding UTF8
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
    foreach ($required in @(
        "'lfs', 'fetch', 'origin', `$targetSha",
        "'lfs', 'checkout'",
        "'lfs', 'ls-files', '--json'",
        'lfs.fetchinclude=',
        'lfs.fetchexclude=',
        'version https://git-lfs.github.com/spec/v1'
    )) {
        if (-not $source.Contains($required)) {
            throw "Source sync does not prove exact LFS hydration: '$required'."
        }
    }
    foreach ($forbidden in @('reset --hard', 'builds/current', 'Godot', 'export', 'smoke')) {
        if ($source -match [regex]::Escape($forbidden)) { throw "Source sync contains builder/destructive token '$forbidden'." }
    }
    Write-Host 'PASS sync_play_main clean-main/fetch/exact-LFS/fetchexclude-override/fail-state-preservation/ff-only/source-only contract'
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
