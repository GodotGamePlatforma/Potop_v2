#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $projectRoot 'tools/publish_agent_pr.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-publish-pr-test-" + [guid]::NewGuid().ToString('N'))
$expectedSlug = 'GodotGamePlatforma/Potop_v2'
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
    if ($result.ExitCode -ne 0) { throw "git failed: $($result.Output)" }
    return $result.Output
}

function Write-Utf8Fixture {
    param([string]$Path, [string]$Value)
    [System.IO.File]::WriteAllText($Path, $Value, [System.Text.UTF8Encoding]::new($false))
}

function New-Fixture {
    param(
        [string]$Name,
        [switch]$ControlPlane,
        [switch]$MissingFastCheck
    )
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
    if (-not $MissingFastCheck) {
        Write-Utf8Fixture (Join-Path $repo 'tools/agent_fast_check.ps1') @'
#requires -Version 5.1
param(
    [string]$Repository,
    [string]$BaseRef,
    [string]$GodotConsolePath,
    [string]$PowerShellCommand = 'pwsh',
    [string[]]$TestTarget = @(),
    [switch]$AllowControlPlane
)
if (-not [string]::IsNullOrWhiteSpace($env:MOCK_FAST_LOG)) {
    Add-Content -LiteralPath $env:MOCK_FAST_LOG -Value "base=$BaseRef allow=$($AllowControlPlane.IsPresent)"
}
if ($env:MOCK_FAST_MODE -eq 'fail') { throw 'injected fast-check failure' }
if ($env:MOCK_FAST_MODE -eq 'dirty') {
    Set-Content -LiteralPath (Join-Path $Repository 'fast-check-dirty.txt') -Value 'dirty'
}
Write-Host 'FAST-CHECK PASS fixture'
'@
    }
    Write-Utf8Fixture (Join-Path $repo 'game.txt') "base`n"
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null

    $githubUrl = "https://github.com/$expectedSlug.git"
    $remoteUri = 'file:///' + ($remote.Replace('\', '/'))
    Git $repo config "url.$remoteUri.insteadOf" $githubUrl | Out-Null
    Git $repo remote add origin $githubUrl | Out-Null
    Git $repo push -u origin main | Out-Null
    $branch = "codex/root/$Name"
    Git $repo checkout -b $branch | Out-Null
    if ($ControlPlane) {
        New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') | Out-Null
        Write-Utf8Fixture (Join-Path $repo '.github/workflows/change.yml') "name: change`n"
    }
    else {
        Write-Utf8Fixture (Join-Path $repo 'game.txt') "feature`n"
    }
    Git $repo add . | Out-Null
    Git $repo commit -m feature | Out-Null
    return [pscustomobject]@{
        Root = $root
        Remote = $remote
        Repo = $repo
        Branch = $branch
        Head = (Git $repo rev-parse HEAD).Trim()
    }
}

function Initialize-GhState {
    param([object]$Fixture, [bool]$Existing, [bool]$AutoEnabled)
    $statePath = Join-Path $Fixture.Root 'gh-state.json'
    $auto = $null
    if ($AutoEnabled) { $auto = [ordered]@{ mergeMethod = 'SQUASH' } }
    $state = [ordered]@{
        exists = $Existing
        auto = $auto
        head = $Fixture.Head
    }
    Write-Utf8Fixture $statePath ($state | ConvertTo-Json -Depth 5 -Compress)
    return $statePath
}

function Run-Publish {
    param(
        [object]$Fixture,
        [string]$Slug = $expectedSlug,
        [switch]$OmitSlug,
        [switch]$ExistingPr,
        [switch]$AutoEnabled,
        [ValidateSet('', 'fail', 'dirty')][string]$FastMode = '',
        [switch]$HeadRaceOnMerge,
        [string]$PowerShellCommand = 'pwsh'
    )
    $statePath = Initialize-GhState $Fixture $ExistingPr.IsPresent $AutoEnabled.IsPresent
    $logPath = Join-Path $Fixture.Root 'gh.log'
    $fastLog = Join-Path $Fixture.Root 'fast.log'
    Remove-Item -LiteralPath $logPath,$fastLog -Force -ErrorAction SilentlyContinue
    $env:MOCK_HEAD = $Fixture.Head
    $env:MOCK_BRANCH = $Fixture.Branch
    $env:MOCK_BASE = 'main'
    $env:MOCK_GH_LOG = $logPath
    $env:MOCK_GH_STATE = $statePath
    $env:MOCK_FAST_LOG = $fastLog
    $env:MOCK_FAST_MODE = $FastMode
    if ($HeadRaceOnMerge) { $env:MOCK_HEAD_RACE = '1' }
    else { Remove-Item Env:MOCK_HEAD_RACE -ErrorAction SilentlyContinue }

    $arguments = @(
        '-NoLogo', '-NoProfile', '-File', $helper,
        '-Repository', $Fixture.Repo,
        '-Title', 'Test PR',
        '-Body', 'Test body',
        '-PowerShellCommand', $PowerShellCommand
    )
    if (-not $OmitSlug) { $arguments += @('-RepositorySlug', $Slug) }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $hostPowerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    $log = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { '' }
    $fast = if (Test-Path -LiteralPath $fastLog) { Get-Content -LiteralPath $fastLog -Raw } else { '' }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    foreach ($name in @(
        'MOCK_HEAD','MOCK_BRANCH','MOCK_BASE','MOCK_GH_LOG','MOCK_GH_STATE',
        'MOCK_FAST_LOG','MOCK_FAST_MODE','MOCK_HEAD_RACE'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
        Log = $log
        FastLog = $fast
        State = $state
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $mockBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Path $mockBin | Out-Null
    Set-Content -LiteralPath (Join-Path $mockBin 'gh.cmd') -Encoding ASCII -Value '@echo off
python "%~dp0gh_mock.py" %*'
    Write-Utf8Fixture (Join-Path $mockBin 'gh_mock.py') @'
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["MOCK_GH_LOG"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
with open(os.environ["MOCK_GH_STATE"], "r", encoding="utf-8-sig") as handle:
    state = json.load(handle)

def save():
    with open(os.environ["MOCK_GH_STATE"], "w", encoding="utf-8") as handle:
        json.dump(state, handle, sort_keys=True)

if args[:2] == ["pr", "list"]:
    print(json.dumps([{"number": 1}] if state["exists"] else []))
elif args[:2] == ["pr", "create"]:
    state["exists"] = True
    state["auto"] = None
    save()
    print("https://example.invalid/pr/1")
elif args[:2] == ["pr", "edit"]:
    pass
elif args[:2] == ["pr", "view"]:
    print(json.dumps({
        "number": 1,
        "url": "https://example.invalid/pr/1",
        "state": "OPEN",
        "headRefName": os.environ["MOCK_BRANCH"],
        "headRefOid": state["head"],
        "baseRefName": os.environ["MOCK_BASE"],
        "autoMergeRequest": state["auto"],
    }))
elif args[:2] == ["pr", "merge"] and "--disable-auto" in args:
    state["auto"] = None
    save()
elif args[:2] == ["pr", "merge"] and "--auto" in args:
    if os.environ.get("MOCK_HEAD_RACE") == "1":
        state["head"] = "f" * 40
        save()
        print("head changed before auto-merge", file=sys.stderr)
        raise SystemExit(1)
    state["auto"] = {"mergeMethod": "SQUASH"}
    save()
raise SystemExit(0)
'@
    $oldPath = $env:PATH
    $env:PATH = "$mockBin;$oldPath"

    $ordinary = New-Fixture 'ordinary'
    $ordinaryResult = Run-Publish $ordinary -OmitSlug
    if ($ordinaryResult.ExitCode -ne 0) { throw "Ordinary publish failed: $($ordinaryResult.Output)" }
    if ($ordinaryResult.FastLog -notmatch 'base=[0-9a-f]{40} allow=False') {
        throw "Ordinary publication did not run canonical fast-check on an exact base: $($ordinaryResult.FastLog)"
    }
    $ordinaryMerge = "pr merge 1 --repo $expectedSlug --auto --squash --match-head-commit $($ordinary.Head)"
    if (-not $ordinaryResult.Log.Contains($ordinaryMerge)) {
        throw "Ordinary PR did not bind native auto+squash to exact HEAD: $($ordinaryResult.Log)"
    }
    if ($null -eq $ordinaryResult.State.auto -or [string]$ordinaryResult.State.auto.mergeMethod -cne 'SQUASH') {
        throw 'Ordinary PR did not finish with SQUASH auto-merge enabled.'
    }
    if ((Git $ordinary.Remote rev-parse "refs/heads/$($ordinary.Branch)").Trim() -cne $ordinary.Head) {
        throw 'Ordinary branch was not pushed at exact HEAD.'
    }

    $control = New-Fixture 'control-plane' -ControlPlane
    $controlResult = Run-Publish $control -ExistingPr -AutoEnabled
    if ($controlResult.ExitCode -ne 0 -or $controlResult.Output -notmatch 'CONTROL-PLANE') {
        throw "Control-plane publication failed: $($controlResult.Output)"
    }
    if ($controlResult.FastLog -notmatch 'allow=True') {
        throw 'Control-plane publication did not explicitly allow the canonical local check.'
    }
    if (-not $controlResult.Log.Contains("pr merge 1 --repo $expectedSlug --disable-auto") -or
        $controlResult.Log -match '(?m)^pr merge 1 .*--auto ') {
        throw "Control-plane PR was not left reliably outside auto-merge: $($controlResult.Log)"
    }
    if ($null -ne $controlResult.State.auto) {
        throw 'Control-plane stale auto-merge was not disabled.'
    }

    $red = New-Fixture 'red-fast-check'
    $redResult = Run-Publish $red -FastMode fail
    if ($redResult.ExitCode -eq 0 -or $redResult.Output -notmatch 'agent_fast_check failed') {
        throw "Red canonical fast-check did not block publication: $($redResult.Output)"
    }
    if (-not [string]::IsNullOrWhiteSpace($redResult.Log) -or
        (Git-Result $red.Remote show-ref --verify --quiet "refs/heads/$($red.Branch)").ExitCode -eq 0) {
        throw 'Red canonical fast-check allowed a push or GitHub PR operation.'
    }

    $missing = New-Fixture 'missing-fast-check' -MissingFastCheck
    $missingResult = Run-Publish $missing
    if ($missingResult.ExitCode -eq 0 -or $missingResult.Output -notmatch 'Canonical fast-check is missing') {
        throw "Missing canonical fast-check did not block publication: $($missingResult.Output)"
    }
    if (-not [string]::IsNullOrWhiteSpace($missingResult.Log) -or
        (Git-Result $missing.Remote show-ref --verify --quiet "refs/heads/$($missing.Branch)").ExitCode -eq 0) {
        throw 'Missing canonical fast-check allowed a push or GitHub PR operation.'
    }

    $mismatch = New-Fixture 'slug-mismatch'
    $mismatchResult = Run-Publish $mismatch -Slug 'DifferentOwner/DifferentRepo'
    if ($mismatchResult.ExitCode -eq 0 -or $mismatchResult.Output -notmatch 'does not match origin') {
        throw "Repository slug mismatch was accepted: $($mismatchResult.Output)"
    }
    if (-not [string]::IsNullOrWhiteSpace($mismatchResult.Log) -or
        (Git-Result $mismatch.Remote show-ref --verify --quiet "refs/heads/$($mismatch.Branch)").ExitCode -eq 0) {
        throw 'Repository slug mismatch allowed a push or GitHub PR operation.'
    }

    $pushUrlMismatch = New-Fixture 'pushurl-mismatch'
    Git $pushUrlMismatch.Repo config remote.origin.pushurl 'https://github.com/DifferentOwner/DifferentRepo.git' | Out-Null
    $pushUrlMismatchResult = Run-Publish $pushUrlMismatch
    if ($pushUrlMismatchResult.ExitCode -eq 0 -or
        $pushUrlMismatchResult.Output -notmatch 'pushurl does not identify the same' -or
        -not [string]::IsNullOrWhiteSpace($pushUrlMismatchResult.Log)) {
        throw "Mismatched origin push URL was accepted: $($pushUrlMismatchResult.Output)"
    }

    $selfModify = New-Fixture 'classifier-self-modification' -ControlPlane
    Write-Utf8Fixture (Join-Path $selfModify.Repo 'tools/ci_protected_paths.py') @'
import argparse
import json
p = argparse.ArgumentParser()
p.add_argument("command")
p.add_argument("--repo")
p.add_argument("--base")
p.add_argument("--head")
a = p.parse_args()
print(json.dumps({"status":"PASS","base":a.base,"head":a.head,"protected_path_count":0}))
'@
    Git $selfModify.Repo add tools/ci_protected_paths.py | Out-Null
    Git $selfModify.Repo commit -m 'candidate attempts to relax classifier' | Out-Null
    $selfModify.Head = (Git $selfModify.Repo rev-parse HEAD).Trim()
    $selfModifyResult = Run-Publish $selfModify
    if ($selfModifyResult.ExitCode -ne 0 -or $selfModifyResult.Output -notmatch 'CONTROL-PLANE' -or
        $selfModifyResult.Log -match '(?m)^pr merge 1 .*--auto ') {
        throw "Exact-base classifier did not contain candidate self-modification: $($selfModifyResult.Output)"
    }

    $invalidJson = New-Fixture 'classifier-invalid-json'
    Write-Utf8Fixture (Join-Path $invalidJson.Repo 'tools/ci_protected_paths.py') "print('not-json')`n"
    Git $invalidJson.Repo add tools/ci_protected_paths.py | Out-Null
    Git $invalidJson.Repo commit -m 'invalid classifier output' | Out-Null
    $invalidJson.Head = (Git $invalidJson.Repo rev-parse HEAD).Trim()
    $invalidJsonResult = Run-Publish $invalidJson
    if ($invalidJsonResult.ExitCode -eq 0 -or $invalidJsonResult.Output -notmatch 'without valid JSON' -or
        -not [string]::IsNullOrWhiteSpace($invalidJsonResult.Log) -or
        (Git-Result $invalidJson.Remote show-ref --verify --quiet "refs/heads/$($invalidJson.Branch)").ExitCode -eq 0) {
        throw "Exit-zero classifier without status=PASS JSON did not stop before publication: $($invalidJsonResult.Output)"
    }

    $classifierCrash = New-Fixture 'classifier-crash'
    Write-Utf8Fixture (Join-Path $classifierCrash.Repo 'tools/ci_protected_paths.py') "raise RuntimeError('unexpected classifier crash')`n"
    Git $classifierCrash.Repo add tools/ci_protected_paths.py | Out-Null
    Git $classifierCrash.Repo commit -m 'crashing classifier' | Out-Null
    $classifierCrash.Head = (Git $classifierCrash.Repo rev-parse HEAD).Trim()
    $classifierCrashResult = Run-Publish $classifierCrash
    if ($classifierCrashResult.ExitCode -eq 0 -or $classifierCrashResult.Output -notmatch 'failed unexpectedly' -or
        -not [string]::IsNullOrWhiteSpace($classifierCrashResult.Log) -or
        (Git-Result $classifierCrash.Remote show-ref --verify --quiet "refs/heads/$($classifierCrash.Branch)").ExitCode -eq 0) {
        throw "Unexpected classifier error was treated as control-plane: $($classifierCrashResult.Output)"
    }

    $headRace = New-Fixture 'head-race'
    $headRaceResult = Run-Publish $headRace -HeadRaceOnMerge
    if ($headRaceResult.ExitCode -eq 0 -or $headRaceResult.Output -notmatch 'head changed before auto-merge' -or
        $headRaceResult.Log -notmatch "--match-head-commit $($headRace.Head)") {
        throw "PR head race was not stopped by exact --match-head-commit: $($headRaceResult.Output)"
    }
    if ($null -ne $headRaceResult.State.auto) {
        throw 'Head race enabled auto-merge for the wrong revision.'
    }

    $dirtyAfterFast = New-Fixture 'dirty-after-fast'
    $dirtyAfterFastResult = Run-Publish $dirtyAfterFast -FastMode dirty
    if ($dirtyAfterFastResult.ExitCode -eq 0 -or $dirtyAfterFastResult.Output -notmatch 'changed during canonical fast-check') {
        throw 'Publisher did not re-check clean exact state after canonical fast-check.'
    }
    if (-not [string]::IsNullOrWhiteSpace($dirtyAfterFastResult.Log) -or
        (Git-Result $dirtyAfterFast.Remote show-ref --verify --quiet "refs/heads/$($dirtyAfterFast.Branch)").ExitCode -eq 0) {
        throw 'Post-fast-check state drift allowed a push or GitHub PR operation.'
    }

    $toolDirectory = @{
        git = Split-Path -Parent (@(Get-Command git.exe -CommandType Application)[0].Source)
        python = Split-Path -Parent (@(Get-Command python.exe -CommandType Application)[0].Source)
        pwsh = Split-Path -Parent (@(Get-Command pwsh.exe -CommandType Application)[0].Source)
        gh = $mockBin
    }
    foreach ($missingToolName in @('git', 'python', 'pwsh', 'gh')) {
        $missingToolFixture = New-Fixture "missing-$missingToolName"
        $limitedDirectories = @()
        foreach ($availableToolName in @('git', 'python', 'pwsh', 'gh')) {
            if ($availableToolName -cne $missingToolName) {
                $limitedDirectories += $toolDirectory[$availableToolName]
            }
        }
        $limitedDirectories += (Join-Path $env:SystemRoot 'System32')
        try {
            $env:PATH = (@($limitedDirectories | Select-Object -Unique) -join ';')
            $selectedPowerShell = if ($missingToolName -ceq 'pwsh') {
                'potop-definitely-missing-pwsh'
            }
            else {
                'pwsh'
            }
            $missingToolResult = Run-Publish $missingToolFixture -PowerShellCommand $selectedPowerShell
        }
        finally {
            $env:PATH = "$mockBin;$oldPath"
        }
        if ($missingToolResult.ExitCode -eq 0 -or
            $missingToolResult.Output -notmatch "external command '$missingToolName'") {
            throw "Missing $missingToolName did not fail explicitly: $($missingToolResult.Output)"
        }
        if ((Git-Result $missingToolFixture.Remote show-ref --verify --quiet "refs/heads/$($missingToolFixture.Branch)").ExitCode -eq 0) {
            throw "Missing $missingToolName allowed branch publication."
        }
    }

    $source = Get-Content -LiteralPath $helper -Raw
    foreach ($forbidden in @('Start-Sleep', 'check-runs', 'repository_dispatch', 'CandidateReceipt', 'integration-green')) {
        if ($source -match [regex]::Escape($forbidden)) { throw "publish-pr contains forbidden legacy token '$forbidden'." }
    }
    Write-Host 'PASS publish_agent_pr preflight-fast-check/trusted-union/derived-repo/exact-push/single-PR/native-auto/manual-control-plane/race contract'
}
finally {
    if (Get-Variable oldPath -ErrorAction SilentlyContinue) { $env:PATH = $oldPath }
    foreach ($name in @(
        'MOCK_HEAD','MOCK_BRANCH','MOCK_BASE','MOCK_GH_LOG','MOCK_GH_STATE',
        'MOCK_FAST_LOG','MOCK_FAST_MODE','MOCK_HEAD_RACE'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
