#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-RunnerInvariant {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$runnerPath = Join-Path $PSScriptRoot "run_all_tests.ps1"
$runnerControlRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$isolatedPythonEntryPath = Join-Path $runnerControlRoot "tools/ci_python_entry.py"
$controlContractToolPath = Join-Path $runnerControlRoot "tools/workbench_contract.py"
$controlLockToolPath = Join-Path $runnerControlRoot "tools/workbench_lock.py"
$tokens = $null
$parseErrors = $null
$runnerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $runnerPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if (@($parseErrors).Count -gt 0) {
    throw "Runner does not parse: $(@($parseErrors | ForEach-Object Message) -join '; ')"
}

$requiredFunctions = @(
    "Get-StructurePackageTestTargets",
    "Get-RunnerTestSelection",
    "Assert-RunnerInvocationMode",
    "Assert-TrackedLfEol",
    "ConvertTo-NormalizedProjectPath",
    "Assert-ProjectGodotCacheAvailable",
    "Remove-IsolatedTestWorkspace",
    "ConvertTo-ProcessArgument",
    "Get-GitSnapshotProjectPaths",
    "Invoke-GitTextQuery",
    "Get-GitSourceIdentity",
    "Get-ProjectSnapshotFingerprint",
    "New-IsolatedTestWorkspace",
    "Get-ExplicitStructureTestPackageId",
    "Get-DirectoryOverlayFingerprint",
    "New-IsolatedTrackedEolProof",
    "Invoke-IsolatedStructureTargetOverlay",
    "Get-AvailableIsolatedTestPort",
    "Get-IsolatedTestUserDirectoryRoot",
    "Assert-IsolatedTestUserDirectoryRoot",
    "New-IsolatedTestRunContext",
    "Release-IsolatedTestRunContext",
    "Invoke-IsolatedTestUserDirectoryRetention",
    "Complete-IsolatedTestUserDirectory",
    "Set-IsolatedGodotRunConfiguration",
    "ConvertTo-TestRunReceiptField",
    "Get-GodotCanonicalEvidenceDigest",
    "Get-IsolatedWorkspaceInputFingerprint",
    "Assert-IsolatedImportInputTransition",
    "New-IsolatedTargetWorkspace",
    "Set-IsolatedGodotTargetConfiguration",
    "Copy-TestCaseForWorkspace",
    "Set-NativeShardDummyAudio",
    "Set-TrustedChildEnvironment",
    "New-RunnerKillOnCloseJob",
    "Complete-RunnerJob",
    "New-TrustedCompletionRecord",
    "Assert-TrustedTargetEvidence",
    "Read-GodotCanonicalEvidenceEnvelope",
    "New-GodotTestShardPlan",
    "Read-GodotTestShardPlan",
    "Assert-GodotTestShardPlanSourceBinding",
    "New-GodotTestShardReceipt",
    "Read-GodotTestShardReceipt",
    "New-GodotTestAggregateReceipt",
    "Merge-GodotTestShardReceipts",
    "Read-GodotTestAggregateReceipt",
    "Assert-GodotTestAggregateReceiptBinding",
    "Read-GodotCandidateRunEvidence",
    "New-GodotTestRunReceipt",
    "Write-GodotTestRunReceipt",
    "ConvertFrom-TestRunReceiptField",
    "Read-GodotTestRunReceipt",
    "Assert-GodotTestRunReceiptBinding",
    "Invoke-PublicationReceiptVerification",
    "Test-GodotTestRunReceipt"
)
$functionDefinitions = @($runnerAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true))
foreach ($functionName in $requiredFunctions) {
    $definition = @($functionDefinitions | Where-Object Name -eq $functionName)
    if ($definition.Count -ne 1) {
        throw "Expected exactly one runner function named '$functionName', found $($definition.Count)."
    }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

$runnerText = [System.IO.File]::ReadAllText($runnerPath)
Assert-RunnerInvariant `
    -Condition (-not $runnerText.Contains("Enter-MapPromotionSnapshotLock")) `
    -Message "The test runner must not acquire map-promotion while copying or testing."
Assert-RunnerInvariant `
    -Condition ($runnerText.Contains('$maxSnapshotAttempts = 3') -and
        $runnerText.Contains('$sourceBefore') -and
        $runnerText.Contains('$sourceAfter') -and
        $runnerText.Contains('$destinationSnapshot')) `
    -Message "The test runner must retain bounded source-before/source-after/copy snapshot verification."
Assert-RunnerInvariant `
    -Condition ($runnerText.Contains('-RunContext $targetContext') -and
        $runnerText.Contains('"--debug-server", $RunContext.DebugServerUri') -and
        $runnerText.Contains('New-IsolatedTestRunContext') -and
        $runnerText.Contains('godot_service_port_scope=import-and-tests')) `
    -Message "Import and every test must receive isolated leased Godot service ports."
Assert-RunnerInvariant `
    -Condition ($runnerText.Contains('[string]$RunReceiptOutputPath') -and
        $runnerText.Contains('-OutputPath $RunReceiptOutputPath')) `
    -Message "Runner must expose the deterministic run receipt through -RunReceiptOutputPath."
Assert-RunnerInvariant `
    -Condition ($runnerText.Contains('[string]$VerifyRunReceipt') -and
        $runnerText.Contains('[string]$CandidateReceipt') -and
        $runnerText.Contains('RUN RECEIPT VERIFIED:')) `
    -Message "Runner must expose fail-closed full-suite receipt verification against a candidate receipt."
Assert-RunnerInvariant `
    -Condition ($runnerText.Contains('Assert-TrackedLfEol -ProjectRoot $sourceProjectRoot') -and
        $runnerText.Contains('"eol-check"') -and
        $runnerText.Contains('[string]$SourceRepositoryPath') -and
        $runnerText.Contains('tools/ci_python_entry.py')) `
    -Message "Runner must reject tracked CRLF/mixed bytes before closing the source snapshot."
foreach ($requiredShardParameter in @(
    '[string]$WriteShardPlan',
    '[int]$HeadlessShardCount = 1',
    '[int]$NativeShardCount = 1',
    '[string]$ShardPlan',
    '[string]$ShardId',
    '[string[]]$AggregateShardReceipt = @()'
)) {
    Assert-RunnerInvariant $runnerText.Contains($requiredShardParameter) "Runner lost shard parameter '$requiredShardParameter'."
}
Assert-RunnerInvariant `
    ([regex]::Matches($runnerText, '(?m)^\s+\$sourceSnapshotReceipt = New-IsolatedTestWorkspace').Count -eq 1) `
    "Shard execution must flow through exactly one main workspace materialization."
Assert-RunnerInvariant `
    ([regex]::Matches($runnerText, '(?m)^\s+\$importReceipt = Invoke-GodotImportPreflight').Count -eq 1) `
    "Shard execution must flow through exactly one main Godot import preflight."
Assert-RunnerInvariant `
    ($runnerText.Contains('New-IsolatedTargetWorkspace') -and
        $runnerText.Contains('Get-IsolatedWorkspaceInputFingerprint') -and
        $runnerText.Contains('Set-IsolatedGodotTargetConfiguration') -and
        $runnerText.Contains('-ProjectRoot $targetWorkspacePath')) `
    "Every target must run from a fresh post-import materialization with a closed input fingerprint."
Assert-RunnerInvariant `
    ($runnerText.Contains('Set-TrustedChildEnvironment') -and
        $runnerText.Contains('New-RunnerKillOnCloseJob') -and
        $runnerText.Contains('Complete-RunnerJob') -and
        $runnerText.Contains('RedirectStandardOutput = $true') -and
        -not $runnerText.Contains('"--log-file"')) `
    "Godot verdict output must use trusted pipes and a kill-on-close process tree, never a child-owned log."
Assert-RunnerInvariant `
    ($runnerText.Contains('$status = "FAIL"') -and
        $runnerText.Contains('New-TrustedCompletionRecord') -and
        $runnerText.Contains('Assert-TrustedTargetEvidence')) `
    "PASS must be fail-closed behind one trusted exact-invocation completion record."
Assert-RunnerInvariant `
    ($runnerText.Contains('$testSelection = if ($shardMode)') -and
        $runnerText.Contains('ManifestTargets = @($activeShardTargets | ForEach-Object Name)')) `
    "Shard execution must consume only the immutable plan target list without rediscovery."
Assert-RunnerInvariant `
    ([regex]::Matches(
        $runnerText,
        '(?m)^\s+"underwater_map_workbench/tests/underwater_map_smoke_test\.gd"\s*$'
    ).Count -eq 1) `
    "The closed full-suite manifest must contain map smoke exactly once."
Assert-RunnerInvariant `
    ([regex]::Matches(
        $runnerText,
        '(?m)^\s{4}if \(\$shardMode\) \{\r?$\n\s{8}Set-NativeShardDummyAudio `'
    ).Count -eq 1) `
    "Shard execution must retain its explicit dummy audio configuration."
Assert-RunnerInvariant `
    ($runnerText.Contains('elseif ($Full -and [string]::Equals(') -and
        $runnerText.Contains('[string]$env:GITHUB_ACTIONS,') -and
        $runnerText.Contains('-TestCases @($testCases | Where-Object { $_.NativeWindow })') -and
        $runnerText.Contains('-ShardLane "native"')) `
    "The direct full GitHub Actions suite must select Dummy audio only for native targets."
Assert-RunnerInvariant `
    ($runnerText.Contains('$engineErrorLines = @($lines | Where-Object { $_ -match "^\s*(?:SCRIPT ERROR|ERROR):" })') -and
        $runnerText.Contains('$reasons.Add("engine output contains ERROR:/SCRIPT ERROR:")')) `
    "Native dummy audio must not weaken fail-closed ERROR:/SCRIPT ERROR: handling."

$headlessArguments = [string[]]@("--headless", "--path", "C:\fixture", "--script", "res://tests/headless.gd")
$headlessCase = [pscustomobject]@{
    Name = "headless.gd"
    NativeWindow = $false
    Arguments = $headlessArguments
}
$headlessArgumentsBefore = [string]::Join("`n", @($headlessCase.Arguments))
Set-NativeShardDummyAudio -TestCases @($headlessCase) -ShardLane "headless"
Assert-RunnerInvariant `
    ([string]::Join("`n", @($headlessCase.Arguments)) -ceq $headlessArgumentsBefore) `
    "Headless shard arguments changed while configuring native dummy audio."

$nativeArguments = [string[]]@("--path", "C:\fixture", "--script", "res://tests/native.gd")
$nativeCase = [pscustomobject]@{
    Name = "native.gd"
    NativeWindow = $true
    Arguments = $nativeArguments
}
Set-NativeShardDummyAudio -TestCases @($nativeCase) -ShardLane "native"
Assert-RunnerInvariant `
    ([string]::Join("`n", @($nativeCase.Arguments)) -ceq
        [string]::Join("`n", @("--audio-driver", "Dummy") + $nativeArguments)) `
    "Native shard did not prepend exactly one explicit Dummy audio-driver selection."

$mixedNativeLaneRejected = $false
try {
    Set-NativeShardDummyAudio `
        -TestCases @([pscustomobject]@{
            Name = "unexpected-headless.gd"
            NativeWindow = $false
            Arguments = [string[]]@("--headless", "--path", "C:\fixture")
        }) `
        -ShardLane "native"
}
catch { $mixedNativeLaneRejected = $_.Exception.Message.Contains("contains non-native target") }
Assert-RunnerInvariant $mixedNativeLaneRejected "Native shard accepted a non-native target."

$existingAudioDriverRejected = $false
try {
    Set-NativeShardDummyAudio `
        -TestCases @([pscustomobject]@{
            Name = "preconfigured-native.gd"
            NativeWindow = $true
            Arguments = [string[]]@("--audio-driver", "Other", "--path", "C:\fixture")
        }) `
        -ShardLane "native"
}
catch { $existingAudioDriverRejected = $_.Exception.Message.Contains("already declares an audio driver") }
Assert-RunnerInvariant $existingAudioDriverRejected "Native shard accepted a second audio-driver declaration."

$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]"\/")
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $tempParent ("ostatni_pomost_runner_test_" + [Guid]::NewGuid().ToString("N"))))
$requiredPrefix = $tempParent + [System.IO.Path]::DirectorySeparatorChar
if (-not $fixtureRoot.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create runner fixture outside the system temp directory: '$fixtureRoot'."
}

try {
    $sourceRoot = Join-Path $fixtureRoot "source checkout with spaces"
    $workspaceRoot = Join-Path $fixtureRoot "isolated workspaces"
    $collisionRoot = [System.IO.Path]::GetFullPath((Join-Path $fixtureRoot "collision workspace"))
    $otherCollisionRoot = [System.IO.Path]::GetFullPath((Join-Path $fixtureRoot "other workspace"))
    [void](New-Item -ItemType Directory -Path $collisionRoot -Force)
    [void](New-Item -ItemType Directory -Path $otherCollisionRoot -Force)
    $script:mockGodotProcesses = @()
    function Get-CimInstance {
        param(
            [string]$ClassName,
            [System.Management.Automation.ActionPreference]$ErrorAction
        )
        return @($script:mockGodotProcesses)
    }
    try {
        $script:mockGodotProcesses = @(
            [pscustomobject]@{
                Name = "godot_console.exe"
                ProcessId = 1001
                CommandLine = 'godot_console.exe --headless --path . --script res://tests/a.gd'
            },
            [pscustomobject]@{
                Name = "godot.exe"
                ProcessId = 1002
                CommandLine = 'godot.exe --headless --path "' + $otherCollisionRoot + '" res://tests/b.tscn'
            }
        )
        Assert-ProjectGodotCacheAvailable -ProjectRoot $collisionRoot

        $script:mockGodotProcesses = @([pscustomobject]@{
            Name = "godot_console.exe"
            ProcessId = 1003
            CommandLine = 'godot_console.exe --headless --path "' + $collisionRoot + '" --script res://tests/c.gd'
        })
        $sameWorkspaceBlocked = $false
        try {
            Assert-ProjectGodotCacheAvailable -ProjectRoot $collisionRoot
        }
        catch {
            $sameWorkspaceBlocked = $_.Exception.Message.Contains(
                "PID 1003 [runtime/test]"
            )
        }
        Assert-RunnerInvariant $sameWorkspaceBlocked "Canonical same-workspace Godot path did not block the runner."
    }
    finally {
        Remove-Item -LiteralPath function:Get-CimInstance -ErrorAction SilentlyContinue
        Remove-Variable -Name mockGodotProcesses -Scope Script -ErrorAction SilentlyContinue
    }
    [void](New-Item -ItemType Directory -Path $sourceRoot -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "tests") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "tools") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "underwater_map_workbench/tools") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "underwater_map_workbench/structures/tower_local/generated") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "underwater_map_workbench/structures/unrelated_stale/generated") -Force)

    [System.IO.File]::WriteAllText(
        (Join-Path $sourceRoot "project.godot"),
        "config_version=5`n`n[application]`n`nconfig/name=`"Runner Fixture`"`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot ".gitignore"), "ignored/`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot ".gitattributes"), "* text=auto eol=lf`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "tracked.txt"), "tracked before`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "deleted.txt"), "staged then deleted`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "tests/explicit_target.gd"), "extends SceneTree`n", [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../tools/workbench_contract.py") -Destination (Join-Path $sourceRoot "tools/workbench_contract.py")
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../tools/workbench_lock.py") -Destination (Join-Path $sourceRoot "tools/workbench_lock.py")
    $fakeBuilder = @'
from pathlib import Path
import os
import sys

if len(sys.argv) != 3 or sys.argv[1] != "--build-structure" or sys.argv[2] != "tower_local":
    raise SystemExit(7)
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools"))
from workbench_contract import verify_isolated_eol_proof

verify_isolated_eol_proof(
    root,
    proof_path=os.environ["OSTATNI_POMOST_ISOLATED_EOL_PROOF_PATH"],
    structure_id=sys.argv[2],
    secret_hex=os.environ["OSTATNI_POMOST_ISOLATED_EOL_PROOF_KEY"],
)
generated = root / ".godot" / "underwater_map_structure_builds" / sys.argv[2] / "generated"
generated.mkdir(parents=True, exist_ok=True)
(generated / "structure.tscn").write_text("[gd_scene]\n", encoding="utf-8", newline="\n")
(generated / "structure_truth.json").write_text('{"package":"tower_local"}\n', encoding="utf-8", newline="\n")
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $sourceRoot "underwater_map_workbench/tools/build_underwater_map.py"),
        $fakeBuilder,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "underwater_map_workbench/structures/tower_local/generated/stale.txt"), "stale target", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "underwater_map_workbench/structures/unrelated_stale/generated/must_remain.txt"), "unrelated stale package", [System.Text.UTF8Encoding]::new($false))

    & git -C $sourceRoot init -q
    if ($LASTEXITCODE -ne 0) { throw "git init failed for runner fixture." }
    & git -c core.autocrlf=false -C $sourceRoot add -- .
    if ($LASTEXITCODE -ne 0) { throw "git add failed for runner fixture." }
    & git -c user.name=RunnerFixture -c user.email=runner.fixture@example.invalid -C $sourceRoot commit -q -m "runner fixture baseline"
    if ($LASTEXITCODE -ne 0) { throw "git commit failed for runner fixture." }

    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "tracked.txt"), "tracked working-tree revision`n", [System.Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath (Join-Path $sourceRoot "deleted.txt") -Force
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "underwater_map_workbench/structures/inflight_package") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "diver_workbench") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "untracked with spaces") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $sourceRoot "ignored") -Force)
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "underwater_map_workbench/structures/inflight_package/runtime.gd"), "extends Node`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "diver_workbench/required_untracked.gd"), "extends Node`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "untracked with spaces/needed source.gd"), "extends Node`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $sourceRoot "ignored/ignored.tmp"), "must not copy`n", [System.Text.UTF8Encoding]::new($false))

    $paths = @(Get-GitSnapshotProjectPaths -ProjectRoot $sourceRoot)
    Assert-RunnerInvariant `
        (@($paths | Where-Object { [string]::IsNullOrEmpty($_) }).Count -eq 0) `
        "Git NUL-delimited path parsing retained the trailing empty record."
    foreach ($requiredPath in @(
        "project.godot",
        "tracked.txt",
        "deleted.txt",
        "tests/explicit_target.gd",
        "underwater_map_workbench/structures/inflight_package/runtime.gd",
        "diver_workbench/required_untracked.gd",
        "untracked with spaces/needed source.gd"
    )) {
        Assert-RunnerInvariant ($paths -ccontains $requiredPath) "Git snapshot omitted required path '$requiredPath'."
    }
    Assert-RunnerInvariant (-not ($paths -ccontains "ignored/ignored.tmp")) "Git snapshot included an ignored file."

    $beforeMutation = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceRoot
    Assert-RunnerInvariant ($beforeMutation.MissingCount -eq 1) "Deleted tracked paths must remain represented in the source fingerprint."
    [System.IO.File]::AppendAllText((Join-Path $sourceRoot "tracked.txt"), "mutation`n", [System.Text.UTF8Encoding]::new($false))
    $afterMutation = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceRoot
    Assert-RunnerInvariant ($beforeMutation.Digest -ne $afterMutation.Digest) "Source fingerprint did not detect a content mutation."

    $explicitSelection = Get-RunnerTestSelection `
        -ResolvedTarget "tests/explicit_target.gd" `
        -ProjectRoot $sourceRoot `
        -FullSuite $false `
        -IncludeSnapshotScenes $false `
        -DefaultHeadlessScriptTests @("default.gd") `
        -DefaultHeadlessFlowScenes @() `
        -SnapshotScenes @()
    Assert-RunnerInvariant ($explicitSelection.ManifestTargets.Count -eq 1) "Explicit target selection added unrelated targets."
    Assert-RunnerInvariant ($explicitSelection.ManifestTargets[0] -eq "tests/explicit_target.gd") "Explicit target selection changed the requested target."
    Assert-RunnerInvariant ($explicitSelection.HeadlessScriptTests.Count -eq 0) "Explicit target selection performed global script discovery."
    Assert-RunnerInvocationMode -InPlaceRequested $false
    $inPlaceRejected = $false
    try {
        Assert-RunnerInvocationMode -InPlaceRequested $true
    }
    catch {
        $inPlaceRejected = $_.Exception.Message.Contains("-InPlace is disabled")
    }
    Assert-RunnerInvariant $inPlaceRejected "Runner did not reject unsafe in-place execution."

    $defaultSelectionFailed = $false
    try {
        [void](Get-RunnerTestSelection `
            -ResolvedTarget $null `
            -ProjectRoot $sourceRoot `
            -FullSuite $false `
            -IncludeSnapshotScenes $false `
            -DefaultHeadlessScriptTests @("default.gd") `
            -DefaultHeadlessFlowScenes @() `
            -SnapshotScenes @())
    }
    catch {
        $defaultSelectionFailed = $_.Exception.Message.Contains("Map manifest is required")
    }
    Assert-RunnerInvariant $defaultSelectionFailed "Default suite did not retain Map package discovery while the explicit target bypassed it."

    $sourceFingerprint = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceRoot
    $sourceSnapshotReceipt = New-IsolatedTestWorkspace -SourceProjectRoot $sourceRoot -WorkspaceRoot $workspaceRoot
    $sourceProjectRoot = $sourceRoot
    Assert-RunnerInvariant `
        ((Get-ExplicitStructureTestPackageId -ResolvedTarget "underwater_map_workbench/structures/tower_local/tests/contract_test.gd") -eq "tower_local") `
        "Explicit structure target did not resolve its package ID."
    Assert-RunnerInvariant `
        ($null -eq (Get-ExplicitStructureTestPackageId -ResolvedTarget "diver_workbench/tests/DiverPresentationTest.tscn")) `
        "Non-structure target incorrectly entered the structure overlay lane."

    $workspacePath = [string]$sourceSnapshotReceipt.WorkspacePath
    Assert-RunnerInvariant (Test-Path -LiteralPath (Join-Path $workspacePath "diver_workbench/required_untracked.gd") -PathType Leaf) "Isolated copy omitted a nonignored untracked Diver source."
    Assert-RunnerInvariant (Test-Path -LiteralPath (Join-Path $workspacePath "underwater_map_workbench/structures/inflight_package/runtime.gd") -PathType Leaf) "Isolated copy omitted a nonignored untracked Map source."
    Assert-RunnerInvariant (-not (Test-Path -LiteralPath (Join-Path $workspacePath "ignored/ignored.tmp"))) "Isolated copy included ignored content."
    Assert-RunnerInvariant (-not (Test-Path -LiteralPath (Join-Path $workspacePath ".git"))) "Isolated copy included Git metadata."
    $copyFingerprint = Get-ProjectSnapshotFingerprint -ProjectRoot $workspacePath -ProjectPaths $sourceFingerprint.ProjectPaths
    Assert-RunnerInvariant ($sourceFingerprint.Digest -eq $copyFingerprint.Digest) "Isolated copy fingerprint differs from the stable source fingerprint."
    Assert-RunnerInvariant ($sourceFingerprint.Digest -eq $sourceSnapshotReceipt.SourceSnapshot.Digest) "Source snapshot receipt differs from the pre-copy source fingerprint."
    $targetAuthority = Join-Path $workspacePath "underwater_map_workbench/structures/tower_local/generated"
    $unrelatedAuthority = Join-Path $workspacePath "underwater_map_workbench/structures/unrelated_stale/generated"
    $structureOverlay = Invoke-IsolatedStructureTargetOverlay `
        -SourceProjectRoot $sourceRoot `
        -IsolatedProjectRoot $workspacePath `
        -StructureId "tower_local" `
        -SourceSnapshotDigest $sourceSnapshotReceipt.SourceSnapshot.Digest `
        -TimeoutSeconds 30
    Assert-RunnerInvariant ($structureOverlay.Version -eq "godot-structure-target-overlay-v1") "Structure target overlay did not publish its schema."
    Assert-RunnerInvariant ($structureOverlay.EolProofVersion -eq "isolated-git-eol-proof-v1") "Structure target overlay did not use the isolated EOL proof."
    Assert-RunnerInvariant ($structureOverlay.EolProofSha256 -match '^[0-9a-f]{64}$') "Structure target overlay did not retain the EOL proof digest."
    Assert-RunnerInvariant ($structureOverlay.FileCount -eq 2) "Structure target overlay did not publish the exact generated file count."
    Assert-RunnerInvariant (Test-Path -LiteralPath (Join-Path $targetAuthority "structure.tscn") -PathType Leaf) "Structure target overlay did not replace target authority."
    Assert-RunnerInvariant (-not (Test-Path -LiteralPath (Join-Path $targetAuthority "stale.txt"))) "Structure target overlay retained stale target authority content."
    Assert-RunnerInvariant (Test-Path -LiteralPath (Join-Path $unrelatedAuthority "must_remain.txt") -PathType Leaf) "Structure target overlay changed an unrelated stale package."
    Assert-RunnerInvariant (-not (Test-Path -LiteralPath (Join-Path $sourceRoot ".godot/underwater_map_structure_builds/tower_local/generated"))) "Structure target overlay wrote into the live/source checkout."
    $contextA = $null
    $contextB = $null
    $targetFixtureA = $null
    $targetFixtureB = $null
    $oldRetainedPath = $null
    try {
        $sourceProjectHashBefore = (Get-FileHash -LiteralPath (Join-Path $sourceRoot "project.godot") -Algorithm SHA256).Hash
        $testUserDirectoryRoot = Join-Path $fixtureRoot "user_data"
        $contextA = New-IsolatedTestRunContext -UserDirectoryRootOverride $testUserDirectoryRoot
        $contextB = New-IsolatedTestRunContext -UserDirectoryRootOverride $testUserDirectoryRoot
        Assert-RunnerInvariant ($contextA.RunId -ne $contextB.RunId) "Two isolated runs received the same run ID."
        Assert-RunnerInvariant ($contextA.UserDirectoryName -ne $contextB.UserDirectoryName) "Two isolated runs received the same user:// directory."
        Assert-RunnerInvariant (@(@($contextA.DebugServerPort, $contextA.DapPort, $contextA.LspPort) | Select-Object -Unique).Count -eq 3) "A run reused one of its Godot service ports."
        $allPorts = @(
            $contextA.DebugServerPort,
            $contextA.DapPort,
            $contextA.LspPort,
            $contextB.DebugServerPort,
            $contextB.DapPort,
            $contextB.LspPort
        )
        Assert-RunnerInvariant (@($allPorts | Select-Object -Unique).Count -eq 6) "Concurrent isolated contexts reused a leased Godot service port."

        $overlayReceipt = Set-IsolatedGodotRunConfiguration `
            -SourceProjectRoot $sourceRoot `
            -IsolatedProjectRoot $workspacePath `
            -RunContext $contextA `
            -SourceSnapshot $sourceSnapshotReceipt.SourceSnapshot
        $sourceProjectHashAfter = (Get-FileHash -LiteralPath (Join-Path $sourceRoot "project.godot") -Algorithm SHA256).Hash
        $isolatedProjectText = [System.IO.File]::ReadAllText((Join-Path $workspacePath "project.godot"))
        Assert-RunnerInvariant ($sourceProjectHashBefore -eq $sourceProjectHashAfter) "Per-run user:// setup modified source project.godot."
        Assert-RunnerInvariant ($isolatedProjectText.Contains("config/use_custom_user_dir=true")) "Isolated project did not enable custom user://."
        Assert-RunnerInvariant ($isolatedProjectText.Contains('config/custom_user_dir_name="' + $contextA.UserDirectoryName + '"')) "Isolated project did not receive the unique user:// name."
        Assert-RunnerInvariant ($overlayReceipt.SourceSnapshotDigest -eq $sourceSnapshotReceipt.SourceSnapshot.Digest) "Test-overlay receipt lost its immutable source digest."
        Assert-RunnerInvariant ($overlayReceipt.BeforeSha256 -ne $overlayReceipt.AfterSha256) "Test overlay did not record the project.godot mutation."
        $receiptHasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes($overlayReceipt.CanonicalReceipt)
            $expectedOverlayDigest = [System.BitConverter]::ToString($receiptHasher.ComputeHash($receiptBytes)).Replace("-", "").ToLowerInvariant()
        }
        finally {
            $receiptHasher.Dispose()
        }
        Assert-RunnerInvariant ($overlayReceipt.Digest -eq $expectedOverlayDigest) "Test-overlay receipt digest is not deterministic."

        $seedInput = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $workspacePath
        $targetFixtureA = (New-IsolatedTargetWorkspace `
            -SeedProjectRoot $workspacePath `
            -WorkspaceRoot $workspaceRoot `
            -TargetIndex 0 `
            -ExpectedSeedFingerprint $seedInput).WorkspacePath
        $targetFixtureB = (New-IsolatedTargetWorkspace `
            -SeedProjectRoot $workspacePath `
            -WorkspaceRoot $workspaceRoot `
            -TargetIndex 1 `
            -ExpectedSeedFingerprint $seedInput).WorkspacePath
        Assert-RunnerInvariant ($targetFixtureA -cne $targetFixtureB) "Two targets reused one workspace path."
        $targetOverlayA = Set-IsolatedGodotTargetConfiguration -SeedProjectRoot $workspacePath -TargetProjectRoot $targetFixtureA -RunContext $contextA
        $targetOverlayB = Set-IsolatedGodotTargetConfiguration -SeedProjectRoot $workspacePath -TargetProjectRoot $targetFixtureB -RunContext $contextB
        Assert-RunnerInvariant ($targetOverlayA.Digest -ne $targetOverlayB.Digest) "Two targets reused one user/overlay identity."
        $targetABefore = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureA
        $targetBBefore = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureB
        [System.IO.File]::AppendAllText((Join-Path $targetFixtureA "tracked.txt"), "target A mutation`n", [System.Text.UTF8Encoding]::new($false))
        $targetAAfter = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureA
        $targetBAfter = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureB
        Assert-RunnerInvariant ($targetAAfter.Digest -ne $targetABefore.Digest) "Per-target fingerprint missed a source mutation."
        Assert-RunnerInvariant ($targetBAfter.Digest -eq $targetBBefore.Digest) "One target mutation leaked into another fresh target workspace."

        $importBefore = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureB
        [System.IO.File]::WriteAllText((Join-Path $targetFixtureB "tests/generated.gd.uid"), "uid://fixture`n", [System.Text.UTF8Encoding]::new($false))
        $importAfterUid = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureB
        $uidTransition = Assert-IsolatedImportInputTransition -Before $importBefore -After $importAfterUid
        Assert-RunnerInvariant ($uidTransition.AddedUidCount -eq 1) "Import transition did not record one deterministic UID sidecar."
        [System.IO.File]::WriteAllText((Join-Path $targetFixtureB "tests/generated.png.import"), "[remap]`n", [System.Text.UTF8Encoding]::new($false))
        $importAfterSidecars = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureB
        $sidecarTransition = Assert-IsolatedImportInputTransition -Before $importBefore -After $importAfterSidecars
        Assert-RunnerInvariant ($sidecarTransition.AddedUidCount -eq 1) "Import transition changed the deterministic UID count."
        Assert-RunnerInvariant ($sidecarTransition.AddedImportCount -eq 1) "Import transition did not record one deterministic import metadata sidecar."
        [System.IO.File]::WriteAllText((Join-Path $targetFixtureB "unexpected.tmp"), "unexpected`n", [System.Text.UTF8Encoding]::new($false))
        $unexpectedImportRejected = $false
        try {
            [void](Assert-IsolatedImportInputTransition `
                -Before $importAfterSidecars `
                -After (Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetFixtureB))
        }
        catch { $unexpectedImportRejected = $true }
        Assert-RunnerInvariant $unexpectedImportRejected "Import transition accepted an unexpected source-tree output."

        $environmentProbe = [System.Diagnostics.ProcessStartInfo]::new()
        $oldGitHubToken = $env:GITHUB_TOKEN
        $oldActionsRuntimeToken = $env:ACTIONS_RUNTIME_TOKEN
        try {
            $env:GITHUB_TOKEN = "must-not-cross"
            $env:ACTIONS_RUNTIME_TOKEN = "must-not-cross"
            $childTemp = Join-Path $targetFixtureB ".godot/runner-temp/probe"
            Set-TrustedChildEnvironment -StartInfo $environmentProbe -TemporaryDirectory $childTemp -InvocationId "probe"
            Assert-RunnerInvariant (-not $environmentProbe.EnvironmentVariables.ContainsKey("GITHUB_TOKEN")) "GitHub token crossed the child environment boundary."
            Assert-RunnerInvariant (-not $environmentProbe.EnvironmentVariables.ContainsKey("ACTIONS_RUNTIME_TOKEN")) "Actions runtime token crossed the child environment boundary."
            Assert-RunnerInvariant ($environmentProbe.EnvironmentVariables["TEMP"] -eq $childTemp) "Child TEMP is not target-private."
        }
        finally {
            $env:GITHUB_TOKEN = $oldGitHubToken
            $env:ACTIONS_RUNTIME_TOKEN = $oldActionsRuntimeToken
        }

        function New-SyntheticTargetEvidence {
            param(
                [string]$Name,
                [string]$Group,
                [string]$Status,
                [int]$ExitCode,
                [bool]$BlockingFailure,
                [string]$RunId,
                [char]$DigestCharacter
            )
            $inputDigest = ([string]$DigestCharacter) * 64
            $invocationDigest = if ($DigestCharacter -eq 'a') { "b" * 64 } else { "c" * 64 }
            $outputDigest = if ($DigestCharacter -eq 'a') { "d" * 64 } else { "e" * 64 }
            $completion = New-TrustedCompletionRecord `
                -InvocationDigest $invocationDigest `
                -TargetName $Name `
                -ExitCode $ExitCode `
                -OutputDigest $outputDigest `
                -InputBeforeDigest $inputDigest `
                -InputAfterDigest $inputDigest
            return [pscustomobject]@{
                Name = $Name
                Group = $Group
                Status = $Status
                ExitCode = $ExitCode
                BlockingFailure = $BlockingFailure
                RunId = $RunId
                UserDirectoryName = "OstatniPomost/TestRuns/$RunId"
                InputBeforeDigest = $inputDigest
                InputAfterDigest = $inputDigest
                InvocationDigest = $invocationDigest
                OutputDigest = $outputDigest
                CompletionVersion = $completion.Version
                CompletionDigest = $completion.Digest
                TargetOverlayVersion = "godot-target-overlay-v1"
                TargetOverlayDigest = "f" * 64
            }
        }

        $duplicateCompletionRejected = $false
        try {
            [void](New-TrustedCompletionRecord `
                -InvocationDigest ("1" * 64) -TargetName "tests/a.gd" -ExitCode 0 `
                -OutputDigest ("2" * 64) -InputBeforeDigest ("3" * 64) -InputAfterDigest ("3" * 64) `
                -RecordCount 2)
        }
        catch { $duplicateCompletionRejected = $true }
        Assert-RunnerInvariant $duplicateCompletionRejected "Trusted completion accepted duplicate terminal records."

        if ($env:OS -eq "Windows_NT") {
            $jobHandle = [IntPtr]::Zero
            $sleepProcess = $null
            $jobClosed = $false
            try {
                $jobHandle = New-RunnerKillOnCloseJob
                $sleepExecutable = (Get-Command -Name "powershell.exe" -CommandType Application).Source
                $sleepInfo = [System.Diagnostics.ProcessStartInfo]::new()
                $sleepInfo.FileName = $sleepExecutable
                $sleepInfo.Arguments = '-NoLogo -NoProfile -Command "Start-Sleep -Seconds 60"'
                $sleepInfo.UseShellExecute = $false
                $sleepInfo.CreateNoWindow = $true
                $sleepProcess = [System.Diagnostics.Process]::new()
                $sleepProcess.StartInfo = $sleepInfo
                Assert-RunnerInvariant $sleepProcess.Start() "Job Object fixture process did not start."
                $jobType = "OstatniPomost.RunnerJob" -as [type]
                $jobType::Assign($jobHandle, $sleepProcess)
                Assert-RunnerInvariant ($jobType::Active($jobHandle) -ge 1) "Job Object did not retain its assigned process."
                [void](Complete-RunnerJob -JobHandle $jobHandle -Terminate $true)
                $jobClosed = $true
                Assert-RunnerInvariant $sleepProcess.WaitForExit(5000) "Kill-on-close Job Object did not terminate its process."
            }
            finally {
                if (-not $jobClosed -and $jobHandle -ne [IntPtr]::Zero) {
                    try { [void](Complete-RunnerJob -JobHandle $jobHandle -Terminate $true) } catch { Write-Warning $_.Exception.Message }
                }
                if ($null -ne $sleepProcess) { $sleepProcess.Dispose() }
            }
        }

        $sampleResults = @(
            (New-SyntheticTargetEvidence -Name "tests/a.gd" -Group "headless script" -Status "PASS" -ExitCode 0 -BlockingFailure $false -RunId "synthetic-a" -DigestCharacter 'a'),
            (New-SyntheticTargetEvidence -Name "tests/b.gd" -Group "headless script" -Status "SKIP" -ExitCode 0 -BlockingFailure $true -RunId "synthetic-b" -DigestCharacter 'b')
        )
        $sourceIdentity = $sourceSnapshotReceipt.SourceIdentity
        $runReceiptParameters = @{
            SourceHead = [string]$sourceIdentity.HeadCommit
            SourceTree = [string]$sourceIdentity.HeadTree
            SourceWorktreeClean = [bool]$sourceIdentity.WorktreeClean
            SourceStatusDigest = [string]$sourceIdentity.StatusDigest
            SourceSnapshotDigest = [string]$sourceSnapshotReceipt.SourceSnapshot.Digest
            TestOverlayDigest = [string]$overlayReceipt.Digest
            TestOverlayVersion = [string]$overlayReceipt.Version
            OverlayProjectBeforeSha256 = [string]$overlayReceipt.BeforeSha256
            OverlayProjectAfterSha256 = [string]$overlayReceipt.AfterSha256
            OverlayRunId = [string]$overlayReceipt.RunId
            OverlayUserDirectoryName = [string]$overlayReceipt.UserDirectoryName
            StructureOverlayVersion = "none"
            StructureOverlayDigest = "none"
            StructureOverlayId = ""
            StructureOverlayFileCount = 0
            StructureOverlayContentDigest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            StructureOverlayManifest = ""
            RunnerSha256 = "a" * 64
            GodotVersion = "4.7.1.stable.official"
            SuiteMode = "full"
            NativeSkipPolicy = "blocking"
            DebugServerPort = 21001
            DapPort = 21002
            LspPort = 21003
            Results = $sampleResults
        }
        $runReceiptA = New-GodotTestRunReceipt @runReceiptParameters
        $runReceiptB = New-GodotTestRunReceipt @runReceiptParameters
        Assert-RunnerInvariant ($runReceiptA.Digest -eq $runReceiptB.Digest) "Identical test evidence produced different run receipt digests."
        Assert-RunnerInvariant ($runReceiptA.Overall -eq "FAIL") "A blocking SKIP did not fail the run receipt."
        Assert-RunnerInvariant ($runReceiptA.TargetCount -eq 2) "Run receipt lost the closed target list."
        foreach ($requiredReceiptKey in @(
            "source_head=$($sourceIdentity.HeadCommit)",
            "source_tree=$($sourceIdentity.HeadTree)",
            "source_worktree_clean=0",
            "source_status_digest=$($sourceIdentity.StatusDigest)",
            "source_snapshot=$($sourceSnapshotReceipt.SourceSnapshot.Digest)",
            "test_overlay=$($overlayReceipt.Digest)",
            "overlay_version=godot-test-overlay-v1",
            "structure_overlay=none",
            "structure_overlay_version=none",
            "godot_service_port_scope=import-and-tests",
            "debug_server_port=21001",
            "dap_port=21002",
            "lsp_port=21003",
            "suite_mode=full",
            "native_skip_policy=blocking",
            "fail=0",
            "skip=1",
            "blocking=1",
            "overall=FAIL"
        )) {
            Assert-RunnerInvariant ($runReceiptA.CanonicalReceipt -match "(?m)^$([regex]::Escape($requiredReceiptKey))$") "Run receipt lost required key '$requiredReceiptKey'."
        }
        $explicitReceiptPath = Join-Path $fixtureRoot "receipt_output/run.receipt"
        $writtenReceiptPath = Write-GodotTestRunReceipt `
            -Receipt $runReceiptA `
            -WorkspaceRoot $workspaceRoot `
            -OutputPath $explicitReceiptPath
        Assert-RunnerInvariant ($writtenReceiptPath -eq [System.IO.Path]::GetFullPath($explicitReceiptPath)) "Run receipt writer changed the explicit output path."
        $expectedPersistedReceipt = "canonical_sha256=$($runReceiptA.Digest)`n$($runReceiptA.CanonicalReceipt)`n"
        Assert-RunnerInvariant ([System.IO.File]::ReadAllText($writtenReceiptPath) -ceq $expectedPersistedReceipt) "Persisted run receipt differs from its canonical envelope/content."
        $writtenReceiptPathAgain = Write-GodotTestRunReceipt `
            -Receipt $runReceiptA `
            -WorkspaceRoot $workspaceRoot `
            -OutputPath $explicitReceiptPath
        Assert-RunnerInvariant ($writtenReceiptPathAgain -eq $writtenReceiptPath) "Identical run receipt did not deduplicate at its output path."
        $parsedRunReceipt = Read-GodotTestRunReceipt -ReceiptPath $writtenReceiptPath
        Assert-RunnerInvariant ($parsedRunReceipt.Digest -eq $runReceiptA.Digest) "Run receipt verifier changed the canonical digest."

        $tamperedReceiptPath = Join-Path $fixtureRoot "receipt_output/tampered.receipt"
        $tamperedReceiptContent = [System.IO.File]::ReadAllText($writtenReceiptPath).Replace("overall=FAIL`n", "overall=PASS`n")
        Assert-RunnerInvariant ($tamperedReceiptContent -cne $expectedPersistedReceipt) "Run receipt tamper fixture did not change the canonical body."
        [System.IO.File]::WriteAllText($tamperedReceiptPath, $tamperedReceiptContent, [System.Text.UTF8Encoding]::new($false))
        $tamperedReceiptRejected = $false
        try {
            [void](Read-GodotTestRunReceipt -ReceiptPath $tamperedReceiptPath)
        }
        catch {
            $tamperedReceiptRejected = $_.Exception.Message.Contains("canonical SHA-256 is invalid")
        }
        Assert-RunnerInvariant $tamperedReceiptRejected "Run receipt verifier accepted a tampered canonical body."

        $emptyStatusDigest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        $passingResults = @((New-SyntheticTargetEvidence `
            -Name "tests/full_required.gd" -Group "headless script" -Status "PASS" `
            -ExitCode 0 -BlockingFailure $false -RunId "synthetic-full" -DigestCharacter 'a'))
        $passingParameters = @{}
        foreach ($key in $runReceiptParameters.Keys) {
            $passingParameters[$key] = $runReceiptParameters[$key]
        }
        $passingParameters.SourceWorktreeClean = $true
        $passingParameters.SourceStatusDigest = $emptyStatusDigest
        $passingParameters.Results = $passingResults
        $passingReceipt = New-GodotTestRunReceipt @passingParameters
        $candidateReceipt = [pscustomobject]@{
            schema_version = 1
            status = "PUBLICATION_READY"
            head = [string]$sourceIdentity.HeadCommit
            tree = [string]$sourceIdentity.HeadTree
        }
        $cleanIdentity = [pscustomobject]@{
            HeadCommit = [string]$sourceIdentity.HeadCommit
            HeadTree = [string]$sourceIdentity.HeadTree
            WorktreeClean = $true
            StatusDigest = $emptyStatusDigest
        }
        $boundReceipt = Assert-GodotTestRunReceiptBinding `
            -Receipt $passingReceipt `
            -CandidateReceipt $candidateReceipt `
            -CurrentIdentity $cleanIdentity `
            -CurrentSnapshot $sourceSnapshotReceipt.SourceSnapshot `
            -CurrentRunnerSha256 ("a" * 64) `
            -ExpectedTargets @("tests/full_required.gd")
        Assert-RunnerInvariant ($boundReceipt.Overall -eq "PASS") "Full-suite receipt binding rejected valid zero-failure evidence."

        foreach ($mismatch in @(
            [pscustomobject]@{ Name = "HEAD"; Head = ("b" * 40); Tree = [string]$sourceIdentity.HeadTree },
            [pscustomobject]@{ Name = "tree"; Head = [string]$sourceIdentity.HeadCommit; Tree = ("c" * 40) }
        )) {
            $mismatchedCandidateReceipt = [pscustomobject]@{
                schema_version = 1
                status = "PUBLICATION_READY"
                head = [string]$mismatch.Head
                tree = [string]$mismatch.Tree
            }
            $candidateMismatchRejected = $false
            try {
                [void](Assert-GodotTestRunReceiptBinding `
                    -Receipt $passingReceipt `
                    -CandidateReceipt $mismatchedCandidateReceipt `
                    -CurrentIdentity $cleanIdentity `
                    -CurrentSnapshot $sourceSnapshotReceipt.SourceSnapshot `
                    -CurrentRunnerSha256 ("a" * 64) `
                    -ExpectedTargets @("tests/full_required.gd"))
            }
            catch {
                $candidateMismatchRejected = $_.Exception.Message.Contains("HEAD/tree do not match")
            }
            Assert-RunnerInvariant $candidateMismatchRejected "Receipt binding accepted a candidate $($mismatch.Name) mismatch."
        }

        $targetParameters = @{}
        foreach ($key in $passingParameters.Keys) {
            $targetParameters[$key] = $passingParameters[$key]
        }
        $targetParameters.SuiteMode = "target"
        $targetReceipt = New-GodotTestRunReceipt @targetParameters
        $targetReceiptRejected = $false
        try {
            [void](Assert-GodotTestRunReceiptBinding `
                -Receipt $targetReceipt `
                -CandidateReceipt $candidateReceipt `
                -CurrentIdentity $cleanIdentity `
                -CurrentSnapshot $sourceSnapshotReceipt.SourceSnapshot `
                -CurrentRunnerSha256 ("a" * 64) `
                -ExpectedTargets @("tests/full_required.gd"))
        }
        catch {
            $targetReceiptRejected = $_.Exception.Message.Contains("required full-suite PASS")
        }
        Assert-RunnerInvariant $targetReceiptRejected "Receipt binding accepted a targeted run as a full-suite baseline."

        foreach ($negativeResultCase in @(
            [pscustomobject]@{
                Name = "FAIL"
                Result = (New-SyntheticTargetEvidence `
                    -Name "tests/full_required.gd" -Group "headless script" -Status "FAIL" `
                    -ExitCode 1 -BlockingFailure $true -RunId "synthetic-fail" -DigestCharacter 'a')
            },
            [pscustomobject]@{
                Name = "SKIP"
                Result = (New-SyntheticTargetEvidence `
                    -Name "tests/full_required.gd" -Group "headless script" -Status "SKIP" `
                    -ExitCode 0 -BlockingFailure $true -RunId "synthetic-skip" -DigestCharacter 'a')
            }
        )) {
            $negativeParameters = @{}
            foreach ($key in $passingParameters.Keys) {
                $negativeParameters[$key] = $passingParameters[$key]
            }
            $negativeParameters.Results = @($negativeResultCase.Result)
            $negativeReceipt = New-GodotTestRunReceipt @negativeParameters
            $negativeResultRejected = $false
            try {
                [void](Assert-GodotTestRunReceiptBinding `
                    -Receipt $negativeReceipt `
                    -CandidateReceipt $candidateReceipt `
                    -CurrentIdentity $cleanIdentity `
                    -CurrentSnapshot $sourceSnapshotReceipt.SourceSnapshot `
                    -CurrentRunnerSha256 ("a" * 64) `
                    -ExpectedTargets @("tests/full_required.gd"))
            }
            catch {
                $negativeResultRejected = $_.Exception.Message.Contains("required full-suite PASS")
            }
            Assert-RunnerInvariant $negativeResultRejected "Receipt binding accepted a full-suite $($negativeResultCase.Name) result."
        }

        $invalidBindingRejected = $false
        try {
            [void](Assert-GodotTestRunReceiptBinding `
                -Receipt $runReceiptA `
                -CandidateReceipt $candidateReceipt `
                -CurrentIdentity $cleanIdentity `
                -CurrentSnapshot $sourceSnapshotReceipt.SourceSnapshot `
                -CurrentRunnerSha256 ("a" * 64) `
                -ExpectedTargets @("tests/a.gd", "tests/b.gd"))
        }
        catch {
            $invalidBindingRejected = $true
        }
        Assert-RunnerInvariant $invalidBindingRejected "Receipt binding accepted dirty/failing evidence as a full-suite baseline."

        $syntheticTargetNames = @(
            "tests/headless_a.gd",
            "tests/headless_b.gd",
            "tests/headless_c.tscn",
            "tests/native_window.gd",
            "tests/native_snapshot.tscn"
        )
        $syntheticTargetGroups = @(
            "headless script",
            "headless script",
            "headless flow",
            "native window",
            "native snapshot"
        )
        $planParameters = @{
            SourceHead = "1" * 40
            SourceTree = "2" * 40
            SourceWorktreeClean = $true
            SourceStatusDigest = $emptyStatusDigest
            SourceSnapshotDigest = [string]$sourceSnapshotReceipt.SourceSnapshot.Digest
            RunnerSha256 = "3" * 64
            SuiteMode = "full-with-snapshots"
            HeadlessShardCount = 2
            NativeShardCount = 2
            TargetNames = $syntheticTargetNames
            TargetGroups = $syntheticTargetGroups
        }
        $shardPlanA = New-GodotTestShardPlan @planParameters
        $shardPlanB = New-GodotTestShardPlan @planParameters
        Assert-RunnerInvariant ($shardPlanA.Digest -eq $shardPlanB.Digest) "Identical full manifests produced different shard plans."
        Assert-RunnerInvariant ($shardPlanA.Algorithm -eq "lane-round-robin-v1") "Shard plan lost its canonical scheduling algorithm."
        Assert-RunnerInvariant ($shardPlanA.ShardCount -eq 4 -and @($shardPlanA.Shards | Where-Object TargetCount -lt 1).Count -eq 0) "Shard plan created a missing or empty lane."
        $expectedAssignments = @(
            "0:headless-0:0",
            "1:headless-1:0",
            "2:headless-0:1",
            "3:native-0:0",
            "4:native-1:0"
        )
        $actualAssignments = @($shardPlanA.Targets | ForEach-Object { "$($_.TargetIndex):$($_.ShardId):$($_.LocalIndex)" })
        Assert-RunnerInvariant ([string]::Join("`n", $actualAssignments) -ceq [string]::Join("`n", $expectedAssignments)) "Lane round-robin assignment is not deterministic."
        $emptyShardRejected = $false
        try {
            $emptyShardParameters = @{}
            foreach ($key in $planParameters.Keys) { $emptyShardParameters[$key] = $planParameters[$key] }
            $emptyShardParameters.HeadlessShardCount = 4
            [void](New-GodotTestShardPlan @emptyShardParameters)
        }
        catch { $emptyShardRejected = $true }
        Assert-RunnerInvariant $emptyShardRejected "Shard plan accepted a shard count that creates an empty lane."

        $shardEvidenceRoot = Join-Path $fixtureRoot "shard evidence"
        $planPath = Join-Path $shardEvidenceRoot "plan.receipt"
        [void](Write-GodotTestRunReceipt -Receipt $shardPlanA -WorkspaceRoot $workspaceRoot -OutputPath $planPath)
        $parsedPlan = Read-GodotTestShardPlan -PlanPath $planPath
        Assert-RunnerInvariant ($parsedPlan.Digest -eq $shardPlanA.Digest) "Shard plan round-trip changed its digest."
        $planAsCandidateRejected = $false
        try { [void](Read-GodotCandidateRunEvidence -ReceiptPath $planPath) } catch { $planAsCandidateRejected = $true }
        Assert-RunnerInvariant $planAsCandidateRejected "Candidate verifier accepted a plan as completed run evidence."

        $tamperedPlanPath = Join-Path $shardEvidenceRoot "tampered-plan.receipt"
        $tamperedPlanContent = [System.IO.File]::ReadAllText($planPath).Replace("algorithm=lane-round-robin-v1", "algorithm=lane-round-robin-v2")
        [System.IO.File]::WriteAllText($tamperedPlanPath, $tamperedPlanContent, [System.Text.UTF8Encoding]::new($false))
        $tamperedPlanRejected = $false
        try { [void](Read-GodotTestShardPlan -PlanPath $tamperedPlanPath) } catch { $tamperedPlanRejected = $true }
        Assert-RunnerInvariant $tamperedPlanRejected "Shard plan reader accepted a tampered canonical body."

        $reassignedPlanBody = $shardPlanA.CanonicalReceipt.Replace(
            "|$(ConvertTo-TestRunReceiptField -Value 'headless-0')|1",
            "|$(ConvertTo-TestRunReceiptField -Value 'headless-1')|1"
        )
        Assert-RunnerInvariant ($reassignedPlanBody -cne $shardPlanA.CanonicalReceipt) "Shard reassignment fixture did not change the plan."
        $reassignedPlanPath = Join-Path $shardEvidenceRoot "reassigned-plan.receipt"
        $reassignedPlanEnvelope = "canonical_sha256=$(Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $reassignedPlanBody)`n$reassignedPlanBody`n"
        [System.IO.File]::WriteAllText($reassignedPlanPath, $reassignedPlanEnvelope, [System.Text.UTF8Encoding]::new($false))
        $reassignedPlanRejected = $false
        try { [void](Read-GodotTestShardPlan -PlanPath $reassignedPlanPath) } catch { $reassignedPlanRejected = $true }
        Assert-RunnerInvariant $reassignedPlanRejected "Shard plan reader accepted a re-signed target reassignment."

        $syntheticCleanIdentity = [pscustomobject]@{
            HeadCommit = $shardPlanA.SourceHead
            HeadTree = $shardPlanA.SourceTree
            WorktreeClean = $true
            StatusDigest = $shardPlanA.SourceStatusDigest
        }
        $syntheticCleanSnapshot = [pscustomobject]@{
            Digest = $shardPlanA.SourceSnapshotDigest
            Entries = @([pscustomobject]@{
                RelativePath = "project.godot"
                Exists = $true
                Sha256 = [string]$overlayReceipt.BeforeSha256
            })
        }
        [void](Assert-GodotTestShardPlanSourceBinding `
            -Plan $shardPlanA `
            -CurrentIdentity $syntheticCleanIdentity `
            -CurrentSnapshot $syntheticCleanSnapshot `
            -CurrentRunnerSha256 $shardPlanA.RunnerSha256)
        $movedPlanSourceRejected = $false
        try {
            [void](Assert-GodotTestShardPlanSourceBinding `
                -Plan $shardPlanA `
                -CurrentIdentity $syntheticCleanIdentity `
                -CurrentSnapshot ([pscustomobject]@{ Digest = "4" * 64; Entries = @() }) `
                -CurrentRunnerSha256 $shardPlanA.RunnerSha256)
        }
        catch { $movedPlanSourceRejected = $true }
        Assert-RunnerInvariant $movedPlanSourceRejected "Shard plan source binding accepted a different snapshot."

        function New-SyntheticShardReceipt {
            param(
                [pscustomobject]$Plan,
                [pscustomobject]$PlannedShard,
                [string]$FirstStatus = "PASS"
            )

            $plannedTargets = @($Plan.Targets | Where-Object ShardId -ceq $PlannedShard.Id | Sort-Object LocalIndex)
            $syntheticResults = [System.Collections.Generic.List[object]]::new()
            foreach ($plannedTarget in $plannedTargets) {
                $status = if ($plannedTarget.LocalIndex -eq 0) { $FirstStatus } else { "PASS" }
                $syntheticTargetRunId = "synthetic-$($PlannedShard.Id)-$($plannedTarget.LocalIndex)"
                $result = New-SyntheticTargetEvidence `
                    -Name ([string]$plannedTarget.Name) `
                    -Group ([string]$plannedTarget.Group) `
                    -Status $status `
                    -ExitCode $(if ($status -eq "FAIL") { 1 } else { 0 }) `
                    -BlockingFailure ($status -ne "PASS") `
                    -RunId $syntheticTargetRunId `
                    -DigestCharacter 'a'
                $result | Add-Member -NotePropertyName TargetIndex -NotePropertyValue ([int]$plannedTarget.TargetIndex)
                $result | Add-Member -NotePropertyName LocalIndex -NotePropertyValue ([int]$plannedTarget.LocalIndex)
                $result | Add-Member -NotePropertyName NativeWindow -NotePropertyValue ([bool]$plannedTarget.NativeWindow)
                $syntheticResults.Add($result)
            }
            $syntheticRunId = "synthetic-$($PlannedShard.Id)"
            $syntheticUserDirectory = "synthetic-user-$($PlannedShard.Id)"
            $syntheticOverlayCanonical = @(
                "version=godot-test-overlay-v1",
                "source_snapshot=$($Plan.SourceSnapshotDigest)",
                "path=project.godot",
                "before=$($overlayReceipt.BeforeSha256)",
                "after=$($overlayReceipt.AfterSha256)",
                "run_id=$syntheticRunId",
                "user_directory=$syntheticUserDirectory"
            ) -join "`n"
            return New-GodotTestShardReceipt `
                -PlanDigest $Plan.Digest `
                -ShardId $PlannedShard.Id `
                -ShardLane $PlannedShard.Lane `
                -SourceHead $Plan.SourceHead `
                -SourceTree $Plan.SourceTree `
                -SourceWorktreeClean $true `
                -SourceStatusDigest $Plan.SourceStatusDigest `
                -SourceSnapshotDigest $Plan.SourceSnapshotDigest `
                -TestOverlayDigest (Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $syntheticOverlayCanonical) `
                -TestOverlayVersion "godot-test-overlay-v1" `
                -OverlayProjectBeforeSha256 $overlayReceipt.BeforeSha256 `
                -OverlayProjectAfterSha256 $overlayReceipt.AfterSha256 `
                -OverlayRunId $syntheticRunId `
                -OverlayUserDirectoryName $syntheticUserDirectory `
                -RunnerSha256 $Plan.RunnerSha256 `
                -GodotVersion "4.7.1.stable.official" `
                -DebugServerPort 22001 `
                -DapPort 22002 `
                -LspPort 22003 `
                -Results @($syntheticResults)
        }

        $correctShardReceipts = @($shardPlanA.Shards | ForEach-Object {
            New-SyntheticShardReceipt -Plan $shardPlanA -PlannedShard $_
        })
        $firstShardPath = Join-Path $shardEvidenceRoot "first-shard.receipt"
        [void](Write-GodotTestRunReceipt -Receipt $correctShardReceipts[0] -WorkspaceRoot $workspaceRoot -OutputPath $firstShardPath)
        $parsedFirstShard = Read-GodotTestShardReceipt -ReceiptPath $firstShardPath
        Assert-RunnerInvariant ($parsedFirstShard.Digest -eq $correctShardReceipts[0].Digest) "Shard receipt round-trip changed its digest."
        $individualShardRejected = $false
        try { [void](Read-GodotCandidateRunEvidence -ReceiptPath $firstShardPath) } catch {
            $individualShardRejected = $_.Exception.Message.Contains("individual shard receipt cannot certify")
        }
        Assert-RunnerInvariant $individualShardRejected "Candidate verifier accepted an individual shard receipt."

        $aggregateReceipt = Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $correctShardReceipts
        Assert-RunnerInvariant ($aggregateReceipt.TargetCount -eq $shardPlanA.TargetCount -and $aggregateReceipt.PassCount -eq $shardPlanA.TargetCount) "Aggregate receipt lost the exact target union."
        Assert-RunnerInvariant ([string]::Join("`n", @($aggregateReceipt.Results | ForEach-Object Name)) -ceq [string]::Join("`n", $syntheticTargetNames)) "Aggregate receipt changed global target order."
        $aggregatePath = Join-Path $shardEvidenceRoot "aggregate.receipt"
        [void](Write-GodotTestRunReceipt -Receipt $aggregateReceipt -WorkspaceRoot $workspaceRoot -OutputPath $aggregatePath)
        $parsedAggregate = Read-GodotTestAggregateReceipt -ReceiptPath $aggregatePath
        Assert-RunnerInvariant ($parsedAggregate.Digest -eq $aggregateReceipt.Digest) "Aggregate receipt round-trip changed its digest."
        $aggregateCandidateEvidence = Read-GodotCandidateRunEvidence -ReceiptPath $aggregatePath
        Assert-RunnerInvariant ($aggregateCandidateEvidence.Digest -eq $aggregateReceipt.Digest) "Candidate verifier did not dispatch aggregate evidence."
        $candidateAggregate = [pscustomobject]@{
            schema_version = 1
            status = "PUBLICATION_READY"
            head = $shardPlanA.SourceHead
            tree = $shardPlanA.SourceTree
        }
        [void](Assert-GodotTestAggregateReceiptBinding `
            -Receipt $parsedAggregate `
            -CandidateReceipt $candidateAggregate `
            -CurrentIdentity $syntheticCleanIdentity `
            -CurrentSnapshot $syntheticCleanSnapshot `
            -CurrentRunnerSha256 $shardPlanA.RunnerSha256 `
            -ExpectedTargets $syntheticTargetNames)

        foreach ($invalidShardSet in @(
            [pscustomobject]@{ Name = "missing shard"; Receipts = @($correctShardReceipts[0..2]) },
            [pscustomobject]@{ Name = "duplicate shard"; Receipts = @($correctShardReceipts[0], $correctShardReceipts[0], $correctShardReceipts[2], $correctShardReceipts[3]) },
            [pscustomobject]@{ Name = "extra shard"; Receipts = @($correctShardReceipts) + @($correctShardReceipts[0]) }
        )) {
            $invalidShardSetRejected = $false
            try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $invalidShardSet.Receipts) } catch { $invalidShardSetRejected = $true }
            Assert-RunnerInvariant $invalidShardSetRejected "Aggregate accepted $($invalidShardSet.Name)."
        }

        $mutableReceipt = $correctShardReceipts[0]
        $originalResults = @($mutableReceipt.Results)
        $originalTargetCount = [int]$mutableReceipt.TargetCount
        try {
            $mutableReceipt.Results = @($originalResults[0])
            $mutableReceipt.TargetCount = 1
            $missingTargetRejected = $false
            try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $correctShardReceipts) } catch { $missingTargetRejected = $true }
            Assert-RunnerInvariant $missingTargetRejected "Aggregate accepted a missing target."

            $mutableReceipt.Results = @($originalResults) + @($originalResults[0])
            $mutableReceipt.TargetCount = $originalTargetCount + 1
            $extraTargetRejected = $false
            try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $correctShardReceipts) } catch { $extraTargetRejected = $true }
            Assert-RunnerInvariant $extraTargetRejected "Aggregate accepted an extra target."

            $duplicateResults = @($originalResults)
            $duplicateResults[1] = $originalResults[0]
            $mutableReceipt.Results = $duplicateResults
            $mutableReceipt.TargetCount = $originalTargetCount
            $duplicateTargetRejected = $false
            try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $correctShardReceipts) } catch { $duplicateTargetRejected = $true }
            Assert-RunnerInvariant $duplicateTargetRejected "Aggregate accepted a duplicated/reassigned target."

            $mutableReceipt.Results = @($originalResults[1], $originalResults[0])
            $wrongOrderRejected = $false
            try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $correctShardReceipts) } catch { $wrongOrderRejected = $true }
            Assert-RunnerInvariant $wrongOrderRejected "Aggregate accepted wrong local target order."
        }
        finally {
            $mutableReceipt.Results = $originalResults
            $mutableReceipt.TargetCount = $originalTargetCount
        }

        foreach ($mismatchProperty in @("SourceHead", "SourceSnapshotDigest", "RunnerSha256", "GodotVersion", "OverlayProjectBeforeSha256")) {
            $mismatchReceipt = $correctShardReceipts[1]
            $originalMismatchValue = $mismatchReceipt.$mismatchProperty
            try {
                $mismatchReceipt.$mismatchProperty = if ($mismatchProperty -eq "GodotVersion") {
                    "4.7.2.stable.official"
                }
                elseif ($mismatchProperty -eq "SourceHead") {
                    "9" * 40
                }
                else {
                    "f" * 64
                }
                $mismatchRejected = $false
                try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $correctShardReceipts) } catch { $mismatchRejected = $true }
                Assert-RunnerInvariant $mismatchRejected "Aggregate accepted shard $mismatchProperty mismatch."
            }
            finally { $mismatchReceipt.$mismatchProperty = $originalMismatchValue }
        }

        $failedShard = New-SyntheticShardReceipt -Plan $shardPlanA -PlannedShard $shardPlanA.Shards[0] -FirstStatus "FAIL"
        $failedSet = @($correctShardReceipts)
        $failedSet[0] = $failedShard
        $failedShardRejected = $false
        try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $failedSet) } catch { $failedShardRejected = $true }
        Assert-RunnerInvariant $failedShardRejected "Aggregate accepted a failed shard target."

        $nativeShardIndex = @($shardPlanA.Shards | ForEach-Object Id).IndexOf("native-0")
        $skippedNativeShard = New-SyntheticShardReceipt -Plan $shardPlanA -PlannedShard $shardPlanA.Shards[$nativeShardIndex] -FirstStatus "SKIP"
        $skippedSet = @($correctShardReceipts)
        $skippedSet[$nativeShardIndex] = $skippedNativeShard
        $skippedShardRejected = $false
        try { [void](Merge-GodotTestShardReceipts -Plan $shardPlanA -ShardReceipts $skippedSet) } catch { $skippedShardRejected = $true }
        Assert-RunnerInvariant $skippedShardRejected "Aggregate accepted a required native SKIP."

        $failedImportBody = $correctShardReceipts[0].CanonicalReceipt.Replace("import=PASS", "import=FAIL")
        $failedImportPath = Join-Path $shardEvidenceRoot "failed-import.receipt"
        $failedImportEnvelope = "canonical_sha256=$(Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $failedImportBody)`n$failedImportBody`n"
        [System.IO.File]::WriteAllText($failedImportPath, $failedImportEnvelope, [System.Text.UTF8Encoding]::new($false))
        $failedImportRejected = $false
        try { [void](Read-GodotTestShardReceipt -ReceiptPath $failedImportPath) } catch { $failedImportRejected = $true }
        Assert-RunnerInvariant $failedImportRejected "Shard reader accepted a re-signed failed import."

        Assert-RunnerInvariant ($parsedRunReceipt.Version -eq "godot-test-run-receipt-v2") "Run receipt did not publish the per-target isolation schema."
        $candidateRunEvidence = Read-GodotCandidateRunEvidence -ReceiptPath $writtenReceiptPath
        Assert-RunnerInvariant ($candidateRunEvidence.Digest -eq $runReceiptA.Digest) "Candidate verifier rejected canonical v2 target evidence."

        [void](New-Item -ItemType Directory -Path $contextA.UserDirectoryPath -Force)
        [System.IO.File]::WriteAllText((Join-Path $contextA.UserDirectoryPath "marker_a.txt"), $contextA.RunId, [System.Text.UTF8Encoding]::new($false))
        Complete-IsolatedTestUserDirectory -RunContext $contextA -Preserve $true
        Assert-RunnerInvariant (Test-Path -LiteralPath $contextA.UserDirectoryPath -PathType Container) "Failed-run/kept user:// was not preserved."
        Complete-IsolatedTestUserDirectory -RunContext $contextA -Preserve $false
        Assert-RunnerInvariant (-not (Test-Path -LiteralPath $contextA.UserDirectoryPath)) "Successful-run user:// was not removed."

        [void](New-Item -ItemType Directory -Path $contextB.UserDirectoryPath -Force)
        [System.IO.File]::WriteAllText((Join-Path $contextB.UserDirectoryPath "marker_b.txt"), $contextB.RunId, [System.Text.UTF8Encoding]::new($false))
        $oldRunId = "run_20000101_000000_000_999_" + [Guid]::NewGuid().ToString("N")
        $oldRetainedPath = Join-Path $contextB.UserDirectoryRoot $oldRunId
        [void](New-Item -ItemType Directory -Path $oldRetainedPath -Force)
        (Get-Item -LiteralPath $oldRetainedPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-10)
        Invoke-IsolatedTestUserDirectoryRetention `
            -UserDirectoryRoot $contextB.UserDirectoryRoot `
            -ExcludedRunId $contextB.RunId `
            -MaxPreservedRuns 12 `
            -MaxAgeDays 7
        Assert-RunnerInvariant (-not (Test-Path -LiteralPath $oldRetainedPath)) "Retention did not remove an expired test user://."
        Assert-RunnerInvariant (Test-Path -LiteralPath $contextB.UserDirectoryPath -PathType Container) "Retention removed the active test user://."
    }
    finally {
        if ($null -ne $contextB) {
            try { Complete-IsolatedTestUserDirectory -RunContext $contextB -Preserve $false } catch { Write-Warning $_.Exception.Message }
        }
        if ($null -ne $contextA) {
            try { Complete-IsolatedTestUserDirectory -RunContext $contextA -Preserve $false } catch { Write-Warning $_.Exception.Message }
        }
        if ($null -ne $oldRetainedPath -and (Test-Path -LiteralPath $oldRetainedPath)) {
            Remove-Item -LiteralPath $oldRetainedPath -Recurse -Force
        }
        foreach ($targetFixture in @($targetFixtureA, $targetFixtureB)) {
            if ($null -ne $targetFixture -and (Test-Path -LiteralPath $targetFixture)) {
                Remove-IsolatedTestWorkspace -WorkspacePath $targetFixture -WorkspaceRoot $workspaceRoot
            }
        }
        Release-IsolatedTestRunContext -RunContext $contextB
        Release-IsolatedTestRunContext -RunContext $contextA
        Remove-IsolatedTestWorkspace -WorkspacePath $workspacePath -WorkspaceRoot $workspaceRoot
    }

    Write-Host "runner_isolation_test PASS: fresh per-target materialization, trusted process/output/completion boundaries, canonical v2 receipts and fail-closed aggregation are valid."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
