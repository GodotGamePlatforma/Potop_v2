#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/agent_fast_check.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-fast-check-test-" + [guid]::NewGuid().ToString('N'))
$hostPowerShell = if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Join-Path $PSHOME 'powershell.exe'
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}

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

function Run-FastCheck {
    param([string]$Repository, [string]$Godot, [string[]]$Extra = @())
    $arguments = @(
        '-NoLogo', '-NoProfile', '-File', $helper,
        '-Repository', $Repository,
        '-BaseRef', 'refs/heads/main'
    )
    if (-not [string]::IsNullOrWhiteSpace($Godot)) {
        $arguments += @('-GodotConsolePath', $Godot)
    }
    $arguments += $Extra
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $hostPowerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $repo = Join-Path $tempRoot 'repo'
    $mockBin = Join-Path $tempRoot 'bin'
    $targetLog = Join-Path $tempRoot 'target.log'
    New-Item -ItemType Directory -Path $mockBin | Out-Null
    Set-Content -LiteralPath (Join-Path $mockBin 'git-lfs.cmd') -Encoding ascii -Value @'
@echo off
python "%~dp0git_lfs_mock.py" %*
'@
    Set-Content -LiteralPath (Join-Path $mockBin 'git_lfs_mock.py') -Encoding UTF8 -Value @'
import json
import os
import sys

if sys.argv[1:2] == ["version"]:
    print("git-lfs/3.0.0")
elif sys.argv[1:2] == ["ls-files"]:
    print(os.environ.get("FAST_LFS_LISTING", json.dumps({"files": []})))
raise SystemExit(0)
'@
    $successGodot = Join-Path $mockBin 'godot-success.cmd'
    $errorGodot = Join-Path $mockBin 'godot-error.cmd'
    $autoGodot = Join-Path $mockBin 'godot.cmd'
    Set-Content -LiteralPath $successGodot -Encoding ascii -Value "@echo off`necho Godot Engine test`nexit /b 0"
    Set-Content -LiteralPath $errorGodot -Encoding ascii -Value "@echo off`necho SCRIPT ERROR: parser failure`nexit /b 0"
    Set-Content -LiteralPath $autoGodot -Encoding ascii -Value "@echo off`necho Godot fallback test`nexit /b 0"
    $oldPath = $env:PATH
    $env:PATH = "$mockBin;$oldPath"
    $env:FAST_TARGET_LOG = $targetLog

    Git $tempRoot init -b main $repo | Out-Null
    Git $repo config user.email 'fast-test@example.invalid' | Out-Null
    Git $repo config user.name 'Fast Test' | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'tools'),(Join-Path $repo 'tests') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/ci_protected_paths.py') -Destination (Join-Path $repo 'tools/ci_protected_paths.py')
    Set-Content -LiteralPath (Join-Path $repo 'tools/workbench_contract.py') -Encoding UTF8 -Value 'print("EOL PASS")'
    Set-Content -LiteralPath (Join-Path $repo 'tests/run_all_tests.ps1') -Encoding UTF8 -Value @'
param([string]$GodotConsolePath,[string]$SourceRepositoryPath,[string[]]$Target)
if ($GodotConsolePath -like '*error*') { throw 'SCRIPT ERROR: parser failure' }
foreach ($entry in $Target) {
    Add-Content -LiteralPath $env:FAST_TARGET_LOG -Value "GODOT=$GodotConsolePath TARGET=$entry"
    Write-Host "TARGET PASS $entry"
}
'@
    Set-Content -LiteralPath (Join-Path $repo 'tests/game_test.gd') -Encoding UTF8 -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $repo 'tests/deleted_test.gd') -Encoding UTF8 -Value 'extends SceneTree'
    Set-Content -LiteralPath (Join-Path $repo 'game.gd') -Encoding UTF8 -Value 'extends Node'
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null
    Git $repo checkout -b codex/root/feature | Out-Null
    Add-Content -LiteralPath (Join-Path $repo 'game.gd') -Value 'var changed := true' -Encoding UTF8

    $pass = Run-FastCheck $repo $successGodot @('-TestTarget', 'tests/game_test.gd', '-AllowedPath', 'game.gd')
    if ($pass.ExitCode -ne 0 -or $pass.Output -notmatch 'FAST-CHECK PASS') {
        throw "Expected fast-check PASS: $($pass.Output)"
    }
    if ((Get-Content -LiteralPath $targetLog -Raw) -notmatch 'tests/game_test.gd') {
        throw 'Targeted test runner was not invoked.'
    }

    Clear-Content -LiteralPath $targetLog
    $nodeTestPath = Join-Path $repo 'tests/node_flow_test.gd'
    $nodeScenePath = Join-Path $repo 'tests/NodeFlowTest.tscn'
    Set-Content -LiteralPath $nodeTestPath -Encoding UTF8 -Value 'extends Node'
    Set-Content -LiteralPath $nodeScenePath -Encoding UTF8 -Value @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/node_flow_test.gd" id="1"]

[node name="NodeFlowTest" type="Node"]
script = ExtResource("1")
'@
    $nodeScene = Run-FastCheck $repo $successGodot
    $nodeSceneLog = Get-Content -LiteralPath $targetLog -Raw
    if ($nodeScene.ExitCode -ne 0 -or $nodeScene.Output -notmatch 'FAST-CHECK PASS' -or
        $nodeSceneLog -notmatch 'TARGET=tests/NodeFlowTest\.tscn' -or
        $nodeSceneLog -match 'TARGET=tests/node_flow_test\.gd') {
        throw "Changed Node test was not routed through its companion scene: $($nodeScene.Output) log=$nodeSceneLog"
    }

    $duplicateScenePath = Join-Path $repo 'tests/NodeFlowDuplicate.tscn'
    Copy-Item -LiteralPath $nodeScenePath -Destination $duplicateScenePath
    $ambiguousNode = Run-FastCheck $repo $successGodot
    if ($ambiguousNode.ExitCode -eq 0 -or
        $ambiguousNode.Output -notmatch 'requires exactly one companion \.tscn' -or
        $ambiguousNode.Output -notmatch 'found\s+2') {
        throw "Changed Node test with ambiguous companion scenes did not fail closed: $($ambiguousNode.Output)"
    }
    Remove-Item -LiteralPath $duplicateScenePath
    Remove-Item -LiteralPath $nodeScenePath

    $orphanNode = Run-FastCheck $repo $successGodot
    if ($orphanNode.ExitCode -eq 0 -or
        $orphanNode.Output -notmatch 'requires exactly one companion \.tscn') {
        throw "Changed Node test without a companion scene did not fail closed: $($orphanNode.Output)"
    }
    Remove-Item -LiteralPath $nodeTestPath

    $toolOnlyPath = @(
        $mockBin,
        (Split-Path -Parent (@(Get-Command git.exe -CommandType Application)[0].Source)),
        (Split-Path -Parent (@(Get-Command python.exe -CommandType Application)[0].Source)),
        (Split-Path -Parent (@(Get-Command pwsh.exe -CommandType Application)[0].Source))
    ) | Select-Object -Unique
    $toolOnlyPath = $toolOnlyPath -join [System.IO.Path]::PathSeparator
    Clear-Content -LiteralPath $targetLog
    $pathBeforeFallback = $env:PATH
    try {
        $env:PATH = $toolOnlyPath
        $fallback = Run-FastCheck $repo $null @(
            '-TestTarget', 'tests/game_test.gd', '-AllowedPath', 'game.gd'
        )
    }
    finally { $env:PATH = $pathBeforeFallback }
    $fallbackLog = Get-Content -LiteralPath $targetLog -Raw
    if ($fallback.ExitCode -ne 0 -or $fallback.Output -notmatch 'FAST-CHECK PASS' -or
        $fallbackLog -notmatch 'godot\.cmd') {
        throw "Missing godot4 did not fall back to godot: $($fallback.Output) log=$fallbackLog"
    }

    $hiddenGodot = Join-Path $tempRoot 'godot.hidden'
    Move-Item -LiteralPath $autoGodot -Destination $hiddenGodot
    try {
        $env:PATH = $toolOnlyPath
        $missingGodot = Run-FastCheck $repo $null @(
            '-TestTarget', 'tests/game_test.gd', '-AllowedPath', 'game.gd'
        )
    }
    finally {
        $env:PATH = $pathBeforeFallback
        Move-Item -LiteralPath $hiddenGodot -Destination $autoGodot
    }
    if ($missingGodot.ExitCode -eq 0 -or
        $missingGodot.Output -notmatch 'Pass -GodotConsolePath' -or
        $missingGodot.Output -match 'Index was outside the bounds') {
        throw "Missing Godot aliases did not produce the explicit-path guidance: $($missingGodot.Output)"
    }

    Remove-Item -LiteralPath (Join-Path $repo 'tests/deleted_test.gd')
    $deletedTest = Run-FastCheck $repo $successGodot @('-TestTarget', 'tests/game_test.gd')
    if ($deletedTest.ExitCode -ne 0 -or $deletedTest.Output -notmatch 'FAST-CHECK PASS') {
        throw "Deleted changed Godot test was treated as a runnable target: $($deletedTest.Output)"
    }
    Git $repo checkout -- tests/deleted_test.gd | Out-Null

    $godotError = Run-FastCheck $repo $errorGodot @('-TestTarget', 'tests/game_test.gd', '-AllowControlPlane')
    if ($godotError.ExitCode -eq 0 -or $godotError.Output -notmatch 'SCRIPT ERROR') {
        throw 'SCRIPT ERROR from Godot was not rejected.'
    }

    New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/unsafe.yml') -Value 'name: unsafe' -Encoding UTF8
    $protected = Run-FastCheck $repo $successGodot
    if ($protected.ExitCode -eq 0 -or $protected.Output -notmatch 'PROTECTED') {
        throw 'Ordinary fast-check accepted a control-plane path.'
    }
    Remove-Item -LiteralPath (Join-Path $repo '.github') -Recurse -Force

    Git $repo add game.gd | Out-Null
    Git $repo commit -m 'feature for detached CI' | Out-Null
    $featureHead = (Git $repo rev-parse HEAD).Trim()
    Git $repo checkout --detach $featureHead | Out-Null
    $detachedPass = Run-FastCheck $repo $successGodot @(
        '-ExpectedHeadSha', $featureHead,
        '-ExpectedBranch', 'codex/root/feature',
        '-TestTarget', 'tests/game_test.gd',
        '-AllowControlPlane'
    )
    if ($detachedPass.ExitCode -ne 0 -or $detachedPass.Output -notmatch 'FAST-CHECK PASS') {
        throw "Exact detached CI fast-check failed: $($detachedPass.Output)"
    }
    $baseHead = (Git $repo rev-parse refs/heads/main).Trim()
    $detachedMismatch = Run-FastCheck $repo $successGodot @(
        '-ExpectedHeadSha', $baseHead,
        '-ExpectedBranch', 'codex/root/feature',
        '-AllowControlPlane'
    )
    if ($detachedMismatch.ExitCode -eq 0 -or $detachedMismatch.Output -notmatch 'HEAD mismatch') {
        throw 'Detached CI fast-check accepted a mismatched expected SHA.'
    }

    Git $repo checkout main | Out-Null
    $wrongBranch = Run-FastCheck $repo $successGodot
    if ($wrongBranch.ExitCode -eq 0 -or $wrongBranch.Output -notmatch 'codex/') {
        throw 'Fast-check accepted main.'
    }
    Git $repo checkout -b codex/root/empty | Out-Null
    $empty = Run-FastCheck $repo $successGodot
    if ($empty.ExitCode -eq 0 -or $empty.Output -notmatch 'found no changes') {
        throw 'Fast-check accepted an empty branch.'
    }

    Set-Content -LiteralPath (Join-Path $repo 'asset.bin') -Encoding ASCII -Value @'
version https://git-lfs.github.com/spec/v1
oid sha256:0000000000000000000000000000000000000000000000000000000000000000
size 1
'@
    Git $repo add asset.bin | Out-Null
    $oldGitExecPath = $env:GIT_EXEC_PATH
    try {
        $env:GIT_EXEC_PATH = $mockBin
        $env:FAST_LFS_LISTING = '{"files":[{"name":"asset.bin","checkout":false}]}'
        $pointer = Run-FastCheck $repo $successGodot @('-AllowControlPlane')
    }
    finally {
        if ($null -eq $oldGitExecPath) { Remove-Item Env:GIT_EXEC_PATH -ErrorAction SilentlyContinue }
        else { $env:GIT_EXEC_PATH = $oldGitExecPath }
        Remove-Item Env:FAST_LFS_LISTING -ErrorAction SilentlyContinue
    }
    if ($pointer.ExitCode -eq 0 -or $pointer.Output -notmatch 'LFS pointers remain unhydrated') {
        throw "Fast-check accepted a tracked LFS pointer in the working tree: $($pointer.Output)"
    }
    Git $repo reset -- asset.bin | Out-Null
    Remove-Item -LiteralPath (Join-Path $repo 'asset.bin')

    Set-Content -LiteralPath (Join-Path $repo 'rename-proof.txt') -Value 'candidate change' -Encoding UTF8
    try {
        $env:FAST_LFS_LISTING = '{"files":[{"name":"deleted-before-rename.bin","checkout":false}]}'
        $deletedRenameSource = Run-FastCheck $repo $successGodot @('-AllowControlPlane')
    }
    finally {
        Remove-Item Env:FAST_LFS_LISTING -ErrorAction SilentlyContinue
    }
    if ($deletedRenameSource.ExitCode -ne 0 -or $deletedRenameSource.Output -notmatch 'FAST-CHECK PASS') {
        throw "Fast-check treated a deleted LFS rename source as an unhydrated candidate path: $($deletedRenameSource.Output)"
    }
    Remove-Item -LiteralPath (Join-Path $repo 'rename-proof.txt')

    $pathBeforeMissingTool = $env:PATH
    try {
        $env:PATH = $mockBin
        $missingTool = Run-FastCheck $repo $successGodot
    }
    finally {
        $env:PATH = $pathBeforeMissingTool
    }
    if ($missingTool.ExitCode -eq 0 -or $missingTool.Output -notmatch "external command 'git'") {
        throw 'Missing git was not reported as a nonzero command-start failure.'
    }

    Write-Host 'PASS agent_fast_check Godot-scene-routing/deleted-test/explicit/fallback/missing-guidance/local-branch/detached-SHA/diff/LFS/missing-tool contract'
}
finally {
    if (Get-Variable oldPath -ErrorAction SilentlyContinue) { $env:PATH = $oldPath }
    Remove-Item Env:FAST_TARGET_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:FAST_LFS_LISTING -ErrorAction SilentlyContinue
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
