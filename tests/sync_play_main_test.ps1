#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Contract {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output | Out-String)"
    }
    return ($output | Out-String).Trim()
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptUnderTest = Join-Path $repoRoot 'tools\sync_play_main.ps1'
$text = [IO.File]::ReadAllText($scriptUnderTest)
$null = $tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $scriptUnderTest,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
Assert-Contract ($parseErrors.Count -eq 0) 'sync_play_main.ps1 does not parse.'

foreach ($required in @(
    '+refs/heads/main:refs/remotes/origin/main',
    "'clone', '--no-tags', '--single-branch', '--branch', 'main'",
    "'merge', '--ff-only'",
    "'lfs', 'fetch', 'origin', `$targetSha",
    "'lfs', 'checkout'",
    "'lfs', 'fsck'",
    "'tools/build_underwater_map.py', '--check'",
    "'-SourceRepositoryPath', `$playRoot",
    "'-Target', 'tests/smoke_test.gd'",
    "'-RunReceiptOutputPath', `$attemptReceipt",
    'New-ScheduledTaskTrigger',
    'New-TimeSpan -Minutes 1',
    'SYNC_BUSY',
    "result = 'FAIL'",
    'current_main_sha',
    'managed-clone.json',
    'SYNC_FAILED_UNCHANGED',
    'standalone clone with a .git directory'
)) {
    Assert-Contract ($text.Contains($required)) "Missing sync/build contract marker: $required"
}
foreach ($forbidden in @(
    "'reset', '--hard'",
    "'checkout', 'main'",
    "'switch', 'main'",
    "'worktree', 'remove'",
    "'worktree', 'add'",
    "'switch', '--detach'",
    '-InPlace',
    'Start-Job'
)) {
    Assert-Contract (-not $text.Contains($forbidden)) "Unsafe sync marker found: $forbidden"
}

$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $systemTemp ('codex-play-main-test-' + [guid]::NewGuid().ToString('N'))
$origin = Join-Path $testRoot 'origin.git'
$source = Join-Path $testRoot 'source'
$play = Join-Path $testRoot 'play-main'
$localData = Join-Path $testRoot 'local-data'
$fakeGodot = Join-Path $testRoot 'fake-godot.cmd'
$oldLocalAppData = $env:LOCALAPPDATA

try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    & git init --bare $origin | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize disposable origin.' }
    & git clone $origin $source | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot clone disposable source.' }
    Invoke-Git $source checkout -b main | Out-Null
    Invoke-Git $source config user.email 'play-main-test@example.invalid' | Out-Null
    Invoke-Git $source config user.name 'Play Main Test' | Out-Null
    Invoke-Git $source config core.autocrlf false | Out-Null

    $mapTools = Join-Path $source 'underwater_map_workbench\tools'
    $sourceTools = Join-Path $source 'tools'
    $sourceTests = Join-Path $source 'tests'
    [IO.Directory]::CreateDirectory($mapTools) | Out-Null
    [IO.Directory]::CreateDirectory($sourceTools) | Out-Null
    [IO.Directory]::CreateDirectory($sourceTests) | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $mapTools 'build_underwater_map.py'),
        "import sys`nprint('MAP_CHECK_PASS')`nsys.exit(0)`n",
        [Text.UTF8Encoding]::new($false)
    )
    Copy-Item -LiteralPath $scriptUnderTest `
        -Destination (Join-Path $sourceTools 'sync_play_main.ps1')
    [IO.File]::WriteAllText(
        (Join-Path $sourceTests 'smoke_test.gd'),
        "extends SceneTree`n",
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $sourceTests 'run_all_tests.ps1'),
        @'
param(
    [string]$GodotConsolePath,
    [string]$SourceRepositoryPath,
    [string]$Target,
    [string]$RunReceiptOutputPath
)
$output = & $GodotConsolePath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $output -match '(?im)^\s*(?:SCRIPT ERROR|ERROR)(?:\s|:)') {
    throw "fake isolated build failed: $output"
}
[IO.File]::WriteAllText($RunReceiptOutputPath, "status=PASS`n", [Text.UTF8Encoding]::new($false))
Write-Output 'ISOLATED_BUILD_PASS'
'@,
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $source 'project.godot'),
        "[application]`nconfig/name=`"Play Main Test`"`n",
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText($fakeGodot, "@echo off`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
    Invoke-Git $source add --all | Out-Null
    Invoke-Git $source commit -m 'initial main' | Out-Null
    Invoke-Git $source push -u origin main | Out-Null
    $firstSha = Invoke-Git $source rev-parse 'HEAD^{commit}'

    $env:LOCALAPPDATA = $localData
    $firstOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -PlayPath $play -GodotConsolePath $fakeGodot
    Assert-Contract (($firstOutput | Out-String) -match 'SYNC_BUILT') `
        'Initial play-main build did not report success.'
    Assert-Contract ((Invoke-Git $play rev-parse 'HEAD^{commit}') -ceq $firstSha) `
        'Initial play-main does not point at exact origin/main.'

    [IO.File]::WriteAllText(
        (Join-Path $source 'revision.txt'),
        "second`n",
        [Text.UTF8Encoding]::new($false)
    )
    Invoke-Git $source add revision.txt | Out-Null
    Invoke-Git $source commit -m 'second main' | Out-Null
    Invoke-Git $source push origin main | Out-Null
    $secondSha = Invoke-Git $source rev-parse 'HEAD^{commit}'
    & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
        -PlayPath $play -GodotConsolePath $fakeGodot | Out-Null
    Assert-Contract ((Invoke-Git $play rev-parse 'HEAD^{commit}') -ceq $secondSha) `
        'play-main did not advance to the second exact origin/main.'

    [IO.File]::WriteAllText(
        (Join-Path $source 'revision.txt'),
        "broken`n",
        [Text.UTF8Encoding]::new($false)
    )
    Invoke-Git $source add revision.txt | Out-Null
    Invoke-Git $source commit -m 'broken main' | Out-Null
    Invoke-Git $source push origin main | Out-Null
    $brokenSha = Invoke-Git $source rev-parse 'HEAD^{commit}'
    [IO.File]::WriteAllText(
        $fakeGodot,
        "@echo off`r`necho ERROR: expected fake import failure`r`nexit /b 0`r`n",
        [Text.Encoding]::ASCII
    )
    $failed = $false
    try {
        & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
            -PlayPath $play -GodotConsolePath $fakeGodot | Out-Null
    }
    catch {
        $failed = $true
    }
    Assert-Contract $failed 'Expected Godot ERROR did not fail the local build.'
    Assert-Contract ((Invoke-Git $play rev-parse 'HEAD^{commit}') -ceq $brokenSha) `
        'Failed build hid the current red origin/main SHA.'
    $statusPath = Join-Path $localData 'OstatniPomost\play-main\status.json'
    $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$status.result -ceq 'FAIL') 'Failure status is not fail-closed.'
    Assert-Contract ([string]$status.target_sha -ceq $brokenSha) 'Failure status lost target SHA.'
    Assert-Contract ([string]$status.current_main_sha -ceq $brokenSha) 'Failure status lost current main SHA.'
    Assert-Contract ([string]$status.last_built_sha -ceq $secondSha) 'Failure status lost last built SHA.'
    $unchangedOutput = & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
        -PlayPath $play -GodotConsolePath $fakeGodot
    Assert-Contract (($unchangedOutput | Out-String) -match 'SYNC_FAILED_UNCHANGED') `
        'Unchanged failed SHA did not use bounded retry suppression.'

    [IO.File]::WriteAllText($fakeGodot, "@echo off`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
    $retryOutput = & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
        -PlayPath $play -GodotConsolePath $fakeGodot -RetryFailed
    Assert-Contract (($retryOutput | Out-String) -match 'SYNC_BUILT') `
        'RetryFailed did not recover the unchanged SHA after a transient build failure.'
    Assert-Contract ((Invoke-Git $play rev-parse 'HEAD^{commit}') -ceq $brokenSha) `
        'Recovered build did not remain on the exact current main SHA.'
    $retryStatus = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$retryStatus.result -ceq 'PASS') `
        'Recovered build did not replace the red status with PASS.'
    Assert-Contract ([string]$retryStatus.built_sha -ceq $brokenSha) `
        'Recovered build did not promote the exact retried SHA.'

    $foreignPlay = Join-Path $testRoot 'foreign-play'
    [IO.Directory]::CreateDirectory((Join-Path $foreignPlay 'tools')) | Out-Null
    Copy-Item -LiteralPath $scriptUnderTest `
        -Destination (Join-Path $foreignPlay 'tools\sync_play_main.ps1')
    $foreignRejected = $false
    try {
        & $scriptUnderTest -Mode Install -SourceRepository $source `
            -PlayPath $foreignPlay -GodotConsolePath $fakeGodot | Out-Null
    }
    catch { $foreignRejected = $true }
    Assert-Contract $foreignRejected `
        'Install accepted an existing path without the managed-clone marker.'

    $lockPath = Join-Path $localData 'OstatniPomost\play-main\sync.lock'
    $lock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    try {
        $busyOutput = & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
            -PlayPath $play -GodotConsolePath $fakeGodot
        Assert-Contract (($busyOutput | Out-String) -match 'SYNC_BUSY') `
            'Concurrent invocation did not exit through the shared lock.'
    }
    finally {
        $lock.Dispose()
    }
    Assert-Contract ([string]::IsNullOrWhiteSpace((Invoke-Git $play status --porcelain=v1 --untracked-files=all))) `
        'play-main is dirty after update and rollback coverage.'
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if ((Test-Path -LiteralPath $source -PathType Container) -and
        (Test-Path -LiteralPath $play -PathType Container)) {
        $cleanupPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & git -C $source worktree remove --force $play 2>&1 | Out-Null }
        finally { $ErrorActionPreference = $cleanupPreference }
    }
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($systemTemp + [IO.Path]::DirectorySeparatorChar)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'sync_play_main_test: PASS'
