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
    -Condition ($runnerText.Contains('-RunContext $runContext') -and
        $runnerText.Contains('"--debug-server", $RunContext.DebugServerUri') -and
        $runnerText.Contains('godot_service_port_scope=import-and-tests')) `
    -Message "The same leased Godot service ports must protect import and every test process."
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
        $runnerText.Contains('"eol-check"')) `
    -Message "Runner must reject tracked CRLF/mixed bytes before closing the source snapshot."

$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]"\/")
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $tempParent ("ostatni_pomost_runner_test_" + [Guid]::NewGuid().ToString("N"))))
$requiredPrefix = $tempParent + [System.IO.Path]::DirectorySeparatorChar
if (-not $fixtureRoot.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create runner fixture outside the system temp directory: '$fixtureRoot'."
}

try {
    $sourceRoot = Join-Path $fixtureRoot "source checkout with spaces"
    $workspaceRoot = Join-Path $fixtureRoot "isolated workspaces"
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

        $sampleResults = @(
            [pscustomobject]@{
                Name = "tests/a.gd"
                Group = "headless script"
                Status = "PASS"
                ExitCode = 0
                BlockingFailure = $false
            },
            [pscustomobject]@{
                Name = "tests/b.gd"
                Group = "headless script"
                Status = "SKIP"
                ExitCode = 0
                BlockingFailure = $true
            }
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
        $passingResults = @([pscustomobject]@{
            Name = "tests/full_required.gd"
            Group = "headless script"
            Status = "PASS"
            ExitCode = 0
            BlockingFailure = $false
        })
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
                Result = [pscustomobject]@{
                    Name = "tests/full_required.gd"
                    Group = "headless script"
                    Status = "FAIL"
                    ExitCode = 1
                    BlockingFailure = $true
                }
            },
            [pscustomobject]@{
                Name = "SKIP"
                Result = [pscustomobject]@{
                    Name = "tests/full_required.gd"
                    Group = "headless script"
                    Status = "SKIP"
                    ExitCode = 0
                    BlockingFailure = $true
                }
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
        Release-IsolatedTestRunContext -RunContext $contextB
        Release-IsolatedTestRunContext -RunContext $contextA
        Remove-IsolatedTestWorkspace -WorkspacePath $workspacePath -WorkspaceRoot $workspaceRoot
    }

    Write-Host "runner_isolation_test PASS: explicit target routing, Git-closed dirty snapshot, fingerprint/CAS copy and per-run Godot isolation are valid."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
