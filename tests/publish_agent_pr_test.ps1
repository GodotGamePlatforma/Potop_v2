#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/publish_agent_pr.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-publish-pr-test-" + [guid]::NewGuid().ToString('N'))

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git.exe -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($output | Out-String)" }
    return ($output | Out-String).Trim()
}

function New-Fixture {
    param([string]$Name, [switch]$ControlPlane)
    $root = Join-Path $tempRoot $Name
    $remote = Join-Path $root 'origin.git'
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $root | Out-Null
    Git $root init --bare $remote | Out-Null
    Git $root init -b main $repo | Out-Null
    Git $repo config user.email 'publish-test@example.invalid' | Out-Null
    Git $repo config user.name 'Publish Test' | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'tools') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tools/ci_protected_paths.py') -Destination (Join-Path $repo 'tools/ci_protected_paths.py')
    Set-Content -LiteralPath (Join-Path $repo 'game.txt') -Value 'base' -Encoding utf8NoBOM
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null
    Git $repo remote add origin $remote | Out-Null
    Git $repo push -u origin main | Out-Null
    Git $repo checkout -b "codex/root/$Name" | Out-Null
    if ($ControlPlane) {
        New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo '.github/workflows/change.yml') -Value 'name: change' -Encoding utf8NoBOM
    }
    else {
        Set-Content -LiteralPath (Join-Path $repo 'game.txt') -Value 'feature' -Encoding utf8NoBOM
    }
    Git $repo add . | Out-Null
    Git $repo commit -m feature | Out-Null
    return [pscustomobject]@{ Root = $root; Remote = $remote; Repo = $repo; Branch = "codex/root/$Name"; Head = (Git $repo rev-parse HEAD).Trim() }
}

function Run-Publish {
    param([object]$Fixture)
    $env:MOCK_HEAD = $Fixture.Head
    $env:MOCK_BRANCH = $Fixture.Branch
    $env:MOCK_BASE = 'main'
    $env:MOCK_GH_LOG = Join-Path $Fixture.Root 'gh.log'
    $output = @(& pwsh -NoLogo -NoProfile -File $helper `
        -Repository $Fixture.Repo `
        -RepositorySlug 'GodotGamePlatforma/Potop_v2' `
        -Title 'Test PR' `
        -Body 'Test body' 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String).Trim(); Log = (Get-Content -LiteralPath $env:MOCK_GH_LOG -Raw) }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $mockBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Path $mockBin | Out-Null
    Set-Content -LiteralPath (Join-Path $mockBin 'gh.cmd') -Encoding ascii -Value '@echo off
python "%~dp0gh_mock.py" %*'
    Set-Content -LiteralPath (Join-Path $mockBin 'gh_mock.py') -Encoding utf8NoBOM -Value @'
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["MOCK_GH_LOG"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
if args[:2] == ["pr", "list"]:
    print("[]")
elif args[:2] == ["pr", "view"]:
    print(json.dumps({
        "number": 1,
        "url": "https://example.invalid/pr/1",
        "state": "OPEN",
        "headRefName": os.environ["MOCK_BRANCH"],
        "headRefOid": os.environ["MOCK_HEAD"],
        "baseRefName": os.environ["MOCK_BASE"],
    }))
elif args[:2] == ["pr", "create"]:
    print("https://example.invalid/pr/1")
sys.exit(0)
'@
    $oldPath = $env:PATH
    $env:PATH = "$mockBin;$oldPath"

    $ordinary = New-Fixture 'ordinary'
    $ordinaryResult = Run-Publish $ordinary
    if ($ordinaryResult.ExitCode -ne 0) { throw "Ordinary publish failed: $($ordinaryResult.Output)" }
    if ($ordinaryResult.Log -notmatch '(?m)^pr merge 1 .*--auto --squash') {
        throw "Ordinary PR did not enable native auto+squash: $($ordinaryResult.Log)"
    }
    if ((Git $ordinary.Remote rev-parse "refs/heads/$($ordinary.Branch)").Trim() -cne $ordinary.Head) {
        throw 'Ordinary branch was not pushed at exact HEAD.'
    }

    $control = New-Fixture 'control-plane' -ControlPlane
    $controlResult = Run-Publish $control
    if ($controlResult.ExitCode -ne 0 -or $controlResult.Output -notmatch 'CONTROL-PLANE') {
        throw "Control-plane publication failed: $($controlResult.Output)"
    }
    if ($controlResult.Log -match '(?m)^pr merge ') {
        throw 'Control-plane PR was automatically enqueued.'
    }

    Add-Content -LiteralPath (Join-Path $ordinary.Repo 'game.txt') -Value 'dirty' -Encoding utf8NoBOM
    $dirty = Run-Publish $ordinary
    if ($dirty.ExitCode -eq 0 -or $dirty.Output -notmatch 'clean worktree') {
        throw 'Dirty worktree was accepted by publish-pr.'
    }

    $source = Get-Content -LiteralPath $helper -Raw
    foreach ($forbidden in @('Start-Sleep', 'check-runs', 'repository_dispatch', 'CandidateReceipt', 'integration-green')) {
        if ($source -match [regex]::Escape($forbidden)) { throw "publish-pr contains forbidden legacy token '$forbidden'." }
    }
    Write-Host 'PASS publish_agent_pr exact-push/single-PR/native-auto/manual-control-plane/no-wait contract'
}
finally {
    if (Get-Variable oldPath -ErrorAction SilentlyContinue) { $env:PATH = $oldPath }
    foreach ($name in @('MOCK_HEAD','MOCK_BRANCH','MOCK_BASE','MOCK_GH_LOG')) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
