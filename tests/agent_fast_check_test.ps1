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
    $worktree = Join-Path $tempRoot 'worktree'
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
param([string]$GodotConsolePath,[string]$SourceRepositoryPath,[string]$Target)
if ($GodotConsolePath -like '*error*') { throw 'SCRIPT ERROR: parser failure' }
Add-Content -LiteralPath $env:FAST_TARGET_LOG -Value "GODOT=$GodotConsolePath TARGET=$Target"
Write-Host "TARGET PASS $Target"
'@
    Set-Content -LiteralPath (Join-Path $repo 'tests/game_test.gd') -Encoding UTF8 -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $repo 'tests/direct_scene_tree_test.gd') -Encoding UTF8 -Value 'extends SceneTree'
    Set-Content -LiteralPath (Join-Path $repo 'tests/explicit_scene_test.gd') -Encoding UTF8 -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $repo 'tests/ExplicitSceneTest.tscn') -Encoding UTF8 -Value @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/explicit_scene_test.gd" id="1"]

[node name="ExplicitSceneTest" type="Node"]
script = ExtResource("1")
'@
    Set-Content -LiteralPath (Join-Path $repo 'tests/unique_scene_test.gd') -Encoding UTF8 -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $repo 'tests/UniqueSceneTest.tscn') -Encoding UTF8 -Value @'
[gd_scene load_steps=2 format=3]

[ext_resource path="res://tests/unique_scene_test.gd" type="Script" id="1"]

[node name="UniqueSceneTest" type="Node"]
script = ExtResource("1")
'@
    Set-Content -LiteralPath (Join-Path $repo 'tests/UniqueSceneSubstringDecoy.tscn') -Encoding UTF8 -Value @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/unique_scene_test.gd.extra" id="1"]

[node name="SubstringDecoy" type="Node"]
script = ExtResource("1")
'@
    Set-Content -LiteralPath (Join-Path $repo 'tests/no_wrapper_test.gd') -Encoding UTF8 -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $repo 'tests/ambiguous_scene_test.gd') -Encoding UTF8 -Value 'extends Node'
    foreach ($suffix in @('A', 'B')) {
        Set-Content -LiteralPath (Join-Path $repo "tests/AmbiguousSceneTest$suffix.tscn") -Encoding UTF8 -Value @"
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/ambiguous_scene_test.gd" id="1"]

[node name="AmbiguousSceneTest$suffix" type="Node"]
script = ExtResource("1")
"@
    }
    Set-Content -LiteralPath (Join-Path $repo 'game.gd') -Encoding UTF8 -Value 'extends Node'
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null
    Git $repo worktree add -b codex/root/feature $worktree main | Out-Null
    Add-Content -LiteralPath (Join-Path $worktree 'game.gd') -Value 'var changed := true' -Encoding UTF8

    $pass = Run-FastCheck $worktree $successGodot @('-TestTarget', 'tests/game_test.gd', '-AllowedPath', 'game.gd')
    if ($pass.ExitCode -ne 0 -or $pass.Output -notmatch 'FAST-CHECK PASS') {
        throw "Expected linked-worktree fast-check PASS: $($pass.Output)"
    }
    if ((Get-Content -LiteralPath $targetLog -Raw) -notmatch 'tests/game_test.gd') {
        throw 'Targeted test runner was not invoked.'
    }

    Add-Content -LiteralPath (Join-Path $worktree 'tests/direct_scene_tree_test.gd') -Value 'var changed := true' -Encoding UTF8
    Clear-Content -LiteralPath $targetLog
    $directSceneTree = Run-FastCheck $worktree $successGodot
    $directSceneTreeLog = @(Get-Content -LiteralPath $targetLog | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($directSceneTree.ExitCode -ne 0 -or $directSceneTree.Output -notmatch 'FAST-CHECK PASS' -or
        $directSceneTreeLog.Count -ne 1 -or
        $directSceneTreeLog[0] -notmatch 'TARGET=tests/direct_scene_tree_test\.gd$') {
        throw "Changed SceneTree test did not run its .gd target exactly once: $($directSceneTree.Output) log=$($directSceneTreeLog -join '; ')"
    }
    Set-Content -LiteralPath (Join-Path $worktree 'tests/direct_scene_tree_test.gd') -Encoding UTF8 -Value 'extends SceneTree'

    Add-Content -LiteralPath (Join-Path $worktree 'tests/explicit_scene_test.gd') -Value 'var changed := true' -Encoding UTF8
    Clear-Content -LiteralPath $targetLog
    $explicitScene = Run-FastCheck $worktree $successGodot @('-TestTarget', 'tests/ExplicitSceneTest.tscn')
    $explicitSceneLog = @(Get-Content -LiteralPath $targetLog | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($explicitScene.ExitCode -ne 0 -or $explicitScene.Output -notmatch 'FAST-CHECK PASS' -or
        $explicitSceneLog.Count -ne 1 -or
        $explicitSceneLog[0] -notmatch 'TARGET=tests/ExplicitSceneTest\.tscn$') {
        throw "Explicit scene-backed test did not run only its .tscn target exactly once: $($explicitScene.Output) log=$($explicitSceneLog -join '; ')"
    }
    Set-Content -LiteralPath (Join-Path $worktree 'tests/explicit_scene_test.gd') -Encoding UTF8 -Value 'extends Node'

    Add-Content -LiteralPath (Join-Path $worktree 'tests/unique_scene_test.gd') -Value 'var changed := true' -Encoding UTF8
    Clear-Content -LiteralPath $targetLog
    $uniqueScene = Run-FastCheck $worktree $successGodot
    $uniqueSceneLog = @(Get-Content -LiteralPath $targetLog | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($uniqueScene.ExitCode -ne 0 -or $uniqueScene.Output -notmatch 'FAST-CHECK PASS' -or
        $uniqueSceneLog.Count -ne 1 -or
        $uniqueSceneLog[0] -notmatch 'TARGET=tests/UniqueSceneTest\.tscn$') {
        throw "Unique exact scene wrapper was not autodiscovered exactly once: $($uniqueScene.Output) log=$($uniqueSceneLog -join '; ')"
    }
    Set-Content -LiteralPath (Join-Path $worktree 'tests/unique_scene_test.gd') -Encoding UTF8 -Value 'extends Node'

    Add-Content -LiteralPath (Join-Path $worktree 'tests/no_wrapper_test.gd') -Value 'var changed := true' -Encoding UTF8
    Clear-Content -LiteralPath $targetLog
    $missingScene = Run-FastCheck $worktree $successGodot
    $missingSceneLog = Get-Content -LiteralPath $targetLog -Raw
    if ($null -eq $missingSceneLog) { $missingSceneLog = '' }
    else { $missingSceneLog = $missingSceneLog.Trim() }
    if ($missingScene.ExitCode -eq 0 -or $missingScene.Output -notmatch '\-TestTarget' -or
        -not [string]::IsNullOrWhiteSpace($missingSceneLog)) {
        throw "Node-based test without a wrapper did not fail closed with -TestTarget guidance: $($missingScene.Output) log=$missingSceneLog"
    }
    Set-Content -LiteralPath (Join-Path $worktree 'tests/no_wrapper_test.gd') -Encoding UTF8 -Value 'extends Node'

    Add-Content -LiteralPath (Join-Path $worktree 'tests/ambiguous_scene_test.gd') -Value 'var changed := true' -Encoding UTF8
    Clear-Content -LiteralPath $targetLog
    $ambiguousScene = Run-FastCheck $worktree $successGodot
    $ambiguousSceneLog = Get-Content -LiteralPath $targetLog -Raw
    if ($null -eq $ambiguousSceneLog) { $ambiguousSceneLog = '' }
    else { $ambiguousSceneLog = $ambiguousSceneLog.Trim() }
    if ($ambiguousScene.ExitCode -eq 0 -or $ambiguousScene.Output -notmatch '\-TestTarget' -or
        -not [string]::IsNullOrWhiteSpace($ambiguousSceneLog)) {
        throw "Node-based test with ambiguous wrappers did not fail closed with -TestTarget guidance: $($ambiguousScene.Output) log=$ambiguousSceneLog"
    }
    Set-Content -LiteralPath (Join-Path $worktree 'tests/ambiguous_scene_test.gd') -Encoding UTF8 -Value 'extends Node'

    $primaryMain = Run-FastCheck $repo $successGodot
    if ($primaryMain.ExitCode -eq 0 -or $primaryMain.Output -notmatch 'separate linked Git worktree') {
        throw "Fast-check accepted the primary main checkout: $($primaryMain.Output)"
    }
    Git $repo checkout -b codex/root/primary-bypass | Out-Null
    $primaryCodex = Run-FastCheck $repo $successGodot
    if ($primaryCodex.ExitCode -eq 0 -or $primaryCodex.Output -notmatch 'separate linked Git worktree') {
        throw "Fast-check accepted a codex/* branch in the primary checkout: $($primaryCodex.Output)"
    }
    Git $repo checkout main | Out-Null

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
        $fallback = Run-FastCheck $worktree $null @(
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
        $missingGodot = Run-FastCheck $worktree $null @(
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

    $godotError = Run-FastCheck $worktree $errorGodot @('-TestTarget', 'tests/game_test.gd', '-AllowControlPlane')
    if ($godotError.ExitCode -eq 0 -or $godotError.Output -notmatch 'SCRIPT ERROR') {
        throw 'SCRIPT ERROR from Godot was not rejected.'
    }

    New-Item -ItemType Directory -Path (Join-Path $worktree '.github/workflows') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree '.github/workflows/unsafe.yml') -Value 'name: unsafe' -Encoding UTF8
    $protected = Run-FastCheck $worktree $successGodot
    if ($protected.ExitCode -eq 0 -or $protected.Output -notmatch 'PROTECTED') {
        throw 'Ordinary fast-check accepted a control-plane path.'
    }
    Remove-Item -LiteralPath (Join-Path $worktree '.github') -Recurse -Force

    Git $worktree add game.gd | Out-Null
    Git $worktree commit -m 'feature for detached CI' | Out-Null
    $featureHead = (Git $worktree rev-parse HEAD).Trim()
    Git $worktree checkout --detach $featureHead | Out-Null
    $detachedPass = Run-FastCheck $worktree $successGodot @(
        '-ExpectedHeadSha', $featureHead,
        '-ExpectedBranch', 'codex/root/feature',
        '-TestTarget', 'tests/game_test.gd',
        '-AllowControlPlane'
    )
    if ($detachedPass.ExitCode -ne 0 -or $detachedPass.Output -notmatch 'FAST-CHECK PASS') {
        throw "Exact detached CI fast-check failed: $($detachedPass.Output)"
    }
    $baseHead = (Git $worktree rev-parse refs/heads/main).Trim()
    $detachedMismatch = Run-FastCheck $worktree $successGodot @(
        '-ExpectedHeadSha', $baseHead,
        '-ExpectedBranch', 'codex/root/feature',
        '-AllowControlPlane'
    )
    if ($detachedMismatch.ExitCode -eq 0 -or $detachedMismatch.Output -notmatch 'HEAD mismatch') {
        throw 'Detached CI fast-check accepted a mismatched expected SHA.'
    }

    Git $worktree checkout -b feature/wrong $featureHead | Out-Null
    $wrongBranch = Run-FastCheck $worktree $successGodot
    if ($wrongBranch.ExitCode -eq 0 -or $wrongBranch.Output -notmatch 'codex/') {
        throw 'Fast-check accepted a non-codex branch in a linked worktree.'
    }
    Git $worktree checkout -b codex/root/empty refs/heads/main | Out-Null
    $empty = Run-FastCheck $worktree $successGodot
    if ($empty.ExitCode -eq 0 -or $empty.Output -notmatch 'found no changes') {
        throw 'Fast-check accepted an empty branch.'
    }

    Set-Content -LiteralPath (Join-Path $worktree 'asset.bin') -Encoding ASCII -Value @'
version https://git-lfs.github.com/spec/v1
oid sha256:0000000000000000000000000000000000000000000000000000000000000000
size 1
'@
    $oldGitExecPath = $env:GIT_EXEC_PATH
    try {
        $env:GIT_EXEC_PATH = $mockBin
        $env:FAST_LFS_LISTING = '{"files":[{"name":"asset.bin","checkout":false}]}'
        $pointer = Run-FastCheck $worktree $successGodot @('-AllowControlPlane')
    }
    finally {
        if ($null -eq $oldGitExecPath) { Remove-Item Env:GIT_EXEC_PATH -ErrorAction SilentlyContinue }
        else { $env:GIT_EXEC_PATH = $oldGitExecPath }
        Remove-Item Env:FAST_LFS_LISTING -ErrorAction SilentlyContinue
    }
    if ($pointer.ExitCode -eq 0 -or $pointer.Output -notmatch 'LFS pointers remain unhydrated') {
        throw "Fast-check accepted a tracked LFS pointer in the working tree: $($pointer.Output)"
    }
    Remove-Item -LiteralPath (Join-Path $worktree 'asset.bin')

    $pathBeforeMissingTool = $env:PATH
    try {
        $env:PATH = $mockBin
        $missingTool = Run-FastCheck $worktree $successGodot
    }
    finally {
        $env:PATH = $pathBeforeMissingTool
    }
    if ($missingTool.ExitCode -eq 0 -or $missingTool.Output -notmatch "external command 'git'") {
        throw 'Missing git was not reported as a nonzero command-start failure.'
    }

    Write-Host 'PASS agent_fast_check linked-worktree-only/scene-target-routing/Godot-explicit/fallback/missing-guidance/local-branch/detached-SHA/diff/LFS/missing-tool contract'
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
