#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/agent_fast_check.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-fast-check-test-" + [guid]::NewGuid().ToString('N'))

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git.exe -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($output | Out-String)" }
    return ($output | Out-String).Trim()
}

function Run-FastCheck {
    param([string]$Repository, [string]$Godot, [string[]]$Extra = @())
    $arguments = @(
        '-NoLogo', '-NoProfile', '-File', $helper,
        '-Repository', $Repository,
        '-BaseRef', 'refs/heads/main',
        '-GodotConsolePath', $Godot
    ) + $Extra
    $output = @(& pwsh @arguments 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String).Trim() }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $repo = Join-Path $tempRoot 'repo'
    $mockBin = Join-Path $tempRoot 'bin'
    $targetLog = Join-Path $tempRoot 'target.log'
    New-Item -ItemType Directory -Path $mockBin | Out-Null
    Set-Content -LiteralPath (Join-Path $mockBin 'git-lfs.cmd') -Encoding ascii -Value @'
@echo off
if "%1"=="version" echo git-lfs/3.0.0
exit /b 0
'@
    $successGodot = Join-Path $mockBin 'godot-success.cmd'
    $errorGodot = Join-Path $mockBin 'godot-error.cmd'
    Set-Content -LiteralPath $successGodot -Encoding ascii -Value "@echo off`necho Godot Engine test`nexit /b 0"
    Set-Content -LiteralPath $errorGodot -Encoding ascii -Value "@echo off`necho SCRIPT ERROR: parser failure`nexit /b 0"
    $oldPath = $env:PATH
    $env:PATH = "$mockBin;$oldPath"
    $env:FAST_TARGET_LOG = $targetLog

    Git $tempRoot init -b main $repo | Out-Null
    Git $repo config user.email 'fast-test@example.invalid' | Out-Null
    Git $repo config user.name 'Fast Test' | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'tools'),(Join-Path $repo 'tests') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/ci_protected_paths.py') -Destination (Join-Path $repo 'tools/ci_protected_paths.py')
    Set-Content -LiteralPath (Join-Path $repo 'tools/workbench_contract.py') -Encoding utf8NoBOM -Value 'print("EOL PASS")'
    Set-Content -LiteralPath (Join-Path $repo 'tests/run_all_tests.ps1') -Encoding utf8NoBOM -Value @'
param([string]$GodotConsolePath,[string]$SourceRepositoryPath,[string]$Target)
if ($GodotConsolePath -like '*error*') { throw 'SCRIPT ERROR: parser failure' }
Add-Content -LiteralPath $env:FAST_TARGET_LOG -Value $Target
Write-Host "TARGET PASS $Target"
'@
    Set-Content -LiteralPath (Join-Path $repo 'tests/game_test.gd') -Encoding utf8NoBOM -Value 'extends Node'
    Set-Content -LiteralPath (Join-Path $repo 'game.gd') -Encoding utf8NoBOM -Value 'extends Node'
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null
    Git $repo checkout -b codex/root/feature | Out-Null
    Add-Content -LiteralPath (Join-Path $repo 'game.gd') -Value 'var changed := true' -Encoding utf8NoBOM

    $pass = Run-FastCheck $repo $successGodot @('-TestTarget', 'tests/game_test.gd', '-AllowedPath', 'game.gd')
    if ($pass.ExitCode -ne 0 -or $pass.Output -notmatch 'FAST-CHECK PASS') {
        throw "Expected fast-check PASS: $($pass.Output)"
    }
    if ((Get-Content -LiteralPath $targetLog -Raw) -notmatch 'tests/game_test.gd') {
        throw 'Targeted test runner was not invoked.'
    }

    $godotError = Run-FastCheck $repo $errorGodot @('-TestTarget', 'tests/game_test.gd', '-AllowControlPlane')
    if ($godotError.ExitCode -eq 0 -or $godotError.Output -notmatch 'SCRIPT ERROR') {
        throw 'SCRIPT ERROR from Godot was not rejected.'
    }

    New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/unsafe.yml') -Value 'name: unsafe' -Encoding utf8NoBOM
    $protected = Run-FastCheck $repo $successGodot
    if ($protected.ExitCode -eq 0 -or $protected.Output -notmatch 'PROTECTED') {
        throw 'Ordinary fast-check accepted a control-plane path.'
    }
    Remove-Item -LiteralPath (Join-Path $repo '.github') -Recurse -Force

    Git $repo restore game.gd | Out-Null
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

    Write-Host 'PASS agent_fast_check diff-scope/protected-path/LFS/Godot-error/targeted-test contract'
}
finally {
    if (Get-Variable oldPath -ErrorAction SilentlyContinue) { $env:PATH = $oldPath }
    Remove-Item Env:FAST_TARGET_LOG -ErrorAction SilentlyContinue
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
