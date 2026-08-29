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
$realGitPath = @(Get-Command git.exe -CommandType Application)[0].Source

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

    Git $repo remote add origin $remote | Out-Null
    Git $repo push -u origin main | Out-Null
    $githubUrl = "https://github.com/$expectedSlug.git"
    Git $repo remote set-url origin $githubUrl | Out-Null
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

function Advance-Main {
    param(
        [Parameter(Mandatory = $true)][object]$Fixture,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Git $Fixture.Repo checkout main | Out-Null
    $absolutePath = Join-Path $Fixture.Repo $RelativePath
    $parent = Split-Path -Parent $absolutePath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Write-Utf8Fixture $absolutePath $Value
    Git $Fixture.Repo add -- $RelativePath | Out-Null
    Git $Fixture.Repo commit -m 'advance main fixture' | Out-Null
    $mainHead = (Git $Fixture.Repo rev-parse HEAD).Trim()
    Git $Fixture.Repo push $Fixture.Remote 'main:main' | Out-Null
    Git $Fixture.Repo checkout $Fixture.Branch | Out-Null
    return $mainHead
}

function Initialize-GhState {
    param(
        [object]$Fixture,
        [bool]$Existing,
        [bool]$AutoEnabled,
        [bool]$Foreign,
        [string]$QueueMethod,
        [bool]$QueueExists,
        [string]$QueueAcceptance
    )
    $statePath = Join-Path $Fixture.Root 'gh-state.json'
    $auto = $null
    if ($AutoEnabled) { $auto = [ordered]@{ mergeMethod = 'SQUASH' } }
    $state = [ordered]@{
        exists = $Existing
        auto = $auto
        entry = $false
        head = $Fixture.Head
        foreign = $Foreign
        queueMethod = $QueueMethod
        queueExists = $QueueExists
        queueAcceptance = $QueueAcceptance
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
        [switch]$ForeignPr,
        [ValidateSet('SQUASH', 'MERGE', 'REBASE')][string]$QueueMethod = 'SQUASH',
        [ValidateSet('pending', 'queued', 'both', 'none', 'foreign')][string]$QueueAcceptance = 'pending',
        [switch]$MissingQueue,
        [switch]$AdvanceBranchOnPush,
        [switch]$MergeTreeFailure,
        [string]$PowerShellCommand = 'pwsh'
    )
    $statePath = Initialize-GhState `
        $Fixture `
        $ExistingPr.IsPresent `
        $AutoEnabled.IsPresent `
        $ForeignPr.IsPresent `
        $QueueMethod `
        (-not $MissingQueue.IsPresent) `
        $QueueAcceptance
    $logPath = Join-Path $Fixture.Root 'gh.log'
    $fastLog = Join-Path $Fixture.Root 'fast.log'
    $transportLog = Join-Path $Fixture.Root 'git-transport.log'
    Remove-Item -LiteralPath $logPath,$fastLog,$transportLog -Force -ErrorAction SilentlyContinue
    $env:MOCK_HEAD = $Fixture.Head
    $env:MOCK_BRANCH = $Fixture.Branch
    $env:MOCK_BASE = 'main'
    $env:MOCK_GH_LOG = $logPath
    $env:MOCK_GH_STATE = $statePath
    $env:MOCK_FAST_LOG = $fastLog
    $env:MOCK_FAST_MODE = $FastMode
    $env:MOCK_REAL_GIT = $realGitPath
    $env:MOCK_GIT_REMOTE = $Fixture.Remote
    $env:MOCK_GIT_TRANSPORT_LOG = $transportLog
    if ($HeadRaceOnMerge) { $env:MOCK_HEAD_RACE = '1' }
    else { Remove-Item Env:MOCK_HEAD_RACE -ErrorAction SilentlyContinue }
    $raceHead = ''
    if ($AdvanceBranchOnPush) {
        $tree = (Git $Fixture.Repo rev-parse 'HEAD^{tree}').Trim()
        $raceHead = (Git -Repository $Fixture.Repo -Arguments @(
            '-c', 'user.name=Push Race',
            '-c', 'user.email=push-race@example.invalid',
            'commit-tree', $tree,
            '-p', $Fixture.Head,
            '-m', 'advance before push spawn'
        )).Trim()
        $env:MOCK_ADVANCE_ON_PUSH = '1'
        $env:MOCK_RACE_HEAD = $raceHead
    }
    else {
        Remove-Item Env:MOCK_ADVANCE_ON_PUSH,Env:MOCK_RACE_HEAD -ErrorAction SilentlyContinue
    }
    if ($MergeTreeFailure) { $env:MOCK_MERGE_TREE_FAILURE = '1' }
    else { Remove-Item Env:MOCK_MERGE_TREE_FAILURE -ErrorAction SilentlyContinue }

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
    $transport = if (Test-Path -LiteralPath $transportLog) { Get-Content -LiteralPath $transportLog -Raw } else { '' }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    foreach ($name in @(
        'MOCK_HEAD','MOCK_BRANCH','MOCK_BASE','MOCK_GH_LOG','MOCK_GH_STATE',
        'MOCK_FAST_LOG','MOCK_FAST_MODE','MOCK_HEAD_RACE','MOCK_REAL_GIT',
        'MOCK_GIT_REMOTE','MOCK_GIT_TRANSPORT_LOG','MOCK_ADVANCE_ON_PUSH','MOCK_RACE_HEAD',
        'MOCK_MERGE_TREE_FAILURE'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
        Log = $log
        FastLog = $fast
        TransportLog = $transport
        State = $state
        RaceHead = $raceHead
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $ghBin = Join-Path $tempRoot 'gh-bin'
    $gitBin = Join-Path $tempRoot 'git-bin'
    New-Item -ItemType Directory -Path $ghBin,$gitBin | Out-Null
    Set-Content -LiteralPath (Join-Path $ghBin 'gh.cmd') -Encoding ASCII -Value '@echo off
python "%~dp0gh_mock.py" %*'
    Write-Utf8Fixture (Join-Path $ghBin 'gh_mock.py') @'
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
    state["entry"] = False
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
        "isCrossRepository": state["foreign"],
        "headRepository": {
            "name": "Potop_v2",
            "nameWithOwner": (
                "ForeignOwner/Potop_v2" if state["foreign"]
                else "GodotGamePlatforma/Potop_v2"
            ),
        },
        "headRepositoryOwner": {
            "login": "ForeignOwner" if state["foreign"] else "GodotGamePlatforma"
        },
    }))
elif args[:2] == ["api", "graphql"]:
    queue = None
    if state["queueExists"]:
        queue = {
            "id": "QUEUE_main",
            "configuration": {"mergeMethod": state["queueMethod"]},
        }
    entry = None
    if state["entry"]:
        entry_queue_id = "QUEUE_other" if state["queueAcceptance"] == "foreign" else "QUEUE_main"
        entry = {"mergeQueue": {"id": entry_queue_id}}
    auto = None if state["auto"] is None else {"enabledAt": "2026-08-28T00:00:00Z"}
    print(json.dumps({
        "data": {
            "repository": {
                "pullRequest": {
                    "state": "OPEN",
                    "headRefName": os.environ["MOCK_BRANCH"],
                    "headRefOid": state["head"],
                    "baseRefName": os.environ["MOCK_BASE"],
                    "autoMergeRequest": auto,
                    "mergeQueueEntry": entry,
                },
                "mergeQueue": queue,
            }
        }
    }))
elif args[:2] == ["pr", "merge"] and "--disable-auto" in args:
    state["auto"] = None
    state["entry"] = False
    save()
elif args[:2] == ["pr", "merge"] and "--auto" in args:
    if os.environ.get("MOCK_HEAD_RACE") == "1":
        state["head"] = "f" * 40
        save()
        print("head changed before auto-merge", file=sys.stderr)
        raise SystemExit(1)
    acceptance = state["queueAcceptance"]
    state["auto"] = {"mergeMethod": "MERGE"} if acceptance in {"pending", "both"} else None
    state["entry"] = acceptance in {"queued", "both", "foreign"}
    save()
raise SystemExit(0)
'@
    Write-Utf8Fixture (Join-Path $gitBin 'git.ps1') @'
& python (Join-Path $PSScriptRoot 'git_mock.py') @args
exit $LASTEXITCODE
'@
    Write-Utf8Fixture (Join-Path $gitBin 'git_mock.py') @'
import os
import subprocess
import sys

args = sys.argv[1:]
real_git = os.environ["MOCK_REAL_GIT"]

index = 0
repository = os.getcwd()
while index < len(args):
    if args[index] == "-C" and index + 1 < len(args):
        repository = args[index + 1]
        index += 2
        continue
    if args[index] == "-c" and index + 1 < len(args):
        index += 2
        continue
    if args[index].startswith("-"):
        index += 1
        continue
    break

command = args[index] if index < len(args) else ""
if command == "merge-tree" and os.environ.get("MOCK_MERGE_TREE_FAILURE") == "1":
    print("injected merge-tree failure", file=sys.stderr)
    raise SystemExit(2)
if command in {"fetch", "push", "ls-remote"}:
    with open(os.environ["MOCK_GIT_TRANSPORT_LOG"], "a", encoding="utf-8") as handle:
        handle.write(" ".join(args[index:]) + "\n")
    if command == "push" and os.environ.get("MOCK_ADVANCE_ON_PUSH") == "1":
        subprocess.run(
            [
                real_git,
                "-C",
                repository,
                "update-ref",
                "refs/heads/" + os.environ["MOCK_BRANCH"],
                os.environ["MOCK_RACE_HEAD"],
                os.environ["MOCK_HEAD"],
            ],
            check=True,
        )
    rewritten = list(args)
    for position in range(index + 1, len(rewritten)):
        if rewritten[position] == "origin":
            rewritten[position] = os.environ["MOCK_GIT_REMOTE"]
            break
    raise SystemExit(subprocess.run([real_git, *rewritten]).returncode)

raise SystemExit(subprocess.run([real_git, *args]).returncode)
'@
    $oldPath = $env:PATH
    $env:PATH = "$gitBin;$ghBin;$oldPath"

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
    if ($null -eq $ordinaryResult.State.auto -or [string]$ordinaryResult.State.auto.mergeMethod -cne 'MERGE' -or
        [bool]$ordinaryResult.State.entry -or $ordinaryResult.Log -notmatch '(?m)^api graphql ') {
        throw 'Ordinary PR did not accept the queue-managed pending-check state.'
    }
    if ((Git $ordinary.Remote rev-parse "refs/heads/$($ordinary.Branch)").Trim() -cne $ordinary.Head) {
        throw 'Ordinary branch was not pushed at exact HEAD.'
    }
    $publishProof = "PUBLISH PASS LocalHead=$($ordinary.Head) RemoteHead=$($ordinary.Head) PullRequestHead=$($ordinary.Head) PullRequest=1"
    if ($ordinaryResult.Output -notmatch "(?m)^$([regex]::Escape($publishProof))\r?$") {
        throw "Successful publisher output omitted the exact three-SHA proof: $($ordinaryResult.Output)"
    }

    $conflictingMain = New-Fixture 'conflicting-main'
    $conflictingBase = Advance-Main $conflictingMain 'game.txt' "main conflict`n"
    $conflictingResult = Run-Publish $conflictingMain
    if ($conflictingResult.ExitCode -eq 0 -or
        $conflictingResult.Output -notmatch 'conflicts with freshly fetched origin/main' -or
        $conflictingResult.Output -notmatch $conflictingBase -or
        -not [string]::IsNullOrWhiteSpace($conflictingResult.FastLog) -or
        -not [string]::IsNullOrWhiteSpace($conflictingResult.Log) -or
        $conflictingResult.TransportLog -match '(?m)^push ' -or
        (Git-Result $conflictingMain.Remote show-ref --verify --quiet "refs/heads/$($conflictingMain.Branch)").ExitCode -eq 0) {
        throw "Conflicting fresh main was not rejected before fast-check/push/PR: $($conflictingResult.Output)"
    }

    $compatibleMain = New-Fixture 'compatible-main'
    $compatibleBase = Advance-Main $compatibleMain 'main-only.txt' "main-only change`n"
    $compatibleResult = Run-Publish $compatibleMain
    if ($compatibleResult.ExitCode -ne 0 -or
        $compatibleResult.FastLog -notmatch "base=$compatibleBase allow=False") {
        throw "Non-conflicting stale branch was rejected or used the wrong fresh base: $($compatibleResult.Output) fast=$($compatibleResult.FastLog)"
    }

    $mergeTreeFailure = New-Fixture 'merge-tree-tool-failure'
    $mergeTreeFailureResult = Run-Publish $mergeTreeFailure -MergeTreeFailure
    if ($mergeTreeFailureResult.ExitCode -eq 0 -or
        $mergeTreeFailureResult.Output -notmatch 'merge-tree preflight failed \(exit 2\)' -or
        -not [string]::IsNullOrWhiteSpace($mergeTreeFailureResult.FastLog) -or
        -not [string]::IsNullOrWhiteSpace($mergeTreeFailureResult.Log) -or
        $mergeTreeFailureResult.TransportLog -match '(?m)^push ') {
        throw "Merge-tree tool failure was not fail-closed before publication: $($mergeTreeFailureResult.Output)"
    }

    $queueReady = New-Fixture 'queue-ready'
    $queueReadyResult = Run-Publish $queueReady -QueueAcceptance queued
    if ($queueReadyResult.ExitCode -ne 0 -or $null -ne $queueReadyResult.State.auto -or
        -not [bool]$queueReadyResult.State.entry -or
        $queueReadyResult.Log -notmatch "--match-head-commit $($queueReady.Head)") {
        throw "Already-ready PR did not finish in the exact native queue: $($queueReadyResult.Output)"
    }

    $queueTransition = New-Fixture 'queue-transition'
    $queueTransitionResult = Run-Publish $queueTransition -QueueAcceptance both
    if ($queueTransitionResult.ExitCode -ne 0 -or $null -eq $queueTransitionResult.State.auto -or
        -not [bool]$queueTransitionResult.State.entry) {
        throw "Safe auto-request to queue transition was rejected: $($queueTransitionResult.Output)"
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

    $foreign = New-Fixture 'foreign-reuse'
    $foreignResult = Run-Publish $foreign -ExistingPr -AutoEnabled -ForeignPr
    if ($foreignResult.ExitCode -eq 0 -or
        $foreignResult.Output -notmatch 'different repository' -or
        $foreignResult.Log -match '(?m)^pr (?:edit|merge) ') {
        throw "Foreign same-branch/SHA PR was edited or accepted: $($foreignResult.Output) log=$($foreignResult.Log)"
    }
    if ($null -eq $foreignResult.State.auto -or
        [string]$foreignResult.State.auto.mergeMethod -cne 'SQUASH') {
        throw 'Foreign PR auto-merge state was mutated before repository identity passed.'
    }

    $wrongQueueMethod = New-Fixture 'wrong-queue-method'
    $wrongQueueMethodResult = Run-Publish $wrongQueueMethod -QueueMethod MERGE
    if ($wrongQueueMethodResult.ExitCode -eq 0 -or
        $wrongQueueMethodResult.Output -notmatch 'does not have an exact native SQUASH merge queue' -or
        $wrongQueueMethodResult.Log -match '(?m)^pr merge .*--auto ') {
        throw "Non-squash native queue was accepted: $($wrongQueueMethodResult.Output)"
    }

    $missingQueue = New-Fixture 'missing-queue'
    $missingQueueResult = Run-Publish $missingQueue -MissingQueue
    if ($missingQueueResult.ExitCode -eq 0 -or
        $missingQueueResult.Output -notmatch 'does not have an exact native SQUASH merge queue' -or
        $missingQueueResult.Log -match '(?m)^pr merge .*--auto ') {
        throw "Missing native queue was accepted: $($missingQueueResult.Output)"
    }

    $notAccepted = New-Fixture 'queue-not-accepted'
    $notAcceptedResult = Run-Publish $notAccepted -QueueAcceptance none
    if ($notAcceptedResult.ExitCode -eq 0 -or
        $notAcceptedResult.Output -notmatch 'did not return an accepted native state' -or
        $notAcceptedResult.Log -notmatch '--auto --squash --match-head-commit') {
        throw "Missing auto-request and queue entry were accepted: $($notAcceptedResult.Output)"
    }

    $foreignQueue = New-Fixture 'foreign-queue-entry'
    $foreignQueueResult = Run-Publish $foreignQueue -QueueAcceptance foreign
    if ($foreignQueueResult.ExitCode -eq 0 -or
        $foreignQueueResult.Output -notmatch 'does not belong to the exact' -or
        $foreignQueueResult.Log -notmatch '--auto --squash --match-head-commit') {
        throw "Foreign merge queue entry was accepted: $($foreignQueueResult.Output)"
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
    if ($mismatchResult.ExitCode -eq 0 -or $mismatchResult.Output -notmatch 'does not match effective origin') {
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
        $pushUrlMismatchResult.Output -notmatch 'Effective origin fetch' -or
        -not [string]::IsNullOrWhiteSpace($pushUrlMismatchResult.Log)) {
        throw "Mismatched origin push URL was accepted: $($pushUrlMismatchResult.Output)"
    }

    foreach ($rewriteKind in @('fetch', 'push')) {
        $rewritten = New-Fixture "effective-$rewriteKind-rewrite"
        $differentRemote = Join-Path $rewritten.Root 'different.git'
        Git $rewritten.Root init --bare $differentRemote | Out-Null
        $differentUri = 'file:///' + ($differentRemote.Replace('\', '/'))
        $githubUrl = "https://github.com/$expectedSlug.git"
        if ($rewriteKind -ceq 'fetch') {
            Git $rewritten.Repo config "url.$differentUri.insteadOf" $githubUrl | Out-Null
        }
        else {
            Git $rewritten.Repo config "url.$differentUri.pushInsteadOf" $githubUrl | Out-Null
        }
        if ((Git $rewritten.Repo config --get remote.origin.url).Trim() -cne $githubUrl) {
            throw 'Rewrite fixture no longer has an apparently canonical raw origin URL.'
        }
        $rewrittenResult = Run-Publish $rewritten
        if ($rewrittenResult.ExitCode -eq 0 -or
            $rewrittenResult.Output -notmatch 'not one unambiguous GitHub repository URL|Effective origin fetch' -or
            -not [string]::IsNullOrWhiteSpace($rewrittenResult.TransportLog) -or
            -not [string]::IsNullOrWhiteSpace($rewrittenResult.Log) -or
            (Git-Result $rewritten.Remote show-ref --verify --quiet "refs/heads/$($rewritten.Branch)").ExitCode -eq 0) {
            throw "Effective $rewriteKind URL rewrite was not rejected before fetch/push/GitHub: $($rewrittenResult.Output) transport=$($rewrittenResult.TransportLog)"
        }
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

    $pushRace = New-Fixture 'exact-object-push-race'
    $pushRaceResult = Run-Publish $pushRace -AdvanceBranchOnPush
    $remoteRaceProbe = Git-Result $pushRace.Remote rev-parse "refs/heads/$($pushRace.Branch)"
    $remoteRaceHead = if ($remoteRaceProbe.ExitCode -eq 0) { $remoteRaceProbe.Output.Trim() } else { '' }
    if ($pushRaceResult.ExitCode -eq 0 -or
        $pushRaceResult.Output -notmatch 'branch ref or clean state changed' -or
        $remoteRaceProbe.ExitCode -ne 0 -or
        $remoteRaceHead -cne $pushRace.Head -or
        $remoteRaceHead -ceq $pushRaceResult.RaceHead -or
        (Git $pushRace.Repo rev-parse "refs/heads/$($pushRace.Branch)").Trim() -cne $pushRaceResult.RaceHead -or
        -not [string]::IsNullOrWhiteSpace($pushRaceResult.Log) -or
        $pushRaceResult.TransportLog -notmatch [regex]::Escape("push origin $($pushRace.Head):refs/heads/$($pushRace.Branch)")) {
        throw "Exact-object push race was not fail-closed at A: $($pushRaceResult.Output) transport=$($pushRaceResult.TransportLog) remote=$remoteRaceHead remote_error=$($remoteRaceProbe.Output) B=$($pushRaceResult.RaceHead)"
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
        git = $gitBin
        python = Split-Path -Parent (@(Get-Command python.exe -CommandType Application)[0].Source)
        pwsh = Split-Path -Parent (@(Get-Command pwsh.exe -CommandType Application)[0].Source)
        gh = $ghBin
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
            $env:PATH = "$gitBin;$ghBin;$oldPath"
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
    foreach ($required in @(
        "'remote', 'get-url', '--all', 'origin'",
        "'remote', 'get-url', '--push', '--all', 'origin'",
        'isCrossRepository,headRepository,headRepositoryOwner',
        'mergeQueue(branch:$base)',
        "'merge-tree', '--write-tree', '--quiet'",
        '"${head}:refs/heads/$branch"',
        'PUBLISH PASS LocalHead={0} RemoteHead={1} PullRequestHead={2}',
        'LocalHead = $head',
        'RemoteHead = [string]$finalRemoteFields[0]',
        'PullRequestHead = [string]$postOperationPr.headRefOid'
    )) {
        if (-not $source.Contains($required)) {
            throw "publish-pr is missing required exact identity/push binding '$required'."
        }
    }
    if ($source -match [regex]::Escape('--set-upstream')) {
        throw 'publish-pr still pushes a moving branch through --set-upstream.'
    }
    Write-Host 'PASS publish_agent_pr effective-origin/exact-object-push/repo-bound-PR/explicit-three-SHA-proof/SQUASH-native-queue/manual-control-plane/race contract'
}
finally {
    if (Get-Variable oldPath -ErrorAction SilentlyContinue) { $env:PATH = $oldPath }
    foreach ($name in @(
        'MOCK_HEAD','MOCK_BRANCH','MOCK_BASE','MOCK_GH_LOG','MOCK_GH_STATE',
        'MOCK_FAST_LOG','MOCK_FAST_MODE','MOCK_HEAD_RACE','MOCK_REAL_GIT',
        'MOCK_GIT_REMOTE','MOCK_GIT_TRANSPORT_LOG','MOCK_ADVANCE_ON_PUSH','MOCK_RACE_HEAD',
        'MOCK_MERGE_TREE_FAILURE'
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
