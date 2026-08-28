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
$pythonPath = @(Get-Command python.exe -CommandType Application -ErrorAction Stop)[0].Source
$contractTool = Join-Path $projectRoot 'tools/workbench_contract.py'
$boundaryProcess = $null
$crashHolder = $null

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

function Start-BoundarySync {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][hashtable]$Environment
    )

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $hostPowerShell
    $start.WorkingDirectory = $tempRoot
    $start.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File boundary-sync.ps1'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['BOUNDARY_SYNC_TOOL'] = $tool
    $start.EnvironmentVariables['BOUNDARY_SYNC_REPOSITORY'] = $Repository
    foreach ($entry in $Environment.GetEnumerator()) {
        $start.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Could not start boundary sync process.' }
    return $process
}

function Complete-BoundarySync {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    if (-not $Process.WaitForExit(60000)) {
        $Process.Kill()
        throw 'Boundary sync process did not finish after release.'
    }
    $stdout = $Process.StandardOutput.ReadToEnd()
    $stderr = $Process.StandardError.ReadToEnd()
    return [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Wait-ForFixturePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutMilliseconds = 30000
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for fixture path '$Path'."
}

function Get-CanonicalLockPath {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $pythonPath -B $contractTool --repo $Repository lock-path 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "Could not resolve canonical lock path: $($output | Out-String)" }
    return ($output | Out-String).Trim()
}

function Invoke-PythonLockProbe {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(
            & $pythonPath -B (Join-Path $tempRoot 'lock-probe.py') `
                (Join-Path $projectRoot 'tools') $Repository 2>&1
        )
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot 'boundary-sync.ps1'),
        @'
$ErrorActionPreference = 'Continue'
& $env:BOUNDARY_SYNC_TOOL -Repository $env:BOUNDARY_SYNC_REPOSITORY
exit $LASTEXITCODE
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot 'powershell-lock-holder.ps1'),
        @'
$ErrorActionPreference = 'Stop'
$stream = [System.IO.File]::Open(
    $env:POWERSHELL_LOCK_PATH,
    [System.IO.FileMode]::OpenOrCreate,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::ReadWrite
)
try {
    if ($stream.Length -eq 0) {
        $stream.WriteByte(0)
        $stream.Flush()
    }
    $stream.Position = 0
    $stream.Lock(0, 1)
    [System.IO.File]::WriteAllText(
        $env:POWERSHELL_LOCK_READY,
        'ready',
        [System.Text.UTF8Encoding]::new($false)
    )
    Start-Sleep -Seconds 120
}
finally {
    try { $stream.Unlock(0, 1) } finally { $stream.Dispose() }
}
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot 'lock-holder.py'),
        @'
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.environ["LOCK_HOLDER_TOOLS"])
from workbench_contract import publication_lock

with publication_lock(os.environ["LOCK_HOLDER_REPOSITORY"], "integration-publish"):
    Path(os.environ["LOCK_HOLDER_READY"]).write_text("ready", encoding="utf-8")
    time.sleep(120)
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $tempRoot 'lock-probe.py'),
        @'
import sys

sys.path.insert(0, sys.argv[1])
from workbench_contract import publication_lock
from workbench_lock import WorkspaceLockError

try:
    with publication_lock(sys.argv[2], "integration-publish"):
        print("ACQUIRED")
except WorkspaceLockError:
    print("BLOCKED")
    raise SystemExit(73)
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
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
    $currentListing = (
        Git -Repository $play -Arguments @(
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'ls-files', '--json', 'HEAD'
        )
    ) | ConvertFrom-Json
    $currentAsset = @($currentListing.files | Where-Object { [string]$_.name -ceq 'asset.bin' })
    if ($currentAsset.Count -ne 1 -or -not [bool]$currentAsset[0].downloaded -or
        -not [bool]$currentAsset[0].checkout) {
        throw 'Current LFS isolation fixture did not begin hydrated and downloaded.'
    }
    $currentOid = [string]$currentAsset[0].oid
    $gitDirectory = (Git $play rev-parse --git-dir).Trim()
    if (-not [System.IO.Path]::IsPathRooted($gitDirectory)) {
        $gitDirectory = [System.IO.Path]::GetFullPath((Join-Path $play $gitDirectory))
    }
    $currentObject = Join-Path $gitDirectory (
        "lfs/objects/$($currentOid.Substring(0, 2))/$($currentOid.Substring(2, 2))/$currentOid"
    )
    if (-not (Test-Path -LiteralPath $currentObject -PathType Leaf)) {
        throw "Current LFS object fixture is missing: '$currentObject'."
    }
    $isolatedCurrentObject = Join-Path $tempRoot 'isolated-current-lfs-object'
    Move-Item -LiteralPath $currentObject -Destination $isolatedCurrentObject
    Git $play config --local lfs.fetchexclude '*' | Out-Null
    $isolatedListing = (
        Git -Repository $play -Arguments @(
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'ls-files', '--json', 'HEAD'
        )
    ) | ConvertFrom-Json
    $isolatedAsset = @($isolatedListing.files | Where-Object { [string]$_.name -ceq 'asset.bin' })
    $isolatedStatus = Git $play status --porcelain=v1 --untracked-files=all
    if ($isolatedAsset.Count -ne 1 -or [bool]$isolatedAsset[0].downloaded -or
        -not [bool]$isolatedAsset[0].checkout -or -not [string]::IsNullOrWhiteSpace($isolatedStatus)) {
        throw "Fixture did not isolate current LFS cleanly: count=$($isolatedAsset.Count) downloaded=$([bool]$isolatedAsset[0].downloaded) checkout=$([bool]$isolatedAsset[0].checkout) status='$isolatedStatus'."
    }

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

    $rollbackRepositories = @{}
    foreach ($caseName in @(
        'safe', 'late-write', 'branch-switch', 'ref-drift',
        'success-branch-switch'
    )) {
        $caseRepository = Join-Path $tempRoot "rollback-$caseName"
        Git $tempRoot clone $remote $caseRepository | Out-Null
        Git $caseRepository checkout main | Out-Null
        Git $caseRepository config --local lfs.fetchexclude '*' | Out-Null
        $rollbackRepositories[$caseName] = $caseRepository
    }

    [System.IO.File]::WriteAllBytes(
        (Join-Path $seed 'asset.bin'),
        [System.Text.Encoding]::UTF8.GetBytes('sync-lfs-three')
    )
    Git $seed add asset.bin | Out-Null
    Git $seed commit -m three | Out-Null
    Git $seed push origin main | Out-Null
    Git $seed lfs push origin main | Out-Null
    $rollbackTarget = (Git $seed rev-parse HEAD).Trim()
    $rollbackOriginal = $expected

    $branchSwitchRepository = [string]$rollbackRepositories['branch-switch']
    Git $branchSwitchRepository branch foreign-switch $rollbackOriginal | Out-Null
    $successBranchSwitchRepository = [string]$rollbackRepositories['success-branch-switch']
    Git $successBranchSwitchRepository branch foreign-success $rollbackOriginal | Out-Null
    $refDriftRepository = [string]$rollbackRepositories['ref-drift']
    Git $refDriftRepository fetch origin main | Out-Null
    $targetTree = (Git $refDriftRepository rev-parse "$rollbackTarget`^{tree}").Trim()
    $driftSha = (Git -Repository $refDriftRepository -Arguments @(
        '-c', 'user.name=Ref Drift',
        '-c', 'user.email=ref-drift@example.invalid',
        'commit-tree', $targetTree,
        '-p', $rollbackTarget,
        '-m', 'competing main generation'
    )).Trim()

    $gitBin = Join-Path $tempRoot 'git-bin'
    New-Item -ItemType Directory -Path $gitBin | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $gitBin 'git.ps1'),
        @'
$joined = $args -join ' '
if (-not [string]::IsNullOrWhiteSpace($env:MOCK_SYNC_ANY_GIT_MARKER)) {
    [System.IO.File]::WriteAllText(
        $env:MOCK_SYNC_ANY_GIT_MARKER,
        $joined,
        [System.Text.UTF8Encoding]::new($false)
    )
}
if ($joined -match '(?:^| )merge --ff-only(?: |$)' -and
    $env:MOCK_SYNC_FAILURE_MODE -ceq 'success-branch-switch') {
    & $env:MOCK_SYNC_REAL_GIT -C $env:MOCK_SYNC_REPOSITORY checkout --quiet foreign-success
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $env:MOCK_SYNC_REAL_GIT @args
    exit $LASTEXITCODE
}
if ($joined -match '(?:^| )lfs checkout(?: |$)' -and
    $env:MOCK_SYNC_FAILURE_MODE -in @('safe', 'late-write', 'branch-switch', 'ref-drift')) {
    $head = (& $env:MOCK_SYNC_REAL_GIT -C $env:MOCK_SYNC_REPOSITORY rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($head -ceq $env:MOCK_SYNC_TARGET_SHA) {
        switch ($env:MOCK_SYNC_FAILURE_MODE) {
            'late-write' {
                [System.IO.File]::WriteAllText(
                    (Join-Path $env:MOCK_SYNC_REPOSITORY 'game.txt'),
                    'foreign-late-tracked-write',
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            'branch-switch' {
                & $env:MOCK_SYNC_REAL_GIT -C $env:MOCK_SYNC_REPOSITORY checkout --quiet foreign-switch
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            }
            'ref-drift' {
                & $env:MOCK_SYNC_REAL_GIT -C $env:MOCK_SYNC_REPOSITORY update-ref `
                    refs/heads/main $env:MOCK_SYNC_DRIFT_SHA $env:MOCK_SYNC_TARGET_SHA
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            }
        }
        [Console]::Error.WriteLine("injected post-merge lfs checkout failure: $env:MOCK_SYNC_FAILURE_MODE")
        exit 23
    }
}
if ($joined -match '(?:^| )restore(?: |$)' -and
    -not [string]::IsNullOrWhiteSpace($env:MOCK_SYNC_RESTORE_READY) -and
    -not [string]::IsNullOrWhiteSpace($env:MOCK_SYNC_RESTORE_RELEASE)) {
    [System.IO.File]::WriteAllText(
        $env:MOCK_SYNC_RESTORE_READY,
        'ready',
        [System.Text.UTF8Encoding]::new($false)
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt 30000 -and
        -not (Test-Path -LiteralPath $env:MOCK_SYNC_RESTORE_RELEASE -PathType Leaf)) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $env:MOCK_SYNC_RESTORE_RELEASE -PathType Leaf)) {
        [Console]::Error.WriteLine('restore-boundary fixture timed out')
        exit 97
    }
}
& $env:MOCK_SYNC_REAL_GIT @args
exit $LASTEXITCODE
'@,
        [System.Text.UTF8Encoding]::new($false)
    )

    $caseResults = @{}
    $oldPath = $env:PATH
    $safeRepository = [string]$rollbackRepositories['safe']
    $restoreReady = Join-Path $tempRoot 'restore-boundary.ready'
    $restoreRelease = Join-Path $tempRoot 'restore-boundary.release'
    $safeLockPath = Get-CanonicalLockPath $safeRepository
    $playLockPath = Get-CanonicalLockPath $play
    if ([string]::Equals($safeLockPath, $playLockPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'integration-publish lock was not bound to the exact repository/common-dir.'
    }
    $boundaryProcess = Start-BoundarySync -Repository $safeRepository -Environment @{
        'PATH' = "$gitBin;$oldPath"
        'MOCK_SYNC_REAL_GIT' = $realGitPath
        'MOCK_SYNC_REPOSITORY' = $safeRepository
        'MOCK_SYNC_TARGET_SHA' = $rollbackTarget
        'MOCK_SYNC_FAILURE_MODE' = 'safe'
        'MOCK_SYNC_DRIFT_SHA' = $driftSha
        'MOCK_SYNC_RESTORE_READY' = $restoreReady
        'MOCK_SYNC_RESTORE_RELEASE' = $restoreRelease
        'GIT_LFS_SKIP_SMUDGE' = '1'
    }
    Wait-ForFixturePath $restoreReady
    $beforeCompetingHead = (Git $safeRepository rev-parse HEAD).Trim()
    $beforeCompetingMain = (Git $safeRepository rev-parse refs/heads/main).Trim()
    $pythonBlockedByPowerShell = Invoke-PythonLockProbe $safeRepository
    if ($pythonBlockedByPowerShell.ExitCode -eq 0 -or
        $pythonBlockedByPowerShell.Output -notmatch 'BLOCKED') {
        throw "Python publication_lock entered while PowerShell held the restore boundary: $($pythonBlockedByPowerShell.Output)"
    }
    $competingSync = Run-Sync $safeRepository
    if ($competingSync.ExitCode -eq 0 -or
        $competingSync.Output -notmatch 'integration-publish' -or
        (Git $safeRepository rev-parse HEAD).Trim() -cne $beforeCompetingHead -or
        (Git $safeRepository rev-parse refs/heads/main).Trim() -cne $beforeCompetingMain) {
        throw "Competing legal sync entered the restore boundary or changed refs: $($competingSync.Output)"
    }
    [System.IO.File]::WriteAllText(
        $restoreRelease,
        'release',
        [System.Text.UTF8Encoding]::new($false)
    )
    $caseResults['safe'] = Complete-BoundarySync $boundaryProcess
    $boundaryProcess.Dispose()
    $boundaryProcess = $null

    foreach ($caseName in @('late-write', 'branch-switch', 'ref-drift', 'success-branch-switch')) {
        try {
            $env:MOCK_SYNC_REAL_GIT = $realGitPath
            $env:MOCK_SYNC_REPOSITORY = [string]$rollbackRepositories[$caseName]
            $env:MOCK_SYNC_TARGET_SHA = $rollbackTarget
            $env:MOCK_SYNC_FAILURE_MODE = $caseName
            $env:MOCK_SYNC_DRIFT_SHA = $driftSha
            $env:PATH = "$gitBin;$oldPath"
            $caseResults[$caseName] = Run-Sync ([string]$rollbackRepositories[$caseName])
        }
        finally {
            $env:PATH = $oldPath
            foreach ($name in @(
                'MOCK_SYNC_REAL_GIT','MOCK_SYNC_REPOSITORY','MOCK_SYNC_TARGET_SHA',
                'MOCK_SYNC_FAILURE_MODE','MOCK_SYNC_DRIFT_SHA',
                'MOCK_SYNC_RESTORE_READY','MOCK_SYNC_RESTORE_RELEASE'
            )) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            }
        }
    }

    $safeFailure = $caseResults['safe']
    if ($safeFailure.ExitCode -eq 0 -or
        $safeFailure.Output -notmatch 'injected post-merge lfs checkout failure' -or
        (Git $safeRepository branch --show-current).Trim() -cne 'main' -or
        (Git $safeRepository rev-parse HEAD).Trim() -cne $rollbackOriginal -or
        (Git $safeRepository rev-parse refs/heads/main).Trim() -cne $rollbackOriginal -or
        -not [string]::IsNullOrWhiteSpace((Git $safeRepository status --porcelain=v1 --untracked-files=all)) -or
        [System.Text.Encoding]::UTF8.GetString(
            [System.IO.File]::ReadAllBytes((Join-Path $safeRepository 'asset.bin'))
        ) -cne 'sync-lfs-two') {
        throw "Safe post-merge failure did not restore exact original main: $($safeFailure.Output)"
    }

    $crashReady = Join-Path $tempRoot 'crash-holder.ready'
    $holderStart = New-Object System.Diagnostics.ProcessStartInfo
    $holderStart.FileName = $pythonPath
    $holderStart.WorkingDirectory = $tempRoot
    $holderStart.Arguments = '-B lock-holder.py'
    $holderStart.UseShellExecute = $false
    $holderStart.CreateNoWindow = $true
    $holderStart.RedirectStandardOutput = $true
    $holderStart.RedirectStandardError = $true
    $holderStart.EnvironmentVariables['LOCK_HOLDER_TOOLS'] = (Join-Path $projectRoot 'tools')
    $holderStart.EnvironmentVariables['LOCK_HOLDER_REPOSITORY'] = $safeRepository
    $holderStart.EnvironmentVariables['LOCK_HOLDER_READY'] = $crashReady
    $crashHolder = New-Object System.Diagnostics.Process
    $crashHolder.StartInfo = $holderStart
    if (-not $crashHolder.Start()) { throw 'Could not start crash-release lock holder.' }
    Wait-ForFixturePath $crashReady
    $beforePythonHolderHead = (Git $safeRepository rev-parse HEAD).Trim()
    $beforePythonHolderStatus = Git $safeRepository status --porcelain=v1 --untracked-files=all
    $blockedGitMarker = Join-Path $tempRoot 'blocked-sync-entered-git'
    try {
        $env:MOCK_SYNC_ANY_GIT_MARKER = $blockedGitMarker
        $env:PATH = "$gitBin;$oldPath"
        $blockedByHolder = Run-Sync $safeRepository
    }
    finally {
        $env:PATH = $oldPath
        Remove-Item 'Env:MOCK_SYNC_ANY_GIT_MARKER' -ErrorAction SilentlyContinue
    }
    if ($blockedByHolder.ExitCode -eq 0 -or
        $blockedByHolder.Output -notmatch 'integration-publish' -or
        (Test-Path -LiteralPath $blockedGitMarker -PathType Leaf) -or
        (Git $safeRepository rev-parse HEAD).Trim() -cne $beforePythonHolderHead -or
        (Git $safeRepository status --porcelain=v1 --untracked-files=all) -cne $beforePythonHolderStatus) {
        throw "Sync bypassed the canonical external lock holder: $($blockedByHolder.Output)"
    }
    $crashHolder.Kill()
    if (-not $crashHolder.WaitForExit(10000)) { throw 'Crashed lock holder did not exit.' }
    $crashHolder.Dispose()
    $crashHolder = $null
    $afterCrashRelease = Run-Sync $safeRepository
    if ($afterCrashRelease.ExitCode -ne 0 -or
        $afterCrashRelease.Output -notmatch 'SYNC PASS' -or
        (Git $safeRepository branch --show-current).Trim() -cne 'main' -or
        (Git $safeRepository rev-parse HEAD).Trim() -cne $rollbackTarget -or
        (Git $safeRepository rev-parse refs/heads/main).Trim() -cne $rollbackTarget -or
        -not [string]::IsNullOrWhiteSpace((Git $safeRepository status --porcelain=v1 --untracked-files=all)) -or
        [System.Text.Encoding]::UTF8.GetString(
            [System.IO.File]::ReadAllBytes((Join-Path $safeRepository 'asset.bin'))
        ) -cne 'sync-lfs-three') {
        throw "OS crash release did not permit a clean exact sync: $($afterCrashRelease.Output)"
    }

    $powerShellCrashReady = Join-Path $tempRoot 'powershell-crash-holder.ready'
    $powerShellHolderStart = New-Object System.Diagnostics.ProcessStartInfo
    $powerShellHolderStart.FileName = $hostPowerShell
    $powerShellHolderStart.WorkingDirectory = $tempRoot
    $powerShellHolderStart.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File powershell-lock-holder.ps1'
    $powerShellHolderStart.UseShellExecute = $false
    $powerShellHolderStart.CreateNoWindow = $true
    $powerShellHolderStart.RedirectStandardOutput = $true
    $powerShellHolderStart.RedirectStandardError = $true
    $powerShellHolderStart.EnvironmentVariables['POWERSHELL_LOCK_PATH'] = $safeLockPath
    $powerShellHolderStart.EnvironmentVariables['POWERSHELL_LOCK_READY'] = $powerShellCrashReady
    $boundaryProcess = New-Object System.Diagnostics.Process
    $boundaryProcess.StartInfo = $powerShellHolderStart
    if (-not $boundaryProcess.Start()) { throw 'Could not start PowerShell crash-release holder.' }
    Wait-ForFixturePath $powerShellCrashReady
    $blockedBeforePowerShellCrash = Invoke-PythonLockProbe $safeRepository
    if ($blockedBeforePowerShellCrash.ExitCode -eq 0 -or
        $blockedBeforePowerShellCrash.Output -notmatch 'BLOCKED') {
        throw "Python lock probe bypassed the PowerShell byte lock: $($blockedBeforePowerShellCrash.Output)"
    }
    $boundaryProcess.Kill()
    if (-not $boundaryProcess.WaitForExit(10000)) { throw 'PowerShell lock holder did not crash.' }
    $boundaryProcess.Dispose()
    $boundaryProcess = $null
    $afterPowerShellCrash = Invoke-PythonLockProbe $safeRepository
    if ($afterPowerShellCrash.ExitCode -ne 0 -or
        $afterPowerShellCrash.Output -notmatch 'ACQUIRED') {
        throw "PowerShell crash did not release the canonical byte lock: $($afterPowerShellCrash.Output)"
    }

    $lateWriteRepository = [string]$rollbackRepositories['late-write']
    $lateWriteFailure = $caseResults['late-write']
    if ($lateWriteFailure.ExitCode -eq 0 -or
        $lateWriteFailure.Output -notmatch 'rollback refused without overwriting ambiguous state' -or
        (Git $lateWriteRepository branch --show-current).Trim() -cne 'main' -or
        (Git $lateWriteRepository rev-parse HEAD).Trim() -cne $rollbackTarget -or
        (Git $lateWriteRepository rev-parse refs/heads/main).Trim() -cne $rollbackTarget -or
        (Get-Content -LiteralPath (Join-Path $lateWriteRepository 'game.txt') -Raw) -cne 'foreign-late-tracked-write') {
        throw "Late tracked write was overwritten during rollback: $($lateWriteFailure.Output)"
    }

    $branchSwitchFailure = $caseResults['branch-switch']
    if ($branchSwitchFailure.ExitCode -eq 0 -or
        $branchSwitchFailure.Output -notmatch 'rollback refused without overwriting ambiguous state' -or
        (Git $branchSwitchRepository branch --show-current).Trim() -cne 'foreign-switch' -or
        (Git $branchSwitchRepository rev-parse HEAD).Trim() -cne $rollbackOriginal -or
        (Git $branchSwitchRepository rev-parse refs/heads/foreign-switch).Trim() -cne $rollbackOriginal -or
        (Git $branchSwitchRepository rev-parse refs/heads/main).Trim() -cne $rollbackTarget) {
        throw "Foreign branch switch/ref was overwritten during rollback: $($branchSwitchFailure.Output)"
    }

    $refDriftFailure = $caseResults['ref-drift']
    if ($refDriftFailure.ExitCode -eq 0 -or
        $refDriftFailure.Output -notmatch 'not the expected target generation' -or
        (Git $refDriftRepository branch --show-current).Trim() -cne 'main' -or
        (Git $refDriftRepository rev-parse HEAD).Trim() -cne $driftSha -or
        (Git $refDriftRepository rev-parse refs/heads/main).Trim() -cne $driftSha -or
        -not [string]::IsNullOrWhiteSpace((Git $refDriftRepository status --porcelain=v1 --untracked-files=all))) {
        throw "Competing main ref generation was overwritten during rollback: $($refDriftFailure.Output)"
    }

    $successBranchFailure = $caseResults['success-branch-switch']
    if ($successBranchFailure.ExitCode -eq 0 -or
        $successBranchFailure.Output -match 'SYNC PASS' -or
        $successBranchFailure.Output -notmatch 'Success exact clean main fence' -or
        (Git $successBranchSwitchRepository branch --show-current).Trim() -cne 'foreign-success' -or
        (Git $successBranchSwitchRepository rev-parse HEAD).Trim() -cne $rollbackTarget -or
        (Git $successBranchSwitchRepository rev-parse refs/heads/foreign-success).Trim() -cne $rollbackTarget -or
        (Git $successBranchSwitchRepository rev-parse refs/heads/main).Trim() -cne $rollbackOriginal) {
        throw "Post-fetch branch switch produced false SYNC PASS or changed main: $($successBranchFailure.Output)"
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
        "'lfs', 'fetch', 'origin', `$currentSha",
        "'lfs', 'fetch', 'origin', `$targetSha",
        "'lfs', 'checkout'",
        "'lfs', 'ls-files', '--json'",
        "'symbolic-ref', '--quiet', 'HEAD'",
        "'rev-parse', 'refs/heads/main'",
        'lock-path --name integration-publish',
        '$stream.Lock(0, 1)',
        '$Stream.Unlock(0, 1)',
        "Assert-ExactCleanMainState -ExpectedSha `$currentSha -Label 'Pre-merge'",
        "Assert-ExactCleanMainState -ExpectedSha `$targetSha -Label 'Success'",
        "Remove-Item -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE'",
        'lfs.fetchinclude=',
        'lfs.fetchexclude=',
        'version https://git-lfs.github.com/spec/v1'
    )) {
        if (-not $source.Contains($required)) {
            throw "Source sync does not prove exact LFS hydration: '$required'."
        }
    }
    foreach ($forbidden in @(
        'reset --hard', 'builds/current', 'Godot', 'export', 'smoke',
        'LockToken', 'POTOP_SYNC_LOCK_TOKEN'
    )) {
        if ($source -match [regex]::Escape($forbidden)) { throw "Source sync contains builder/destructive token '$forbidden'." }
    }
    Write-Host 'PASS sync_play_main integration-publish-lock/crash-release/pre-post-main-fences/current-LFS-self-heal/SKIP_SMUDGE-safe-rollback/source-only contract'
}
finally {
    foreach ($process in @($boundaryProcess, $crashHolder)) {
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) { $process.Kill() }
                $process.WaitForExit(5000) | Out-Null
                $process.Dispose()
            }
            catch { }
        }
    }
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
