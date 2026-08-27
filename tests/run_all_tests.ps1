#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias("GodotPath")]
    [string]$GodotConsolePath,

    [switch]$Full,

    [switch]$IncludeSnapshots,

    [string]$SourceRepositoryPath,

    [string]$Target,

    [string]$NativeTarget,

    [string[]]$TargetUserArgument = @(),

    [string]$TargetUserArgumentsJson,

    [string]$TargetUserArgumentsBase64,

    [string]$NativeMovieOutputPath,

    [ValidateRange(1, 240)]
    [int]$NativeMovieFps = 30,

    [switch]$KeepWorkspace,

    [string]$RunReceiptOutputPath,

    [string]$VerifyRunReceipt,

    [string]$CandidateReceipt,

    [string]$WriteShardPlan,

    [ValidateRange(1, 64)]
    [int]$HeadlessShardCount = 1,

    [ValidateRange(1, 64)]
    [int]$NativeShardCount = 1,

    [string]$ShardPlan,

    [string]$ShardId,

    [string[]]$AggregateShardReceipt = @(),

    [switch]$InPlace,

    [ValidateRange(1, 3600)]
    [int]$ImportTimeoutSeconds = 600,

    [ValidateRange(1, 3600)]
    [int]$TestTimeoutSeconds = 120,

    # The native window test is part of the default required suite. This switch
    # is intended only for explicitly unsupported environments (for example CI
    # workers without a real desktop session).
    [switch]$AllowNativeSkip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$testTimeoutWasExplicit = $PSBoundParameters.ContainsKey("TestTimeoutSeconds")
$testSpecificDefaultTimeoutSeconds = @{
    "campaign_format_test.gd" = 300
    "tests/campaign_format_test.gd" = 300
}

# PowerShell 7 can otherwise promote native stderr to PowerShell errors. Godot's
# stdout and stderr are inspected together below, using the engine's own error
# prefixes and the process exit code as the test contract.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$runnerControlRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$isolatedPythonEntryPath = Join-Path $runnerControlRoot "tools/ci_python_entry.py"
$controlContractToolPath = Join-Path $runnerControlRoot "tools/workbench_contract.py"
$controlLockToolPath = Join-Path $runnerControlRoot "tools/workbench_lock.py"
$sourceProjectRoot = if ([string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
    [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
else {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($SourceRepositoryPath))
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceProjectRoot "project.godot") -PathType Leaf)) {
    throw "Source repository is not a Godot project: '$sourceProjectRoot'."
}
$projectRoot = $sourceProjectRoot
$ansiEscapePattern = "(?:\x1B\[[0-?]*[ -/]*[@-~])|(?:\x1B\][^\x07]*(?:\x07|\x1B\\))"
$runnerSourceSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()

function Get-StructurePackageTestTargets {
    param(
        [string]$ProjectRoot,
        [switch]$ContractOnly
    )

    $workbenchRoot = Join-Path $ProjectRoot "underwater_map_workbench"
    $structuresRoot = Join-Path $workbenchRoot "structures"
    if (-not (Test-Path -LiteralPath $structuresRoot -PathType Container)) {
        return @()
    }

    $manifestPath = Join-Path $workbenchRoot "map_manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Map manifest is required for structure test discovery: '$manifestPath'."
    }
    try {
        $mapManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Map manifest is not valid JSON for structure test discovery: $($_.Exception.Message)"
    }
    $structuresProperty = $mapManifest.PSObject.Properties['structures']
    $instancesProperty = if ($null -ne $structuresProperty) {
        $structuresProperty.Value.PSObject.Properties['instances']
    }
    else {
        $null
    }
    if ($null -eq $instancesProperty) {
        throw "Map manifest must publish structures.instances for structure test discovery."
    }

    $registeredPackages = @{}
    foreach ($record in @($instancesProperty.Value)) {
        $packageId = [string]$record.id
        if ($packageId -notmatch '^[a-z][a-z0-9_]*$' -or $registeredPackages.ContainsKey($packageId)) {
            throw "Registered structure package id must be unique lowercase snake_case: '$packageId'."
        }
        $expectedPackagePath = "structures/$packageId/structure_manifest.json"
        if ([string]$record.package.path -ne $expectedPackagePath) {
            throw "Registered structure package '$packageId' must use path '$expectedPackagePath'."
        }
        $registeredPackages[$packageId] = $record
    }

    $packageDirectories = @{}
    foreach ($packageDirectory in @(Get-ChildItem -LiteralPath $structuresRoot -Directory | Sort-Object Name)) {
        if ($packageDirectory.Name -notmatch '^[a-z][a-z0-9_]*$') {
            throw "Structure package directory must use lowercase snake_case: '$($packageDirectory.Name)'."
        }
        if (-not $registeredPackages.ContainsKey($packageDirectory.Name)) {
            throw "Structure package directory is not registered in map_manifest.json: '$($packageDirectory.Name)'."
        }
        $packageDirectories[$packageDirectory.Name] = $packageDirectory
    }

    $filePattern = if ($ContractOnly) { "*_package_contract_test.gd" } else { "*_test.gd" }
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($packageId in @($registeredPackages.Keys | Sort-Object)) {
        if (-not $packageDirectories.ContainsKey($packageId)) {
            throw "Registered structure package directory does not exist: '$packageId'."
        }
        $packageDirectory = $packageDirectories[$packageId]
        $testsDirectory = Join-Path $packageDirectory.FullName "tests"
        if (-not (Test-Path -LiteralPath $testsDirectory -PathType Container)) {
            throw "Registered structure package '$packageId' must contain a tests directory."
        }
        $contractTests = @(Get-ChildItem -LiteralPath $testsDirectory -File -Filter "*_package_contract_test.gd")
        $runtimeTests = @(Get-ChildItem -LiteralPath $testsDirectory -File -Filter "*_runtime_test.gd")
        if ($contractTests.Count -ne 1 -or $runtimeTests.Count -ne 1) {
            throw "Registered structure package '$packageId' must contain exactly one package contract test and one runtime test."
        }
        foreach ($testFile in @(Get-ChildItem -LiteralPath $testsDirectory -File -Filter $filePattern | Sort-Object Name)) {
            $targets.Add("underwater_map_workbench/structures/$packageId/tests/$($testFile.Name)")
        }
    }
    return @($targets)
}

function Get-RunnerTestSelection {
    param(
        [AllowNull()][string]$ResolvedTarget,
        [string]$ProjectRoot,
        [bool]$FullSuite,
        [bool]$IncludeSnapshotScenes,
        [string[]]$DefaultHeadlessScriptTests,
        [string[]]$DefaultHeadlessFlowScenes,
        [string[]]$SnapshotScenes
    )

    # An explicit target is an intentionally closed runner request. In
    # particular, it must not inspect Map package registration or reject a
    # target owned by Root/Diver because an unrelated structure is in flight.
    if (-not [string]::IsNullOrWhiteSpace($ResolvedTarget)) {
        return [pscustomobject]@{
            HeadlessScriptTests = @()
            ManifestTargets = @($ResolvedTarget)
        }
    }

    $structurePackageTests = if ($FullSuite) {
        @(Get-StructurePackageTestTargets -ProjectRoot $ProjectRoot)
    }
    else {
        @(Get-StructurePackageTestTargets -ProjectRoot $ProjectRoot -ContractOnly)
    }
    $headlessScriptTests = @($DefaultHeadlessScriptTests) + @($structurePackageTests)
    $manifestTargets = @($headlessScriptTests) +
        $(if ($FullSuite) { @("native_window_settings_test.gd") } else { @() }) +
        @($DefaultHeadlessFlowScenes) +
        $(if ($IncludeSnapshotScenes) { @($SnapshotScenes) } else { @() })

    return [pscustomobject]@{
        HeadlessScriptTests = @($headlessScriptTests)
        ManifestTargets = @($manifestTargets)
    }
}

function Assert-RunnerInvocationMode {
    param([bool]$InPlaceRequested)

    if ($InPlaceRequested) {
        throw (
            "-InPlace is disabled because it cannot provide an isolated Godot user:// " +
            "without mutating source project.godot. Use the default immutable isolated " +
            "workspace runner; each invocation receives its own cache, user data and ports."
        )
    }
}

function Assert-TrackedLfEol {
    param([string]$ProjectRoot)

    $contractTool = $controlContractToolPath
    if (-not (Test-Path -LiteralPath $contractTool -PathType Leaf)) {
        throw "Tracked EOL verifier is missing: '$contractTool'."
    }
    $pythonCommand = Get-Command -Name "python" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $pythonCommand) {
        throw "Python is required for the tracked EOL preflight."
    }

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pythonCommand.Source
        $arguments = @(
            "-I", "-B", $isolatedPythonEntryPath,
            "--preload", "workbench_lock=$controlLockToolPath",
            "--script", $contractTool, "--",
            "--repo", $ProjectRoot,
            "eol-check"
        )
        $startInfo.Arguments = (@($arguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $ProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Tracked EOL preflight process could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            try { $process.Kill($true) } catch { $process.Kill() }
            $process.WaitForExit()
            throw "Tracked EOL preflight timed out after 60 seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult().Trim()
        $standardError = $standardErrorTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            throw "Tracked EOL preflight failed: $standardOutput $standardError"
        }
        if (-not [string]::IsNullOrWhiteSpace($standardOutput)) {
            Write-Verbose $standardOutput
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function ConvertTo-NormalizedProjectPath {
    param(
        [string]$Candidate,
        [string]$RelativeBase
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Candidate.Trim())
        $absolute = if ([System.IO.Path]::IsPathRooted($expanded)) {
            [System.IO.Path]::GetFullPath($expanded)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $RelativeBase $expanded))
        }
        return $absolute.TrimEnd([char[]]"\\/")
    }
    catch {
        return $null
    }
}

function Assert-ProjectGodotCacheAvailable {
    param([string]$ProjectRoot)

    if ($env:OS -ne "Windows_NT") {
        return
    }

    $normalizedProjectRoot = ConvertTo-NormalizedProjectPath -Candidate $ProjectRoot -RelativeBase $ProjectRoot
    $godotProcesses = $null
    try {
        $godotProcesses = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -match "(?i)^godot.*\.exe$" })
    }
    catch {
        $unscopedGodotProcesses = @(Get-Process -Name "Godot*" -ErrorAction SilentlyContinue)
        if ($unscopedGodotProcesses.Count -gt 0) {
            $processIds = @($unscopedGodotProcesses | ForEach-Object { $_.Id }) -join ", "
            throw "Godot process inspection failed while Godot is running (PID: $processIds). Close Godot before using this project, or run tests in a separate full project copy with its own .godot cache."
        }
        return
    }

    $pathPattern = '(?i)(?:^|\s)--path(?:=|\s+)(?:"(?<double>[^"]+)"|''(?<single>[^'']+)''|(?<bare>\S+))'
    $collisions = [System.Collections.Generic.List[object]]::new()
    foreach ($godotProcess in $godotProcesses) {
        $commandLine = [string]$godotProcess.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            continue
        }

        $pathMatch = [System.Text.RegularExpressions.Regex]::Match($commandLine, $pathPattern)
        if (-not $pathMatch.Success) {
            continue
        }

        $candidatePath = foreach ($groupName in @("double", "single", "bare")) {
            if ($pathMatch.Groups[$groupName].Success) {
                $pathMatch.Groups[$groupName].Value
                break
            }
        }
        $expandedCandidatePath = [Environment]::ExpandEnvironmentVariables(
            ([string]$candidatePath).Trim()
        )
        # Win32_Process exposes a command line but not the process working
        # directory. Resolving somebody else's relative `--path .` against
        # our workspace would fabricate a collision. Official runner-created
        # Godot processes always receive a canonical absolute --path, so only
        # absolute paths are comparable here.
        if (-not [System.IO.Path]::IsPathRooted($expandedCandidatePath)) {
            continue
        }
        $normalizedCandidatePath = ConvertTo-NormalizedProjectPath `
            -Candidate $expandedCandidatePath `
            -RelativeBase $ProjectRoot
        if ($null -eq $normalizedCandidatePath -or
            -not [string]::Equals($normalizedCandidatePath, $normalizedProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $collisions.Add([pscustomobject]@{
            Id = [int]$godotProcess.ProcessId
            Mode = if ($commandLine -match "(?i)(?:^|\s)--editor(?:\s|$)") { "editor" } else { "runtime/test" }
        })
    }

    if ($collisions.Count -eq 0) {
        return
    }

    $details = @($collisions | Sort-Object Id | ForEach-Object {
        "PID $($_.Id) [$($_.Mode)]"
    }) -join ", "
    throw "This project is already open in Godot: $details. Close these processes before running tests, or use a separate full project copy with its own .godot cache."
}

$quickHeadlessScriptTests = @(
    "campaign_map_contract_test.gd"
    "workbench_boundary_test.gd"
    "structure_world_link_test.gd"
    "campaign_story_system_test.gd"
    "competency_system_test.gd"
    "expedition_preparation_selection_test.gd"
    "interactable_visual_style_test.gd"
    "narrative_content_test.gd"
    "profession_talent_system_test.gd"
    "production_system_test.gd"
    "roster_rotation_skeleton_test.gd"
    "campaign_format_test.gd"
    "smoke_test.gd"
    "tutorial_flow_test.gd"
)

$fullHeadlessScriptTests = @(
    "base_environment_test.gd"
    "building_system_test.gd"
    "campaign_map_contract_test.gd"
    "workbench_boundary_test.gd"
    "underwater_map_workbench/tests/underwater_map_smoke_test.gd"
    "structure_world_link_test.gd"
    "campaign_story_system_test.gd"
    "career_progression_system_test.gd"
    "competency_system_test.gd"
    "profession_talent_system_test.gd"
    "difficulty_director_test.gd"
    "difficulty_profile_test.gd"
    "difficulty_simulation_test.gd"
    "disease_definition_test.gd"
    "disease_end_of_day_test.gd"
    "disease_system_test.gd"
    "dive_risk_system_test.gd"
    "dive_system_test.gd"
    "diver_clearance_integration_test.gd"
    "diving_equipment_test.gd"
    "expedition_preparation_selection_test.gd"
    "interactable_visual_style_test.gd"
    "narrative_content_test.gd"
    "portrait_catalog_test.gd"
    "production_system_test.gd"
    "rescue_system_test.gd"
    "roster_rotation_skeleton_test.gd"
    "campaign_format_test.gd"
    "settings_manager_test.gd"
    "settlement_event_balance_test.gd"
    "settlement_event_system_test.gd"
    "smoke_test.gd"
    "survival_dependencies_test.gd"
    "tutorial_flow_test.gd"
    "weather_system_test.gd"
    "worker_assignment_persistence_test.gd"
)

$quickHeadlessFlowScenes = @(
    "BaseMusicTest.tscn"
    "NarrativeDialogueFlowTest.tscn"
    "WorkerCandidatePickerFlowTest.tscn"
)

$fullHeadlessFlowScenes = @(
    "BaseMusicTest.tscn"
    "BaseOptionalPanelsFlowTest.tscn"
    "BasePortraitBindingTest.tscn"
    "BuildingSlotMotionTest.tscn"
    "DayTransitionPerformanceTest.tscn"
    "diver_workbench/tests/DiverPresentationTest.tscn"
    "IntroFlowTest.tscn"
    "MorningEventFlowTest.tscn"
    "NarrativeDialogueFlowTest.tscn"
    "PauseMenuFlowTest.tscn"
    "SettingsUIFlowTest.tscn"
    "SurvivorDevelopmentFlowTest.tscn"
    "TutorialPartialLootFlowTest.tscn"
    "WorkerCandidatePickerFlowTest.tscn"
)

$headlessScriptTests = @(if ($Full) { $fullHeadlessScriptTests } else { $quickHeadlessScriptTests })
$headlessFlowScenes = @(if ($Full) { $fullHeadlessFlowScenes } else { $quickHeadlessFlowScenes })

$nativeSnapshotScenes = @(
    "BaseBuildingsSnapshot.tscn"
    "BaseManagementWorkspaceSnapshot.tscn"
    "BaseUISnapshot.tscn"
    "BaseWeatherSnapshot.tscn"
    "BuildingOccupancyBadgesSnapshot.tscn"
    "CampaignOutcomesSnapshot.tscn"
    "DiveHudLayoutSnapshot.tscn"
    "IntroVisualSnapshot.tscn"
    "SettingsUISnapshot.tscn"
)

function Resolve-ExecutableCandidate {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $resolvedPath = $null
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        $resolvedPath = (Resolve-Path -LiteralPath $Candidate).Path
    }
    else {
        $command = Get-Command -Name $Candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $resolvedPath = $command.Source
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        return $null
    }

    # Official Windows distributions ship a GUI executable and a companion
    # console executable. Prefer the companion even if the GUI path was passed.
    if ($env:OS -eq "Windows_NT" -and
        [System.IO.Path]::GetExtension($resolvedPath) -ieq ".exe" -and
        [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath) -notmatch "_console$") {
        $directory = [System.IO.Path]::GetDirectoryName($resolvedPath)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
        $consoleSibling = Join-Path $directory ($stem + "_console.exe")
        if (Test-Path -LiteralPath $consoleSibling -PathType Leaf) {
            return (Resolve-Path -LiteralPath $consoleSibling).Path
        }
    }

    return $resolvedPath
}

function Find-GodotConsole {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $requested = Resolve-ExecutableCandidate -Candidate $RequestedPath
        if ($null -eq $requested) {
            throw "Godot executable was not found at '$RequestedPath'."
        }
        return $requested
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($environmentCandidate in @(
        $env:GODOT_CONSOLE_PATH,
        $env:GODOT_CONSOLE,
        $env:GODOT4_BIN,
        $env:GODOT_BIN
    )) {
        if (-not [string]::IsNullOrWhiteSpace($environmentCandidate)) {
            $candidates.Add($environmentCandidate)
        }
    }

    foreach ($commandName in @("godot4_console", "godot_console", "godot4", "godot")) {
        $candidates.Add($commandName)
    }

    if ($env:OS -eq "Windows_NT") {
        $searchDirectories = [System.Collections.Generic.List[string]]::new()
        $searchDirectories.Add($projectRoot)
        if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
            $searchDirectories.Add((Join-Path $env:ProgramFiles "Godot"))
            $searchDirectories.Add((Join-Path $env:ProgramFiles "Godot Engine"))
        }
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $searchDirectories.Add((Join-Path $env:LOCALAPPDATA "Programs\Godot"))
            $winGetPackages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
            if (Test-Path -LiteralPath $winGetPackages -PathType Container) {
                $packageDirectories = Get-ChildItem -LiteralPath $winGetPackages -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "GodotEngine.GodotEngine*" }
                foreach ($packageDirectory in $packageDirectories) {
                    $searchDirectories.Add($packageDirectory.FullName)
                }
            }
        }

        $discovered = foreach ($directory in $searchDirectories) {
            if (Test-Path -LiteralPath $directory -PathType Container) {
                if ([System.IO.Path]::GetFullPath($directory) -eq $projectRoot) {
                    Get-ChildItem -LiteralPath $directory -File -Filter "Godot*_console.exe" -ErrorAction SilentlyContinue
                }
                else {
                    Get-ChildItem -LiteralPath $directory -File -Filter "Godot*_console.exe" -Recurse -ErrorAction SilentlyContinue
                }
            }
        }
        foreach ($executable in @($discovered | Sort-Object LastWriteTimeUtc -Descending)) {
            $candidates.Add($executable.FullName)
        }
    }

    $fallback = $null
    $seen = @{}
    foreach ($candidate in $candidates) {
        $resolved = Resolve-ExecutableCandidate -Candidate $candidate
        if ($null -eq $resolved) {
            continue
        }
        $key = $resolved.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true

        if ($env:OS -ne "Windows_NT" -or
            [System.IO.Path]::GetFileNameWithoutExtension($resolved) -match "_console$") {
            return $resolved
        }
        if ($null -eq $fallback) {
            $fallback = $resolved
        }
    }

    if ($null -ne $fallback) {
        Write-Warning "No dedicated Godot *_console.exe was found; using '$fallback'. Output capture may depend on that executable's build."
        return $fallback
    }

    throw "Godot console executable was not found. Pass -GodotConsolePath, set GODOT_CONSOLE_PATH, or add Godot to PATH."
}

function Get-TestWorkspaceRoot {
    if ($env:OS -eq "Windows_NT" -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return Join-Path $env:LOCALAPPDATA "OstatniPomost\TestWorkspaces"
    }
    return Join-Path ([System.IO.Path]::GetTempPath()) "OstatniPomost/TestWorkspaces"
}

function Remove-IsolatedTestWorkspace {
    param(
        [string]$WorkspacePath,
        [string]$WorkspaceRoot
    )

    if ([string]::IsNullOrWhiteSpace($WorkspacePath) -or -not (Test-Path -LiteralPath $WorkspacePath)) {
        return
    }

    $normalizedRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]"\/")
    $normalizedWorkspace = [System.IO.Path]::GetFullPath($WorkspacePath).TrimEnd([char[]]"\/")
    $requiredPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($normalizedWorkspace -eq $normalizedRoot -or
        -not $normalizedWorkspace.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove test workspace outside '$normalizedRoot': '$normalizedWorkspace'."
    }

    Remove-Item -LiteralPath $normalizedWorkspace -Recurse -Force
}

function ConvertTo-ProcessArgument {
    param([AllowEmptyString()][string]$Argument)

    # ProcessStartInfo.ArgumentList is unavailable on Windows PowerShell 5.1.
    # Build one Windows command-line argument according to CommandLineToArgvW:
    # backslashes are doubled only before a quote and before the closing quote.
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]'\') {
            $backslashCount++
            continue
        }

        if ($character -eq [char]'"') {
            [void]$builder.Append([char]'\', ($backslashCount * 2) + 1)
            [void]$builder.Append('"')
        }
        else {
            if ($backslashCount -gt 0) {
                [void]$builder.Append([char]'\', $backslashCount)
            }
            [void]$builder.Append($character)
        }
        $backslashCount = 0
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append([char]'\', $backslashCount * 2)
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-GitSnapshotProjectPaths {
    param(
        [string]$ProjectRoot
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]"\/")
    $gitCommand = Get-Command -Name "git" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $gitCommand) {
        throw "Git is required to create an isolated test snapshot."
    }

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $gitCommand.Source
        $gitArguments = @(
            "-c", "safe.directory=$($normalizedRoot.Replace('\', '/'))",
            "-C", $normalizedRoot,
            "ls-files", "--cached", "--others", "--exclude-standard", "-z"
        )
        $startInfo.Arguments = (@($gitArguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $normalizedRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Git snapshot path query could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Git snapshot path query timed out after 30 seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Git snapshot path query failed with exit code $($process.ExitCode): $($standardError.Trim())"
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    # Windows PowerShell 5.1 can bind the scalar-char Split overload differently
    # and retain the empty record after Git's required trailing NUL. Select the
    # char[] overload explicitly and filter only truly empty records so paths
    # containing spaces remain byte-for-byte meaningful.
    $rawPaths = $standardOutput.Split(
        [char[]]@([char]0),
        [System.StringSplitOptions]::None
    )
    foreach ($rawPath in $rawPaths) {
        if ([string]::IsNullOrEmpty($rawPath)) {
            continue
        }
        $relativePath = $rawPath.Replace('\', '/')
        if ([System.IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -eq ".." -or
            $relativePath.StartsWith("../", [StringComparison]::Ordinal) -or
            $relativePath.Contains("/../")) {
            throw "Git snapshot path escaped project root: '$relativePath'."
        }
        $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Git snapshot path escaped project root: '$relativePath'."
        }
        if (-not $seen.Add($relativePath)) {
            throw "Git snapshot path query returned a duplicate path: '$relativePath'."
        }
        $paths.Add($relativePath)
    }

    $result = [string[]]$paths.ToArray()
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Invoke-GitTextQuery {
    param(
        [string]$ProjectRoot,
        [string[]]$Arguments,
        [string]$Description
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]"\/")
    $gitCommand = Get-Command -Name "git" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $gitCommand) {
        throw "Git is required to query $Description."
    }

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $gitCommand.Source
        $gitArguments = @(
            "-c", "safe.directory=$($normalizedRoot.Replace('\', '/'))",
            "-C", $normalizedRoot
        ) + @($Arguments)
        $startInfo.Arguments = (@($gitArguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $normalizedRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Git $Description query could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Git $Description query timed out after 30 seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Git $Description query failed with exit code $($process.ExitCode): $($standardError.Trim())"
        }
        return $standardOutput
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Get-GitSourceIdentity {
    param([string]$ProjectRoot)

    $headCommit = (Invoke-GitTextQuery `
        -ProjectRoot $ProjectRoot `
        -Arguments @("rev-parse", "--verify", "HEAD") `
        -Description "HEAD commit").Trim().ToLowerInvariant()
    $headTree = (Invoke-GitTextQuery `
        -ProjectRoot $ProjectRoot `
        -Arguments @("rev-parse", "--verify", "HEAD^{tree}") `
        -Description "HEAD tree").Trim().ToLowerInvariant()
    if ($headCommit -notmatch '^[0-9a-f]{40,64}$' -or $headTree -notmatch '^[0-9a-f]{40,64}$') {
        throw "Git source identity did not return valid HEAD and tree object IDs."
    }

    $statusText = Invoke-GitTextQuery `
        -ProjectRoot $ProjectRoot `
        -Arguments @("status", "--porcelain=v1", "--untracked-files=all", "-z") `
        -Description "worktree status"
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $statusBytes = [System.Text.Encoding]::UTF8.GetBytes($statusText)
        $statusDigest = [System.BitConverter]::ToString($hasher.ComputeHash($statusBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }

    return [pscustomobject]@{
        HeadCommit = $headCommit
        HeadTree = $headTree
        WorktreeClean = [string]::IsNullOrEmpty($statusText)
        StatusDigest = $statusDigest
    }
}

function Get-ProjectSnapshotFingerprint {
    param(
        [string]$ProjectRoot,
        [AllowNull()][string[]]$ProjectPaths = $null
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]"\/")
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $paths = if ($null -eq $ProjectPaths) {
        @(Get-GitSnapshotProjectPaths -ProjectRoot $normalizedRoot)
    }
    else {
        @($ProjectPaths)
    }
    $entries = [System.Collections.Generic.List[object]]::new()
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $paths) {
        $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Snapshot path escaped project root: '$relativePath'."
        }
        $pathToken = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($relativePath))
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            $records.Add("M`t$pathToken")
            $entries.Add([pscustomobject]@{
                RelativePath = $relativePath
                Exists = $false
                Length = 0L
                Sha256 = ""
            })
            continue
        }
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Git snapshot entry is not a file: '$relativePath'."
        }
        $file = Get-Item -LiteralPath $absolutePath
        $fileHash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $records.Add("F`t$pathToken`t$($file.Length)`t$fileHash")
        $entries.Add([pscustomobject]@{
            RelativePath = $relativePath
            Exists = $true
            Length = [long]$file.Length
            Sha256 = $fileHash
        })
    }

    $manifestText = [string]::Join("`n", $records)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifestText)
        $digest = [System.BitConverter]::ToString($hasher.ComputeHash($manifestBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    return [PSCustomObject]@{
        Digest = $digest
        FileCount = @($entries | Where-Object Exists).Count
        MissingCount = @($entries | Where-Object { -not $_.Exists }).Count
        PathCount = $paths.Count
        ProjectPaths = @($paths)
        Entries = @($entries)
        Records = @($records)
    }
}

function New-IsolatedTestWorkspace {
    param(
        [string]$SourceProjectRoot,
        [string]$WorkspaceRoot
    )

    [void](New-Item -ItemType Directory -Path $WorkspaceRoot -Force)
    $maxSnapshotAttempts = 3
    $lastSnapshotError = $null

    for ($attempt = 1; $attempt -le $maxSnapshotAttempts; $attempt++) {
        $workspaceName = "run_{0}_{1}_{2}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $PID, [Guid]::NewGuid().ToString("N")
        $workspacePath = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $workspaceName))
        [void](New-Item -ItemType Directory -Path $workspacePath)
        try {
            $sourceIdentityBefore = Get-GitSourceIdentity -ProjectRoot $SourceProjectRoot
            $sourceBefore = Get-ProjectSnapshotFingerprint -ProjectRoot $SourceProjectRoot
            foreach ($entry in @($sourceBefore.Entries | Where-Object Exists)) {
                $sourcePath = Join-Path $SourceProjectRoot $entry.RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                $destinationPath = Join-Path $workspacePath $entry.RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                $destinationDirectory = [System.IO.Path]::GetDirectoryName($destinationPath)
                if (-not [string]::IsNullOrWhiteSpace($destinationDirectory)) {
                    [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)
                }
                Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
            }
            $sourceAfter = Get-ProjectSnapshotFingerprint -ProjectRoot $SourceProjectRoot
            $sourceIdentityAfter = Get-GitSourceIdentity -ProjectRoot $SourceProjectRoot
            $destinationSnapshot = Get-ProjectSnapshotFingerprint `
                -ProjectRoot $workspacePath `
                -ProjectPaths $sourceBefore.ProjectPaths
            $snapshotIsStable = (
                $sourceBefore.Digest -eq $sourceAfter.Digest -and
                $sourceAfter.Digest -eq $destinationSnapshot.Digest -and
                $sourceBefore.FileCount -eq $sourceAfter.FileCount -and
                $sourceAfter.FileCount -eq $destinationSnapshot.FileCount -and
                $sourceBefore.PathCount -eq $sourceAfter.PathCount -and
                $sourceAfter.PathCount -eq $destinationSnapshot.PathCount -and
                $sourceIdentityBefore.HeadCommit -eq $sourceIdentityAfter.HeadCommit -and
                $sourceIdentityBefore.HeadTree -eq $sourceIdentityAfter.HeadTree -and
                $sourceIdentityBefore.WorktreeClean -eq $sourceIdentityAfter.WorktreeClean -and
                $sourceIdentityBefore.StatusDigest -eq $sourceIdentityAfter.StatusDigest
            )
            if ($snapshotIsStable) {
                Write-Host ("  Source snapshot: {0} ({1} files / {2} Git paths, immutable FROZEN copy, attempt {3}/{4})" -f $destinationSnapshot.Digest, $destinationSnapshot.FileCount, $destinationSnapshot.PathCount, $attempt, $maxSnapshotAttempts)
                return [pscustomobject]@{
                    WorkspacePath = $workspacePath
                    SourceSnapshot = $destinationSnapshot
                    SourceIdentity = $sourceIdentityAfter
                }
            }
            $lastSnapshotError = (
                "Source files changed while isolated test snapshot attempt " +
                "$attempt/$maxSnapshotAttempts was copied. " +
                "before=$($sourceBefore.Digest)/$($sourceBefore.FileCount)/$($sourceBefore.PathCount), " +
                "after=$($sourceAfter.Digest)/$($sourceAfter.FileCount)/$($sourceAfter.PathCount), " +
                "copy=$($destinationSnapshot.Digest)/$($destinationSnapshot.FileCount)/$($destinationSnapshot.PathCount)."
            )
        }
        catch {
            $lastSnapshotError = "Snapshot attempt $attempt/$maxSnapshotAttempts could not produce a stable copy: $($_.Exception.Message)"
        }

        try {
            Remove-IsolatedTestWorkspace -WorkspacePath $workspacePath -WorkspaceRoot $WorkspaceRoot
        }
        catch {
            throw "Failed to remove incomplete test workspace '$workspacePath': $($_.Exception.Message)"
        }
        if ($attempt -lt $maxSnapshotAttempts) {
            Write-Warning "$lastSnapshotError Retrying after a short backoff; no Godot process was started."
            Start-Sleep -Milliseconds 150
        }
    }

    throw (
        "$lastSnapshotError No Godot process was started after " +
        "$maxSnapshotAttempts attempts. Open a short snapshot window and retry."
    )
}

function Get-ExplicitStructureTestPackageId {
    param([AllowNull()][string]$ResolvedTarget)

    if ([string]::IsNullOrWhiteSpace($ResolvedTarget)) {
        return $null
    }
    $normalizedTarget = $ResolvedTarget.Replace('\', '/')
    if ($normalizedTarget -match '^underwater_map_workbench/structures/([a-z][a-z0-9_]*)/tests/[^/]+\.gd$') {
        return $Matches[1]
    }
    return $null
}

function Get-DirectoryOverlayFingerprint {
    param([string]$DirectoryRoot)

    $normalizedRoot = [System.IO.Path]::GetFullPath($DirectoryRoot).TrimEnd([char[]]"\/")
    if (-not (Test-Path -LiteralPath $normalizedRoot -PathType Container)) {
        throw "Structure overlay directory does not exist: '$normalizedRoot'."
    }
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $relativePaths = @(
        Get-ChildItem -LiteralPath $normalizedRoot -Recurse -File |
            ForEach-Object {
                $resolvedPath = [System.IO.Path]::GetFullPath($_.FullName)
                if (-not $resolvedPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Structure overlay file escaped its root: '$resolvedPath'."
                }
                $resolvedPath.Substring($rootPrefix.Length).Replace('\', '/')
            }
    )
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)
    $entries = [System.Collections.Generic.List[object]]::new()
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $relativePaths) {
        $absolutePath = Join-Path $normalizedRoot $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $file = Get-Item -LiteralPath $absolutePath
        $sha256 = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $pathToken = ConvertTo-TestRunReceiptField -Value $relativePath
        $records.Add("$pathToken|$($file.Length)|$sha256")
        $entries.Add([pscustomobject]@{
            RelativePath = $relativePath
            Length = [long]$file.Length
            Sha256 = $sha256
        })
    }
    $canonicalManifest = [string]::Join("`n", $records)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalManifest)
        $digest = [System.BitConverter]::ToString($hasher.ComputeHash($manifestBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    return [pscustomobject]@{
        Digest = $digest
        FileCount = $entries.Count
        Entries = @($entries)
        CanonicalManifest = $canonicalManifest
    }
}

function New-IsolatedTrackedEolProof {
    param(
        [string]$SourceProjectRoot,
        [string]$IsolatedProjectRoot,
        [string]$StructureId,
        [string]$SourceSnapshotDigest,
        [int]$TimeoutSeconds = 120
    )

    if ($StructureId -notmatch '^[a-z][a-z0-9_]*$' -or
        $SourceSnapshotDigest -notmatch '^[0-9a-f]{64}$') {
        throw "Cannot create an isolated EOL proof for invalid structure/snapshot metadata."
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($SourceProjectRoot).TrimEnd([char[]]"\/")
    $isolatedRoot = [System.IO.Path]::GetFullPath($IsolatedProjectRoot).TrimEnd([char[]]"\/")
    if ([string]::Equals($sourceRoot, $isolatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to attest an in-place source checkout as an isolated snapshot."
    }
    if (Test-Path -LiteralPath (Join-Path $isolatedRoot ".git")) {
        throw "Isolated EOL proof must not rely on copied Git metadata."
    }
    # The source Git checkout, not the untrusted non-Git copy, issues the
    # attestation after rehashing both sides of the snapshot boundary.
    $contractTool = $controlContractToolPath
    if (-not (Test-Path -LiteralPath $contractTool -PathType Leaf)) {
        throw "Isolated workbench contract tool is missing: '$contractTool'."
    }
    $pythonCommand = Get-Command -Name "python" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $pythonCommand) {
        throw "Python is required to create an isolated EOL proof."
    }

    $proofDirectory = Join-Path $isolatedRoot ".godot/isolated_eol_proofs"
    [void](New-Item -ItemType Directory -Path $proofDirectory -Force)
    $proofPath = Join-Path $proofDirectory ("{0}-{1}.json" -f $StructureId, [Guid]::NewGuid().ToString("N"))
    $keyBytes = New-Object byte[] 32
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($keyBytes)
    }
    finally {
        $random.Dispose()
    }
    $proofKey = [System.BitConverter]::ToString($keyBytes).Replace("-", "").ToLowerInvariant()

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pythonCommand.Source
        $arguments = @(
            "-I", "-B", $isolatedPythonEntryPath,
            "--preload", "workbench_lock=$controlLockToolPath",
            "--script", $contractTool, "--",
            "--repo", $sourceRoot,
            "eol-proof", "create",
            "--snapshot-root", $isolatedRoot,
            "--snapshot-digest", $SourceSnapshotDigest,
            "--structure-id", $StructureId,
            "--proof", $proofPath
        )
        $startInfo.Arguments = (@($arguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $sourceRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.EnvironmentVariables["OSTATNI_POMOST_ISOLATED_EOL_PROOF_KEY"] = $proofKey
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Isolated EOL proof process could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { $process.Kill() }
            $process.WaitForExit()
            throw "Isolated EOL proof timed out after $TimeoutSeconds seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult().Trim()
        $standardError = $standardErrorTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            throw "Isolated EOL proof failed with exit code $($process.ExitCode): $standardOutput $standardError"
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    if (-not (Test-Path -LiteralPath $proofPath -PathType Leaf)) {
        throw "Isolated EOL proof process did not publish its proof file."
    }
    return [pscustomobject]@{
        Version = "isolated-git-eol-proof-v1"
        Path = [System.IO.Path]::GetFullPath($proofPath)
        Key = $proofKey
        Sha256 = (Get-FileHash -LiteralPath $proofPath -Algorithm SHA256).Hash.ToLowerInvariant()
        SourceSnapshotDigest = $SourceSnapshotDigest
        StructureId = $StructureId
    }
}

function Invoke-IsolatedStructureTargetOverlay {
    param(
        [string]$SourceProjectRoot,
        [string]$IsolatedProjectRoot,
        [string]$StructureId,
        [string]$SourceSnapshotDigest,
        [int]$TimeoutSeconds = 300
    )

    if ($StructureId -notmatch '^[a-z][a-z0-9_]*$') {
        throw "Explicit structure target produced an invalid package ID: '$StructureId'."
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($SourceProjectRoot).TrimEnd([char[]]"\/")
    $isolatedRoot = [System.IO.Path]::GetFullPath($IsolatedProjectRoot).TrimEnd([char[]]"\/")
    if ([string]::Equals($sourceRoot, $isolatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to build a structure target in the live source checkout."
    }
    $isolatedPrefix = $isolatedRoot + [System.IO.Path]::DirectorySeparatorChar
    $builderPath = [System.IO.Path]::GetFullPath((Join-Path $isolatedRoot "underwater_map_workbench/tools/build_underwater_map.py"))
    $candidateRoot = [System.IO.Path]::GetFullPath((Join-Path $isolatedRoot ".godot/underwater_map_structure_builds/$StructureId/generated"))
    $authorityRoot = [System.IO.Path]::GetFullPath((Join-Path $isolatedRoot "underwater_map_workbench/structures/$StructureId/generated"))
    foreach ($path in @($builderPath, $candidateRoot, $authorityRoot)) {
        if (-not $path.StartsWith($isolatedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Structure target overlay path escaped the isolated project: '$path'."
        }
    }
    if (-not (Test-Path -LiteralPath $builderPath -PathType Leaf)) {
        throw "Isolated Map builder is missing: '$builderPath'."
    }
    $pythonCommand = Get-Command -Name "python" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $pythonCommand) {
        throw "Python is required for an explicit structure target overlay."
    }

    $eolProof = New-IsolatedTrackedEolProof `
        -SourceProjectRoot $sourceRoot `
        -IsolatedProjectRoot $isolatedRoot `
        -StructureId $StructureId `
        -SourceSnapshotDigest $SourceSnapshotDigest `
        -TimeoutSeconds ([Math]::Min($TimeoutSeconds, 120))

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pythonCommand.Source
        $arguments = @(
            "-I", "-B", $isolatedPythonEntryPath,
            "--preload", "workbench_lock=$controlLockToolPath",
            "--preload", "workbench_contract=$controlContractToolPath",
            "--script", $builderPath, "--",
            "--build-structure", $StructureId
        )
        $startInfo.Arguments = (@($arguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = Join-Path $isolatedRoot "underwater_map_workbench"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.EnvironmentVariables["OSTATNI_POMOST_ISOLATED_EOL_PROOF_PATH"] = $eolProof.Path
        $startInfo.EnvironmentVariables["OSTATNI_POMOST_ISOLATED_EOL_PROOF_KEY"] = $eolProof.Key
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Isolated structure target builder could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { $process.Kill() }
            $process.WaitForExit()
            throw "Isolated structure target build timed out after $TimeoutSeconds seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult().Trim()
        $standardError = $standardErrorTask.GetAwaiter().GetResult().Trim()
        $proofHashAfter = if (Test-Path -LiteralPath $eolProof.Path -PathType Leaf) {
            (Get-FileHash -LiteralPath $eolProof.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        else {
            "missing"
        }
        if ($proofHashAfter -ne $eolProof.Sha256) {
            throw "Isolated structure target builder changed its EOL proof."
        }
        if ($process.ExitCode -ne 0) {
            throw "Isolated structure target build failed with exit code $($process.ExitCode): $standardOutput $standardError"
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    $candidateBefore = Get-DirectoryOverlayFingerprint -DirectoryRoot $candidateRoot
    if ($candidateBefore.FileCount -lt 1) {
        throw "Isolated structure target builder produced an empty candidate overlay."
    }
    if (Test-Path -LiteralPath $authorityRoot) {
        Remove-Item -LiteralPath $authorityRoot -Recurse -Force
    }
    [void](New-Item -ItemType Directory -Path $authorityRoot -Force)
    foreach ($entry in $candidateBefore.Entries) {
        $sourcePath = Join-Path $candidateRoot $entry.RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $destinationPath = Join-Path $authorityRoot $entry.RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $destinationDirectory = [System.IO.Path]::GetDirectoryName($destinationPath)
        [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
    $candidateAfter = Get-DirectoryOverlayFingerprint -DirectoryRoot $candidateRoot
    $authorityAfter = Get-DirectoryOverlayFingerprint -DirectoryRoot $authorityRoot
    if ($candidateBefore.Digest -ne $candidateAfter.Digest -or
        $candidateAfter.Digest -ne $authorityAfter.Digest -or
        $candidateBefore.FileCount -ne $authorityAfter.FileCount) {
        throw "Structure target candidate changed or copied authority differs from the exact overlay."
    }

    $canonicalReceipt = @(
        "version=godot-structure-target-overlay-v1",
        "source_snapshot=$SourceSnapshotDigest",
        "structure_id=$StructureId",
        "candidate_root=.godot/underwater_map_structure_builds/$StructureId/generated",
        "authority_root=underwater_map_workbench/structures/$StructureId/generated",
        "file_count=$($authorityAfter.FileCount)",
        "content_digest=$($authorityAfter.Digest)"
    ) -join "`n"
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalReceipt)
        $overlayDigest = [System.BitConverter]::ToString($hasher.ComputeHash($receiptBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    return [pscustomobject]@{
        Version = "godot-structure-target-overlay-v1"
        Digest = $overlayDigest
        StructureId = $StructureId
        FileCount = $authorityAfter.FileCount
        ContentDigest = $authorityAfter.Digest
        CanonicalFileManifest = $authorityAfter.CanonicalManifest
        CanonicalReceipt = $canonicalReceipt
        EolProofVersion = $eolProof.Version
        EolProofSha256 = $eolProof.Sha256
    }
}

function Get-AvailableIsolatedTestPort {
    param([System.Collections.Generic.HashSet[int]]$UsedPorts)

    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        for ($attempt = 0; $attempt -lt 64; $attempt++) {
            $bytes = New-Object byte[] 4
            $random.GetBytes($bytes)
            $candidate = 20000 + ([int]([System.BitConverter]::ToUInt32($bytes, 0) % 28000))
            if ($UsedPorts.Contains($candidate)) {
                continue
            }
            $gateName = if ($env:OS -eq "Windows_NT") {
                "Local\OstatniPomost.GodotPort.$candidate"
            }
            else {
                "OstatniPomost.GodotPort.$candidate"
            }
            $gate = [System.Threading.Semaphore]::new(1, 1, $gateName)
            $gateOwned = $false
            $listener = $null
            try {
                $gateOwned = $gate.WaitOne(0)
                if (-not $gateOwned) {
                    $gate.Dispose()
                    continue
                }
                $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $candidate)
                $listener.Start()
                $listener.Stop()
                $listener = $null
                [void]$UsedPorts.Add($candidate)
                return [pscustomobject]@{
                    Port = $candidate
                    Gate = $gate
                    GateOwned = $true
                }
            }
            catch [System.Net.Sockets.SocketException] {
                if ($null -ne $listener) {
                    $listener.Stop()
                }
                if ($gateOwned) {
                    [void]$gate.Release()
                }
                $gate.Dispose()
            }
            catch {
                if ($null -ne $listener) {
                    $listener.Stop()
                }
                if ($gateOwned) {
                    [void]$gate.Release()
                }
                $gate.Dispose()
                throw
            }
        }
    }
    finally {
        $random.Dispose()
    }
    throw "Could not allocate an isolated Godot service port after 64 attempts."
}

function Get-IsolatedTestUserDirectoryRoot {
    if ($env:OS -eq "Windows_NT") {
        $dataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    }
    elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $dataRoot = Join-Path $userProfile "Library/Application Support"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:XDG_DATA_HOME)) {
        $dataRoot = $env:XDG_DATA_HOME
    }
    else {
        $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $dataRoot = Join-Path $userProfile ".local/share"
    }
    if ([string]::IsNullOrWhiteSpace($dataRoot)) {
        throw "Could not resolve the platform user data root for isolated Godot tests."
    }
    return [System.IO.Path]::GetFullPath((Join-Path $dataRoot "OstatniPomost/TestRuns"))
}

function Assert-IsolatedTestUserDirectoryRoot {
    param([string]$UserDirectoryRoot)

    $normalizedRoot = [System.IO.Path]::GetFullPath($UserDirectoryRoot).TrimEnd([char[]]"\/")
    $platformRoot = (Get-IsolatedTestUserDirectoryRoot).TrimEnd([char[]]"\/")
    if ([string]::Equals($normalizedRoot, $platformRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $normalizedRoot
    }

    # The infrastructure test may exercise cleanup only inside its validated
    # disposable fixture. Production calls never pass this override.
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]"\/")
    $tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($normalizedRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $relativeRoot = $normalizedRoot.Substring($tempPrefix.Length).Replace('\', '/')
        $firstSegment = $relativeRoot.Split('/')[0]
        if ($firstSegment -match '^ostatni_pomost_runner_test_[0-9a-f]{32}$') {
            return $normalizedRoot
        }
    }
    throw "Refusing to manage test user:// outside '$platformRoot' or a validated runner test fixture: '$normalizedRoot'."
}

function New-IsolatedTestRunContext {
    param([AllowNull()][string]$UserDirectoryRootOverride = $null)

    $runId = "run_{0}_{1}_{2}" -f (Get-Date -Format "yyyyMMdd_HHmmss_fff"), $PID, [Guid]::NewGuid().ToString("N")
    $usedPorts = [System.Collections.Generic.HashSet[int]]::new()
    $leases = [System.Collections.Generic.List[object]]::new()
    try {
        $leases.Add((Get-AvailableIsolatedTestPort -UsedPorts $usedPorts))
        $leases.Add((Get-AvailableIsolatedTestPort -UsedPorts $usedPorts))
        $leases.Add((Get-AvailableIsolatedTestPort -UsedPorts $usedPorts))
        $userDirectoryRoot = if ([string]::IsNullOrWhiteSpace($UserDirectoryRootOverride)) {
            Get-IsolatedTestUserDirectoryRoot
        }
        else {
            Assert-IsolatedTestUserDirectoryRoot -UserDirectoryRoot $UserDirectoryRootOverride
        }
        return [pscustomobject]@{
            RunId = $runId
            UserDirectoryName = "OstatniPomost/TestRuns/$runId"
            UserDirectoryRoot = $userDirectoryRoot
            UserDirectoryPath = [System.IO.Path]::GetFullPath((Join-Path $userDirectoryRoot $runId))
            DebugServerUri = "tcp://127.0.0.1:$($leases[0].Port)"
            DebugServerPort = [int]$leases[0].Port
            DapPort = [int]$leases[1].Port
            LspPort = [int]$leases[2].Port
            PortLeases = @($leases)
        }
    }
    catch {
        foreach ($lease in $leases) {
            if ($lease.GateOwned) {
                [void]$lease.Gate.Release()
                $lease.GateOwned = $false
            }
            $lease.Gate.Dispose()
        }
        throw
    }
}

function Release-IsolatedTestRunContext {
    param([AllowNull()][pscustomobject]$RunContext)

    if ($null -eq $RunContext -or $null -eq $RunContext.PSObject.Properties['PortLeases']) {
        return
    }
    foreach ($lease in @($RunContext.PortLeases)) {
        if ($null -eq $lease) {
            continue
        }
        if ($lease.GateOwned) {
            [void]$lease.Gate.Release()
            $lease.GateOwned = $false
        }
        $lease.Gate.Dispose()
    }
}

function Invoke-IsolatedTestUserDirectoryRetention {
    param(
        [string]$UserDirectoryRoot,
        [AllowNull()][string]$ExcludedRunId,
        [ValidateRange(1, 100)][int]$MaxPreservedRuns = 12,
        [ValidateRange(1, 365)][int]$MaxAgeDays = 7
    )

    if (-not (Test-Path -LiteralPath $UserDirectoryRoot -PathType Container)) {
        return
    }
    $normalizedRoot = Assert-IsolatedTestUserDirectoryRoot -UserDirectoryRoot $UserDirectoryRoot
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $directories = @(Get-ChildItem -LiteralPath $normalizedRoot -Directory -Force |
        Where-Object Name -match '^run_[0-9]{8}_[0-9]{6}_[0-9]{3}_[0-9]+_[0-9a-f]{32}$' |
        Sort-Object LastWriteTimeUtc -Descending)
    $cutoff = [DateTime]::UtcNow.AddDays(-$MaxAgeDays)
    $removePaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt $directories.Count; $index++) {
        $directory = $directories[$index]
        if ($directory.Name -eq $ExcludedRunId) {
            continue
        }
        if ($directory.LastWriteTimeUtc -lt $cutoff -or $index -ge $MaxPreservedRuns) {
            [void]$removePaths.Add($directory.FullName)
        }
    }
    foreach ($removePath in $removePaths) {
        $normalizedPath = [System.IO.Path]::GetFullPath($removePath).TrimEnd([char[]]"\/")
        if (-not $normalizedPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals(
                [System.IO.Path]::GetDirectoryName($normalizedPath).TrimEnd([char[]]"\/"),
                $normalizedRoot,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove retained test user:// outside '$normalizedRoot': '$normalizedPath'."
        }
        Remove-Item -LiteralPath $normalizedPath -Recurse -Force
    }
}

function Complete-IsolatedTestUserDirectory {
    param(
        [pscustomobject]$RunContext,
        [bool]$Preserve
    )

    $expectedRoot = Assert-IsolatedTestUserDirectoryRoot -UserDirectoryRoot $RunContext.UserDirectoryRoot
    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $expectedRoot $RunContext.RunId)).TrimEnd([char[]]"\/")
    $reportedPath = [System.IO.Path]::GetFullPath($RunContext.UserDirectoryPath).TrimEnd([char[]]"\/")
    if (-not [string]::Equals($expectedPath, $reportedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to manage unexpected test user:// path '$reportedPath'."
    }

    if ($Preserve) {
        if (Test-Path -LiteralPath $reportedPath -PathType Container) {
            Write-Host ("Test user:// preserved: {0}" -f $reportedPath) -ForegroundColor Yellow
        }
    }
    elseif (Test-Path -LiteralPath $reportedPath) {
        Remove-Item -LiteralPath $reportedPath -Recurse -Force
    }

    Invoke-IsolatedTestUserDirectoryRetention `
        -UserDirectoryRoot $expectedRoot `
        -ExcludedRunId $(if ($Preserve) { $RunContext.RunId } else { $null })
}

function Set-IsolatedGodotRunConfiguration {
    param(
        [string]$SourceProjectRoot,
        [string]$IsolatedProjectRoot,
        [pscustomobject]$RunContext,
        [pscustomobject]$SourceSnapshot
    )

    $sourceRoot = [System.IO.Path]::GetFullPath($SourceProjectRoot).TrimEnd([char[]]"\/")
    $isolatedRoot = [System.IO.Path]::GetFullPath($IsolatedProjectRoot).TrimEnd([char[]]"\/")
    if ([string]::Equals($sourceRoot, $isolatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to patch project.godot in the source checkout."
    }
    $isolatedProjectFile = Join-Path $isolatedRoot "project.godot"
    if (-not (Test-Path -LiteralPath $isolatedProjectFile -PathType Leaf)) {
        throw "Isolated project.godot is required for user:// isolation."
    }
    $sourceProjectEntries = @($SourceSnapshot.Entries | Where-Object RelativePath -ceq "project.godot")
    if ($sourceProjectEntries.Count -ne 1 -or -not $sourceProjectEntries[0].Exists) {
        throw "Immutable source snapshot must contain exactly one project.godot file."
    }
    $sourceProjectHash = [string]$sourceProjectEntries[0].Sha256
    $isolatedHashBefore = (Get-FileHash -LiteralPath $isolatedProjectFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($isolatedHashBefore -ne $sourceProjectHash) {
        throw "Isolated project.godot changed before the test overlay was applied."
    }

    $content = [System.IO.File]::ReadAllText($isolatedProjectFile)
    $lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*(?:\r?\n)?',
        ''
    )
    $applicationHeader = [System.Text.RegularExpressions.Regex]::Match($content, '(?m)^\[application\]\r?$')
    if (-not $applicationHeader.Success) {
        throw "Isolated project.godot has no [application] section."
    }
    $insertIndex = $applicationHeader.Index + $applicationHeader.Length
    if ($content.Substring($insertIndex).StartsWith("`r`n")) {
        $insertIndex += 2
    }
    elseif ($content.Substring($insertIndex).StartsWith("`n")) {
        $insertIndex += 1
    }
    $isolationBlock = (
        'config/use_custom_user_dir=true' + $lineEnding +
        'config/custom_user_dir_name="' + $RunContext.UserDirectoryName + '"' + $lineEnding
    )
    $content = $content.Insert($insertIndex, $isolationBlock)
    [System.IO.File]::WriteAllText(
        $isolatedProjectFile,
        $content,
        [System.Text.UTF8Encoding]::new($false)
    )

    $verifiedContent = [System.IO.File]::ReadAllText($isolatedProjectFile)
    if ($verifiedContent -notmatch '(?m)^config/use_custom_user_dir=true$' -or
        -not $verifiedContent.Contains('config/custom_user_dir_name="' + $RunContext.UserDirectoryName + '"')) {
        throw "Isolated project.godot did not retain the per-run user:// settings."
    }
    $isolatedHashAfter = (Get-FileHash -LiteralPath $isolatedProjectFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $canonicalReceipt = @(
        "version=godot-test-overlay-v1",
        "source_snapshot=$($SourceSnapshot.Digest)",
        "path=project.godot",
        "before=$isolatedHashBefore",
        "after=$isolatedHashAfter",
        "run_id=$($RunContext.RunId)",
        "user_directory=$($RunContext.UserDirectoryName)"
    ) -join "`n"
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalReceipt)
        $overlayDigest = [System.BitConverter]::ToString($hasher.ComputeHash($receiptBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    return [pscustomobject]@{
        Version = "godot-test-overlay-v1"
        Digest = $overlayDigest
        SourceSnapshotDigest = [string]$SourceSnapshot.Digest
        RelativePath = "project.godot"
        BeforeSha256 = $isolatedHashBefore
        AfterSha256 = $isolatedHashAfter
        RunId = [string]$RunContext.RunId
        UserDirectoryName = [string]$RunContext.UserDirectoryName
        CanonicalReceipt = $canonicalReceipt
    }
}

function ConvertTo-TestRunReceiptField {
    param([AllowEmptyString()][string]$Value)

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
}

function Get-GodotVersionString {
    param([string]$GodotExecutable)

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotExecutable
        $startInfo.Arguments = "--version"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Godot version process could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            $process.WaitForExit()
            throw "Godot version query timed out after 30 seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult().Trim()
        $standardError = $standardErrorTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            throw "Godot version query failed with exit code $($process.ExitCode): $standardError"
        }
        $version = if (-not [string]::IsNullOrWhiteSpace($standardOutput)) {
            $standardOutput
        }
        else {
            $standardError
        }
        if ([string]::IsNullOrWhiteSpace($version) -or $version -match "[\r\n]") {
            throw "Godot version query did not return one non-empty version line."
        }
        return $version
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function New-GodotTestRunReceipt {
    param(
        [string]$SourceHead,
        [string]$SourceTree,
        [bool]$SourceWorktreeClean,
        [string]$SourceStatusDigest,
        [string]$SourceSnapshotDigest,
        [string]$TestOverlayDigest,
        [string]$TestOverlayVersion,
        [string]$OverlayProjectBeforeSha256,
        [string]$OverlayProjectAfterSha256,
        [string]$OverlayRunId,
        [string]$OverlayUserDirectoryName,
        [string]$StructureOverlayVersion,
        [string]$StructureOverlayDigest,
        [AllowEmptyString()][string]$StructureOverlayId,
        [int]$StructureOverlayFileCount,
        [string]$StructureOverlayContentDigest,
        [AllowEmptyString()][string]$StructureOverlayManifest,
        [string]$RunnerSha256,
        [string]$GodotVersion,
        [string]$SuiteMode,
        [string]$NativeSkipPolicy,
        [int]$DebugServerPort,
        [int]$DapPort,
        [int]$LspPort,
        [object[]]$Results
    )

    if ($SourceHead -notmatch '^[0-9a-f]{40,64}$' -or $SourceTree -notmatch '^[0-9a-f]{40,64}$') {
        throw "Test run receipt requires lowercase Git HEAD and tree object IDs."
    }
    foreach ($digest in @(
        $SourceStatusDigest,
        $SourceSnapshotDigest,
        $TestOverlayDigest,
        $OverlayProjectBeforeSha256,
        $OverlayProjectAfterSha256,
        $StructureOverlayContentDigest,
        $RunnerSha256
    )) {
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw "Test run receipt requires lowercase SHA-256 digests."
        }
    }
    if ($TestOverlayVersion -ne "godot-test-overlay-v1" -or
        [string]::IsNullOrWhiteSpace($OverlayRunId) -or
        [string]::IsNullOrWhiteSpace($OverlayUserDirectoryName) -or
        [string]::IsNullOrWhiteSpace($GodotVersion) -or
        $SuiteMode -notin @("quick", "quick-with-snapshots", "full", "full-with-snapshots", "target", "native-target") -or
        $NativeSkipPolicy -notin @("allowed", "blocking")) {
        throw "Test run receipt metadata cannot be empty."
    }
    $ports = @($DebugServerPort, $DapPort, $LspPort)
    if (@($ports | Where-Object { $_ -lt 1 -or $_ -gt 65535 }).Count -gt 0 -or
        @($ports | Select-Object -Unique).Count -ne 3) {
        throw "Test run receipt requires three distinct valid Godot service ports."
    }
    $overlayCanonicalReceipt = @(
        "version=$TestOverlayVersion",
        "source_snapshot=$SourceSnapshotDigest",
        "path=project.godot",
        "before=$OverlayProjectBeforeSha256",
        "after=$OverlayProjectAfterSha256",
        "run_id=$OverlayRunId",
        "user_directory=$OverlayUserDirectoryName"
    ) -join "`n"
    $overlayHasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $overlayBytes = [System.Text.Encoding]::UTF8.GetBytes($overlayCanonicalReceipt)
        $verifiedOverlayDigest = [System.BitConverter]::ToString($overlayHasher.ComputeHash($overlayBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $overlayHasher.Dispose()
    }
    if ($verifiedOverlayDigest -ne $TestOverlayDigest) {
        throw "Test run receipt overlay metadata does not match the overlay digest."
    }
    $structureManifestHasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $structureManifestBytes = [System.Text.Encoding]::UTF8.GetBytes($StructureOverlayManifest)
        $verifiedStructureContentDigest = [System.BitConverter]::ToString($structureManifestHasher.ComputeHash($structureManifestBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $structureManifestHasher.Dispose()
    }
    if ($verifiedStructureContentDigest -ne $StructureOverlayContentDigest) {
        throw "Structure target overlay manifest does not match its content digest."
    }
    $structureManifestLines = @(if ([string]::IsNullOrEmpty($StructureOverlayManifest)) {
        @()
    }
    else {
        @($StructureOverlayManifest -split "`n")
    })
    if ($structureManifestLines.Count -ne $StructureOverlayFileCount) {
        throw "Structure target overlay file count differs from its exact manifest."
    }
    $previousStructurePath = $null
    foreach ($manifestLine in $structureManifestLines) {
        $manifestParts = @($manifestLine -split '\|', 3)
        if ($manifestParts.Count -ne 3 -or $manifestParts[1] -notmatch '^(0|[1-9][0-9]*)$' -or
            $manifestParts[2] -notmatch '^[0-9a-f]{64}$') {
            throw "Structure target overlay contains an invalid file manifest record."
        }
        $manifestPath = ConvertFrom-TestRunReceiptField -Value $manifestParts[0]
        if ([string]::IsNullOrWhiteSpace($manifestPath) -or
            [System.IO.Path]::IsPathRooted($manifestPath) -or
            $manifestPath.Contains('\') -or
            $manifestPath -eq ".." -or
            $manifestPath.StartsWith("../", [StringComparison]::Ordinal) -or
            $manifestPath.Contains("/../") -or
            ($null -ne $previousStructurePath -and [string]::CompareOrdinal($previousStructurePath, $manifestPath) -ge 0)) {
            throw "Structure target overlay file manifest paths are not canonical and ordered."
        }
        $previousStructurePath = $manifestPath
    }
    if ($StructureOverlayVersion -eq "none") {
        if ($StructureOverlayDigest -ne "none" -or
            -not [string]::IsNullOrEmpty($StructureOverlayId) -or
            $StructureOverlayFileCount -ne 0 -or
            -not [string]::IsNullOrEmpty($StructureOverlayManifest)) {
            throw "Non-structure test run must publish an empty structure overlay."
        }
    }
    elseif ($StructureOverlayVersion -eq "godot-structure-target-overlay-v1") {
        if ($StructureOverlayDigest -notmatch '^[0-9a-f]{64}$' -or
            $StructureOverlayId -notmatch '^[a-z][a-z0-9_]*$' -or
            $StructureOverlayFileCount -lt 1) {
            throw "Structure target overlay metadata is invalid."
        }
        $structureOverlayCanonical = @(
            "version=$StructureOverlayVersion",
            "source_snapshot=$SourceSnapshotDigest",
            "structure_id=$StructureOverlayId",
            "candidate_root=.godot/underwater_map_structure_builds/$StructureOverlayId/generated",
            "authority_root=underwater_map_workbench/structures/$StructureOverlayId/generated",
            "file_count=$StructureOverlayFileCount",
            "content_digest=$StructureOverlayContentDigest"
        ) -join "`n"
        $structureOverlayHasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $structureOverlayBytes = [System.Text.Encoding]::UTF8.GetBytes($structureOverlayCanonical)
            $verifiedStructureOverlayDigest = [System.BitConverter]::ToString($structureOverlayHasher.ComputeHash($structureOverlayBytes)).Replace("-", "").ToLowerInvariant()
        }
        finally {
            $structureOverlayHasher.Dispose()
        }
        if ($verifiedStructureOverlayDigest -ne $StructureOverlayDigest) {
            throw "Structure target overlay metadata does not match its overlay digest."
        }
    }
    else {
        throw "Unknown structure target overlay version '$StructureOverlayVersion'."
    }

    $orderedResults = @($Results)
    $targetRunIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($result in $orderedResults) {
        if ([string]::IsNullOrWhiteSpace([string]$result.Name) -or
            [string]::IsNullOrWhiteSpace([string]$result.Group) -or
            [string]$result.Status -notin @("PASS", "FAIL", "SKIP")) {
            throw "Test run receipt contains invalid target result metadata."
        }
        if ([string]$result.Status -eq "PASS" -and
            ([int]$result.ExitCode -ne 0 -or [bool]$result.BlockingFailure)) {
            throw "A PASS target result must have exit code 0 and no blocking failure."
        }
        if ([string]$result.Status -eq "FAIL" -and -not [bool]$result.BlockingFailure) {
            throw "A FAIL target result must be blocking."
        }
        [void](Assert-TrustedTargetEvidence -Result $result)
        if (-not $targetRunIds.Add([string]$result.RunId)) {
            throw "Every target must use a distinct isolated run ID."
        }
    }
    $passCount = @($orderedResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failCount = @($orderedResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $skipCount = @($orderedResults | Where-Object { $_.Status -eq "SKIP" }).Count
    $blockingFailureCount = @($orderedResults | Where-Object { $_.BlockingFailure }).Count
    $overall = if ($blockingFailureCount -eq 0) { "PASS" } else { "FAIL" }

    $receiptLines = [System.Collections.Generic.List[string]]::new()
    $receiptLines.Add("version=godot-test-run-receipt-v2")
    $receiptLines.Add("source_head=$SourceHead")
    $receiptLines.Add("source_tree=$SourceTree")
    $receiptLines.Add("source_worktree_clean=$(if ($SourceWorktreeClean) { '1' } else { '0' })")
    $receiptLines.Add("source_status_digest=$SourceStatusDigest")
    $receiptLines.Add("source_snapshot=$SourceSnapshotDigest")
    $receiptLines.Add("test_overlay=$TestOverlayDigest")
    $receiptLines.Add("overlay_version=$TestOverlayVersion")
    $receiptLines.Add("overlay_project_before=$OverlayProjectBeforeSha256")
    $receiptLines.Add("overlay_project_after=$OverlayProjectAfterSha256")
    $receiptLines.Add("overlay_run_id=$(ConvertTo-TestRunReceiptField -Value $OverlayRunId)")
    $receiptLines.Add("overlay_user_directory=$(ConvertTo-TestRunReceiptField -Value $OverlayUserDirectoryName)")
    $receiptLines.Add("structure_overlay=$StructureOverlayDigest")
    $receiptLines.Add("structure_overlay_version=$StructureOverlayVersion")
    $receiptLines.Add("structure_overlay_id=$(ConvertTo-TestRunReceiptField -Value $StructureOverlayId)")
    $receiptLines.Add("structure_overlay_file_count=$StructureOverlayFileCount")
    $receiptLines.Add("structure_overlay_content_digest=$StructureOverlayContentDigest")
    $receiptLines.Add("structure_overlay_manifest=$(ConvertTo-TestRunReceiptField -Value $StructureOverlayManifest)")
    $receiptLines.Add("runner_sha256=$RunnerSha256")
    $receiptLines.Add("godot_version=$(ConvertTo-TestRunReceiptField -Value $GodotVersion)")
    $receiptLines.Add("suite_mode=$SuiteMode")
    $receiptLines.Add("import=PASS")
    $receiptLines.Add("godot_service_port_scope=import-and-tests")
    $receiptLines.Add("debug_server_port=$DebugServerPort")
    $receiptLines.Add("dap_port=$DapPort")
    $receiptLines.Add("lsp_port=$LspPort")
    $receiptLines.Add("native_skip_policy=$NativeSkipPolicy")
    $receiptLines.Add("target_count=$($orderedResults.Count)")
    for ($index = 0; $index -lt $orderedResults.Count; $index++) {
        $result = $orderedResults[$index]
        $receiptLines.Add((
            "target={0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}" -f `
                $index, `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.Name)), `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.Group)), `
                ([string]$result.Status), `
                ([int]$result.ExitCode), `
                $(if ([bool]$result.BlockingFailure) { "1" } else { "0" }), `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.RunId)), `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.UserDirectoryName)), `
                ([string]$result.InputBeforeDigest), `
                ([string]$result.InputAfterDigest), `
                ([string]$result.InvocationDigest), `
                ([string]$result.OutputDigest), `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.CompletionVersion)), `
                ([string]$result.CompletionDigest), `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.TargetOverlayVersion)), `
                ([string]$result.TargetOverlayDigest)
        ))
    }
    $receiptLines.Add("pass=$passCount")
    $receiptLines.Add("fail=$failCount")
    $receiptLines.Add("skip=$skipCount")
    $receiptLines.Add("blocking=$blockingFailureCount")
    $receiptLines.Add("overall=$overall")
    $canonicalReceipt = $receiptLines -join "`n"

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalReceipt)
        $receiptDigest = [System.BitConverter]::ToString($hasher.ComputeHash($receiptBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }

    return [pscustomobject]@{
        Version = "godot-test-run-receipt-v2"
        Digest = $receiptDigest
        SourceHead = $SourceHead
        SourceTree = $SourceTree
        SourceWorktreeClean = $SourceWorktreeClean
        SourceStatusDigest = $SourceStatusDigest
        SourceSnapshotDigest = $SourceSnapshotDigest
        TestOverlayDigest = $TestOverlayDigest
        TestOverlayVersion = $TestOverlayVersion
        OverlayProjectBeforeSha256 = $OverlayProjectBeforeSha256
        OverlayProjectAfterSha256 = $OverlayProjectAfterSha256
        OverlayRunId = $OverlayRunId
        OverlayUserDirectoryName = $OverlayUserDirectoryName
        StructureOverlayVersion = $StructureOverlayVersion
        StructureOverlayDigest = $StructureOverlayDigest
        StructureOverlayId = $StructureOverlayId
        StructureOverlayFileCount = $StructureOverlayFileCount
        StructureOverlayContentDigest = $StructureOverlayContentDigest
        StructureOverlayManifest = $StructureOverlayManifest
        RunnerSha256 = $RunnerSha256
        GodotVersion = $GodotVersion
        SuiteMode = $SuiteMode
        NativeSkipPolicy = $NativeSkipPolicy
        DebugServerPort = $DebugServerPort
        DapPort = $DapPort
        LspPort = $LspPort
        TargetCount = $orderedResults.Count
        PassCount = $passCount
        FailCount = $failCount
        SkipCount = $skipCount
        BlockingFailureCount = $blockingFailureCount
        Overall = $overall
        Results = @($orderedResults)
        CanonicalReceipt = $canonicalReceipt
    }
}

function Write-GodotTestRunReceipt {
    param(
        [pscustomobject]$Receipt,
        [string]$WorkspaceRoot,
        [AllowNull()][string]$OutputPath = $null
    )

    $normalizedWorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char[]]"\/")
    $receiptPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $defaultRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetDirectoryName($normalizedWorkspaceRoot)) "TestRunReceipts"))
        Join-Path $defaultRoot ("{0}.receipt" -f $Receipt.Digest)
    }
    else {
        [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($OutputPath.Trim()))
    }
    $receiptRoot = [System.IO.Path]::GetDirectoryName($receiptPath)
    if ([string]::IsNullOrWhiteSpace($receiptRoot)) {
        throw "Test run receipt output path has no parent directory."
    }
    $sourcePrefix = $sourceProjectRoot.TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    $workspacePrefix = $normalizedWorkspaceRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($receiptPath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $receiptPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Test run receipts must stay outside the source checkout."
    }
    [void](New-Item -ItemType Directory -Path $receiptRoot -Force)

    $receiptContent = "canonical_sha256=$($Receipt.Digest)`n$($Receipt.CanonicalReceipt)`n"
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        if ([System.IO.File]::ReadAllText($receiptPath) -cne $receiptContent) {
            throw "Existing test run receipt does not match its digest path: '$receiptPath'."
        }
        return $receiptPath
    }

    $temporaryPath = Join-Path $receiptRoot (".{0}.tmp-{1}-{2}" -f $Receipt.Digest, $PID, [Guid]::NewGuid().ToString("N"))
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $receiptContent, [System.Text.UTF8Encoding]::new($false))
        try {
            Move-Item -LiteralPath $temporaryPath -Destination $receiptPath -ErrorAction Stop
        }
        catch {
            if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
                [System.IO.File]::ReadAllText($receiptPath) -cne $receiptContent) {
                throw
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $receiptPath
}

function ConvertFrom-TestRunReceiptField {
    param([string]$Value)

    try {
        $bytes = [Convert]::FromBase64String($Value)
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    }
    catch {
        throw "Test run receipt contains an invalid Base64 UTF-8 field."
    }
}

function Get-GodotCanonicalEvidenceDigest {
    param([AllowEmptyString()][string]$CanonicalEvidence)

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $evidenceBytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalEvidence)
        return [System.BitConverter]::ToString($hasher.ComputeHash($evidenceBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

function Read-GodotCanonicalEvidenceEnvelope {
    param([string]$EvidencePath)

    $resolvedPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($EvidencePath))
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Canonical Godot evidence does not exist: '$resolvedPath'."
    }
    $content = [System.IO.File]::ReadAllText($resolvedPath)
    if ($content.Contains("`r") -or -not $content.EndsWith("`n") -or $content.EndsWith("`n`n")) {
        throw "Canonical Godot evidence must use LF lines and exactly one final newline."
    }
    $lines = @($content.Substring(0, $content.Length - 1).Split([char]"`n"))
    if ($lines.Count -lt 2 -or $lines[0] -notmatch '^canonical_sha256=([0-9a-f]{64})$') {
        throw "Canonical Godot evidence has no valid canonical_sha256 envelope."
    }
    $declaredDigest = $Matches[1]
    $canonicalEvidence = [string]::Join("`n", $lines[1..($lines.Count - 1)])
    $actualDigest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonicalEvidence
    if ($actualDigest -ne $declaredDigest) {
        throw "Canonical Godot evidence SHA-256 is invalid."
    }
    if ($lines[1] -notmatch '^version=([a-z0-9-]+)$') {
        throw "Canonical Godot evidence has no valid version record."
    }
    return [pscustomobject]@{
        Path = $resolvedPath
        Version = $Matches[1]
        Digest = $declaredDigest
        CanonicalEvidence = $canonicalEvidence
        BodyLines = @($lines[1..($lines.Count - 1)])
    }
}

function New-GodotTestShardPlan {
    param(
        [string]$SourceHead,
        [string]$SourceTree,
        [bool]$SourceWorktreeClean,
        [string]$SourceStatusDigest,
        [string]$SourceSnapshotDigest,
        [string]$RunnerSha256,
        [string]$SuiteMode,
        [ValidateRange(1, 64)][int]$HeadlessShardCount,
        [ValidateRange(1, 64)][int]$NativeShardCount,
        [string[]]$TargetNames,
        [string[]]$TargetGroups
    )

    if ($SourceHead -notmatch '^[0-9a-f]{40,64}$' -or $SourceTree -notmatch '^[0-9a-f]{40,64}$') {
        throw "Shard plan requires lowercase Git HEAD and tree object IDs."
    }
    if (-not $SourceWorktreeClean) {
        throw "Shard plan requires a clean committed source."
    }
    foreach ($digest in @($SourceStatusDigest, $SourceSnapshotDigest, $RunnerSha256)) {
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw "Shard plan requires lowercase SHA-256 source digests."
        }
    }
    if ($SuiteMode -notin @("full", "full-with-snapshots")) {
        throw "Shard plan supports only the required full suite."
    }
    $names = @($TargetNames)
    $groups = @($TargetGroups)
    if ($names.Count -lt 1 -or $names.Count -ne $groups.Count) {
        throw "Shard plan requires matching non-empty target name and group lists."
    }
    $targetNameSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $headlessTargetCount = 0
    $nativeTargetCount = 0
    for ($index = 0; $index -lt $names.Count; $index++) {
        if ([string]::IsNullOrWhiteSpace($names[$index]) -or
            [string]::IsNullOrWhiteSpace($groups[$index]) -or
            -not $targetNameSet.Add([string]$names[$index])) {
            throw "Shard plan targets must have unique non-empty names and groups."
        }
        if ($groups[$index] -in @("native window", "native snapshot")) {
            $nativeTargetCount++
        }
        elseif ($groups[$index] -in @("headless script", "headless flow")) {
            $headlessTargetCount++
        }
        else {
            throw "Shard plan target '$($names[$index])' has unknown group '$($groups[$index])'."
        }
    }
    if ($HeadlessShardCount -gt $headlessTargetCount -or $NativeShardCount -gt $nativeTargetCount) {
        throw "Shard plan cannot create an empty shard (headless targets=$headlessTargetCount, native targets=$nativeTargetCount)."
    }

    $shards = [System.Collections.Generic.List[object]]::new()
    $targetCountsByShard = @{}
    for ($index = 0; $index -lt $HeadlessShardCount; $index++) {
        $id = "headless-$index"
        $targetCountsByShard[$id] = 0
        $shards.Add([pscustomobject]@{ Index = $shards.Count; Id = $id; Lane = "headless"; LaneIndex = $index; TargetCount = 0 })
    }
    for ($index = 0; $index -lt $NativeShardCount; $index++) {
        $id = "native-$index"
        $targetCountsByShard[$id] = 0
        $shards.Add([pscustomobject]@{ Index = $shards.Count; Id = $id; Lane = "native"; LaneIndex = $index; TargetCount = 0 })
    }

    $laneOrdinals = @{ headless = 0; native = 0 }
    $targets = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $names.Count; $index++) {
        $nativeWindow = $groups[$index] -in @("native window", "native snapshot")
        $lane = if ($nativeWindow) { "native" } else { "headless" }
        $laneShardCount = if ($nativeWindow) { $NativeShardCount } else { $HeadlessShardCount }
        $laneIndex = [int]$laneOrdinals[$lane]
        $assignedShardIndex = $laneIndex % $laneShardCount
        $assignedShardId = "$lane-$assignedShardIndex"
        $localIndex = [int]$targetCountsByShard[$assignedShardId]
        $targets.Add([pscustomobject]@{
            TargetIndex = $index
            Name = [string]$names[$index]
            Group = [string]$groups[$index]
            NativeWindow = $nativeWindow
            ShardId = $assignedShardId
            LocalIndex = $localIndex
        })
        $targetCountsByShard[$assignedShardId] = $localIndex + 1
        $laneOrdinals[$lane] = $laneIndex + 1
    }
    foreach ($shard in $shards) {
        $shard.TargetCount = [int]$targetCountsByShard[$shard.Id]
        if ($shard.TargetCount -lt 1) {
            throw "Shard plan produced empty shard '$($shard.Id)'."
        }
    }

    $receiptLines = [System.Collections.Generic.List[string]]::new()
    $receiptLines.Add("version=godot-test-shard-plan-v1")
    $receiptLines.Add("source_head=$SourceHead")
    $receiptLines.Add("source_tree=$SourceTree")
    $receiptLines.Add("source_worktree_clean=1")
    $receiptLines.Add("source_status_digest=$SourceStatusDigest")
    $receiptLines.Add("source_snapshot=$SourceSnapshotDigest")
    $receiptLines.Add("runner_sha256=$RunnerSha256")
    $receiptLines.Add("suite_mode=$SuiteMode")
    $receiptLines.Add("algorithm=lane-round-robin-v1")
    $receiptLines.Add("headless_shard_count=$HeadlessShardCount")
    $receiptLines.Add("native_shard_count=$NativeShardCount")
    $receiptLines.Add("shard_count=$($shards.Count)")
    foreach ($shard in $shards) {
        $receiptLines.Add(("shard={0}|{1}|{2}|{3}|{4}" -f
            $shard.Index,
            (ConvertTo-TestRunReceiptField -Value $shard.Id),
            $shard.Lane,
            $shard.LaneIndex,
            $shard.TargetCount))
    }
    $receiptLines.Add("target_count=$($targets.Count)")
    foreach ($target in $targets) {
        $receiptLines.Add(("target={0}|{1}|{2}|{3}|{4}|{5}" -f
            $target.TargetIndex,
            (ConvertTo-TestRunReceiptField -Value $target.Name),
            (ConvertTo-TestRunReceiptField -Value $target.Group),
            $(if ($target.NativeWindow) { "1" } else { "0" }),
            (ConvertTo-TestRunReceiptField -Value $target.ShardId),
            $target.LocalIndex))
    }
    $canonicalReceipt = $receiptLines -join "`n"
    return [pscustomobject]@{
        Version = "godot-test-shard-plan-v1"
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonicalReceipt
        SourceHead = $SourceHead
        SourceTree = $SourceTree
        SourceWorktreeClean = $true
        SourceStatusDigest = $SourceStatusDigest
        SourceSnapshotDigest = $SourceSnapshotDigest
        RunnerSha256 = $RunnerSha256
        SuiteMode = $SuiteMode
        Algorithm = "lane-round-robin-v1"
        HeadlessShardCount = $HeadlessShardCount
        NativeShardCount = $NativeShardCount
        ShardCount = $shards.Count
        Shards = @($shards)
        TargetCount = $targets.Count
        Targets = @($targets)
        CanonicalReceipt = $canonicalReceipt
    }
}

function Read-GodotTestShardPlan {
    param([string]$PlanPath)

    $envelope = Read-GodotCanonicalEvidenceEnvelope -EvidencePath $PlanPath
    if ($envelope.Version -ne "godot-test-shard-plan-v1") {
        throw "Shard plan has unsupported version '$($envelope.Version)'."
    }
    $scalars = @{}
    $shardRecords = [System.Collections.Generic.List[object]]::new()
    $targetRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $envelope.BodyLines) {
        if ($line.StartsWith("shard=", [StringComparison]::Ordinal)) {
            $parts = @($line.Substring(6) -split '\|', 5)
            if ($parts.Count -ne 5 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or
                $parts[2] -notin @("headless", "native") -or
                $parts[3] -notmatch '^(0|[1-9][0-9]*)$' -or $parts[4] -notmatch '^[1-9][0-9]*$') {
                throw "Shard plan contains an invalid shard record."
            }
            $shardRecords.Add([pscustomobject]@{
                Index = [int]$parts[0]
                Id = ConvertFrom-TestRunReceiptField -Value $parts[1]
                Lane = $parts[2]
                LaneIndex = [int]$parts[3]
                TargetCount = [int]$parts[4]
            })
            continue
        }
        if ($line.StartsWith("target=", [StringComparison]::Ordinal)) {
            $parts = @($line.Substring(7) -split '\|', 6)
            if ($parts.Count -ne 6 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or
                $parts[3] -notin @("0", "1") -or $parts[5] -notmatch '^(0|[1-9][0-9]*)$') {
                throw "Shard plan contains an invalid target record."
            }
            $targetRecords.Add([pscustomobject]@{
                TargetIndex = [int]$parts[0]
                Name = ConvertFrom-TestRunReceiptField -Value $parts[1]
                Group = ConvertFrom-TestRunReceiptField -Value $parts[2]
                NativeWindow = $parts[3] -eq "1"
                ShardId = ConvertFrom-TestRunReceiptField -Value $parts[4]
                LocalIndex = [int]$parts[5]
            })
            continue
        }
        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            throw "Shard plan contains an invalid scalar record."
        }
        $key = $line.Substring(0, $separatorIndex)
        if ($scalars.ContainsKey($key)) {
            throw "Shard plan contains duplicate scalar key '$key'."
        }
        $scalars[$key] = $line.Substring($separatorIndex + 1)
    }
    $requiredKeys = @(
        "version", "source_head", "source_tree", "source_worktree_clean",
        "source_status_digest", "source_snapshot", "runner_sha256", "suite_mode",
        "algorithm", "headless_shard_count", "native_shard_count", "shard_count", "target_count"
    )
    if ($scalars.Count -ne $requiredKeys.Count -or
        @($requiredKeys | Where-Object { -not $scalars.ContainsKey($_) }).Count -gt 0 -or
        $scalars.version -ne "godot-test-shard-plan-v1" -or
        $scalars.source_worktree_clean -ne "1" -or
        $scalars.algorithm -ne "lane-round-robin-v1" -or
        $scalars.headless_shard_count -notmatch '^[1-9][0-9]*$' -or
        $scalars.native_shard_count -notmatch '^[1-9][0-9]*$' -or
        $scalars.shard_count -notmatch '^[1-9][0-9]*$' -or
        $scalars.target_count -notmatch '^[1-9][0-9]*$') {
        throw "Shard plan scalar key set or metadata is invalid."
    }
    if ([int]$scalars.shard_count -ne $shardRecords.Count -or [int]$scalars.target_count -ne $targetRecords.Count) {
        throw "Shard plan counts differ from its closed shard/target records."
    }
    $reconstructed = New-GodotTestShardPlan `
        -SourceHead $scalars.source_head `
        -SourceTree $scalars.source_tree `
        -SourceWorktreeClean $true `
        -SourceStatusDigest $scalars.source_status_digest `
        -SourceSnapshotDigest $scalars.source_snapshot `
        -RunnerSha256 $scalars.runner_sha256 `
        -SuiteMode $scalars.suite_mode `
        -HeadlessShardCount ([int]$scalars.headless_shard_count) `
        -NativeShardCount ([int]$scalars.native_shard_count) `
        -TargetNames @($targetRecords | ForEach-Object { [string]$_.Name }) `
        -TargetGroups @($targetRecords | ForEach-Object { [string]$_.Group })
    if ($reconstructed.Digest -ne $envelope.Digest -or $reconstructed.CanonicalReceipt -cne $envelope.CanonicalEvidence) {
        throw "Shard plan is not canonical or its lane assignment was changed."
    }
    return $reconstructed
}

function Assert-GodotTestShardPlanSourceBinding {
    param(
        [pscustomobject]$Plan,
        [pscustomobject]$CurrentIdentity,
        [pscustomobject]$CurrentSnapshot,
        [string]$CurrentRunnerSha256
    )

    if (-not $Plan.SourceWorktreeClean -or -not $CurrentIdentity.WorktreeClean) {
        throw "Shard plan is admissible only for a clean committed source."
    }
    if ($Plan.SourceHead -ne [string]$CurrentIdentity.HeadCommit -or
        $Plan.SourceTree -ne [string]$CurrentIdentity.HeadTree -or
        $Plan.SourceStatusDigest -ne [string]$CurrentIdentity.StatusDigest -or
        $Plan.SourceSnapshotDigest -ne [string]$CurrentSnapshot.Digest) {
        throw "Shard plan does not bind the exact current source HEAD/tree/status/snapshot."
    }
    if ($Plan.RunnerSha256 -ne $CurrentRunnerSha256) {
        throw "Shard plan runner SHA-256 does not match the executing runner."
    }
    return $Plan
}

function New-GodotTestShardReceipt {
    param(
        [string]$PlanDigest,
        [string]$ShardId,
        [string]$ShardLane,
        [string]$SourceHead,
        [string]$SourceTree,
        [bool]$SourceWorktreeClean,
        [string]$SourceStatusDigest,
        [string]$SourceSnapshotDigest,
        [string]$TestOverlayDigest,
        [string]$TestOverlayVersion,
        [string]$OverlayProjectBeforeSha256,
        [string]$OverlayProjectAfterSha256,
        [string]$OverlayRunId,
        [string]$OverlayUserDirectoryName,
        [string]$RunnerSha256,
        [string]$GodotVersion,
        [int]$DebugServerPort,
        [int]$DapPort,
        [int]$LspPort,
        [object[]]$Results
    )

    if ($PlanDigest -notmatch '^[0-9a-f]{64}$' -or
        $SourceHead -notmatch '^[0-9a-f]{40,64}$' -or $SourceTree -notmatch '^[0-9a-f]{40,64}$' -or
        $ShardId -notmatch '^(headless|native)-(0|[1-9][0-9]*)$' -or
        $ShardLane -notin @("headless", "native")) {
        throw "Shard receipt identity metadata is invalid."
    }
    if (-not $SourceWorktreeClean) {
        throw "Shard receipt requires a clean committed source."
    }
    foreach ($digest in @(
        $SourceStatusDigest, $SourceSnapshotDigest, $TestOverlayDigest,
        $OverlayProjectBeforeSha256, $OverlayProjectAfterSha256, $RunnerSha256
    )) {
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw "Shard receipt requires lowercase SHA-256 digests."
        }
    }
    if ($TestOverlayVersion -ne "godot-test-overlay-v1" -or
        [string]::IsNullOrWhiteSpace($OverlayRunId) -or
        [string]::IsNullOrWhiteSpace($OverlayUserDirectoryName) -or
        [string]::IsNullOrWhiteSpace($GodotVersion)) {
        throw "Shard receipt overlay/Godot metadata cannot be empty."
    }
    $expectedLane = $ShardId.Substring(0, $ShardId.IndexOf('-'))
    if ($expectedLane -ne $ShardLane) {
        throw "Shard receipt ID does not belong to its declared lane."
    }
    $ports = @($DebugServerPort, $DapPort, $LspPort)
    if (@($ports | Where-Object { $_ -lt 1 -or $_ -gt 65535 }).Count -gt 0 -or
        @($ports | Select-Object -Unique).Count -ne 3) {
        throw "Shard receipt requires three distinct valid Godot service ports."
    }
    $overlayCanonicalReceipt = @(
        "version=$TestOverlayVersion",
        "source_snapshot=$SourceSnapshotDigest",
        "path=project.godot",
        "before=$OverlayProjectBeforeSha256",
        "after=$OverlayProjectAfterSha256",
        "run_id=$OverlayRunId",
        "user_directory=$OverlayUserDirectoryName"
    ) -join "`n"
    if ((Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $overlayCanonicalReceipt) -ne $TestOverlayDigest) {
        throw "Shard receipt overlay metadata does not match the overlay digest."
    }

    $orderedResults = @($Results)
    if ($orderedResults.Count -lt 1) {
        throw "Shard receipt cannot be empty."
    }
    $targetIndexSet = [System.Collections.Generic.HashSet[int]]::new()
    $targetRunIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $orderedResults.Count; $index++) {
        $result = $orderedResults[$index]
        $isNative = [bool]$result.NativeWindow
        if ([int]$result.LocalIndex -ne $index -or [int]$result.TargetIndex -lt 0 -or
            -not $targetIndexSet.Add([int]$result.TargetIndex) -or
            [string]::IsNullOrWhiteSpace([string]$result.Name) -or
            [string]$result.Group -notin @("headless script", "headless flow", "native window", "native snapshot") -or
            [string]$result.Status -notin @("PASS", "FAIL", "SKIP")) {
            throw "Shard receipt contains invalid or unordered target metadata."
        }
        if (($ShardLane -eq "native") -ne $isNative -or
            ($isNative -ne ([string]$result.Group -in @("native window", "native snapshot")))) {
            throw "Shard receipt contains a target assigned to the wrong lane."
        }
        if ([string]$result.Status -eq "PASS" -and
            ([int]$result.ExitCode -ne 0 -or [bool]$result.BlockingFailure)) {
            throw "A PASS shard target must have exit code 0 and no blocking failure."
        }
        if ([string]$result.Status -in @("FAIL", "SKIP") -and -not [bool]$result.BlockingFailure) {
            throw "A failed or skipped required shard target must be blocking."
        }
        [void](Assert-TrustedTargetEvidence -Result $result)
        if (-not $targetRunIds.Add([string]$result.RunId)) {
            throw "Every shard target must use a distinct isolated run ID."
        }
    }
    $passCount = @($orderedResults | Where-Object Status -eq "PASS").Count
    $failCount = @($orderedResults | Where-Object Status -eq "FAIL").Count
    $skipCount = @($orderedResults | Where-Object Status -eq "SKIP").Count
    $blockingCount = @($orderedResults | Where-Object BlockingFailure).Count
    $overall = if ($blockingCount -eq 0) { "PASS" } else { "FAIL" }

    $receiptLines = [System.Collections.Generic.List[string]]::new()
    $receiptLines.Add("version=godot-test-shard-receipt-v2")
    $receiptLines.Add("plan_sha256=$PlanDigest")
    $receiptLines.Add("shard_id=$(ConvertTo-TestRunReceiptField -Value $ShardId)")
    $receiptLines.Add("shard_lane=$ShardLane")
    $receiptLines.Add("source_head=$SourceHead")
    $receiptLines.Add("source_tree=$SourceTree")
    $receiptLines.Add("source_worktree_clean=1")
    $receiptLines.Add("source_status_digest=$SourceStatusDigest")
    $receiptLines.Add("source_snapshot=$SourceSnapshotDigest")
    $receiptLines.Add("test_overlay=$TestOverlayDigest")
    $receiptLines.Add("overlay_version=$TestOverlayVersion")
    $receiptLines.Add("overlay_project_before=$OverlayProjectBeforeSha256")
    $receiptLines.Add("overlay_project_after=$OverlayProjectAfterSha256")
    $receiptLines.Add("overlay_run_id=$(ConvertTo-TestRunReceiptField -Value $OverlayRunId)")
    $receiptLines.Add("overlay_user_directory=$(ConvertTo-TestRunReceiptField -Value $OverlayUserDirectoryName)")
    $receiptLines.Add("structure_overlay=none")
    $receiptLines.Add("structure_overlay_version=none")
    $receiptLines.Add("runner_sha256=$RunnerSha256")
    $receiptLines.Add("godot_version=$(ConvertTo-TestRunReceiptField -Value $GodotVersion)")
    $receiptLines.Add("suite_mode=shard")
    $receiptLines.Add("import=PASS")
    $receiptLines.Add("godot_service_port_scope=import-and-tests")
    $receiptLines.Add("debug_server_port=$DebugServerPort")
    $receiptLines.Add("dap_port=$DapPort")
    $receiptLines.Add("lsp_port=$LspPort")
    $receiptLines.Add("native_skip_policy=blocking")
    $receiptLines.Add("target_count=$($orderedResults.Count)")
    foreach ($result in $orderedResults) {
        $receiptLines.Add(("target={0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}" -f
            ([int]$result.TargetIndex),
            ([int]$result.LocalIndex),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.Name)),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.Group)),
            $(if ([bool]$result.NativeWindow) { "1" } else { "0" }),
            ([string]$result.Status),
            ([int]$result.ExitCode),
            $(if ([bool]$result.BlockingFailure) { "1" } else { "0" }),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.RunId)),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.UserDirectoryName)),
            ([string]$result.InputBeforeDigest),
            ([string]$result.InputAfterDigest),
            ([string]$result.InvocationDigest),
            ([string]$result.OutputDigest),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.CompletionVersion)),
            ([string]$result.CompletionDigest),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.TargetOverlayVersion)),
            ([string]$result.TargetOverlayDigest)))
    }
    $receiptLines.Add("pass=$passCount")
    $receiptLines.Add("fail=$failCount")
    $receiptLines.Add("skip=$skipCount")
    $receiptLines.Add("blocking=$blockingCount")
    $receiptLines.Add("overall=$overall")
    $canonicalReceipt = $receiptLines -join "`n"
    return [pscustomobject]@{
        Version = "godot-test-shard-receipt-v2"
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonicalReceipt
        PlanDigest = $PlanDigest
        ShardId = $ShardId
        ShardLane = $ShardLane
        SourceHead = $SourceHead
        SourceTree = $SourceTree
        SourceWorktreeClean = $true
        SourceStatusDigest = $SourceStatusDigest
        SourceSnapshotDigest = $SourceSnapshotDigest
        TestOverlayDigest = $TestOverlayDigest
        TestOverlayVersion = $TestOverlayVersion
        OverlayProjectBeforeSha256 = $OverlayProjectBeforeSha256
        OverlayProjectAfterSha256 = $OverlayProjectAfterSha256
        OverlayRunId = $OverlayRunId
        OverlayUserDirectoryName = $OverlayUserDirectoryName
        StructureOverlayVersion = "none"
        StructureOverlayDigest = "none"
        RunnerSha256 = $RunnerSha256
        GodotVersion = $GodotVersion
        SuiteMode = "shard"
        NativeSkipPolicy = "blocking"
        DebugServerPort = $DebugServerPort
        DapPort = $DapPort
        LspPort = $LspPort
        TargetCount = $orderedResults.Count
        PassCount = $passCount
        FailCount = $failCount
        SkipCount = $skipCount
        BlockingFailureCount = $blockingCount
        Overall = $overall
        Results = @($orderedResults)
        CanonicalReceipt = $canonicalReceipt
    }
}

function Read-GodotTestShardReceipt {
    param([string]$ReceiptPath)

    $envelope = Read-GodotCanonicalEvidenceEnvelope -EvidencePath $ReceiptPath
    if ($envelope.Version -ne "godot-test-shard-receipt-v2") {
        throw "Shard receipt has unsupported version '$($envelope.Version)'."
    }
    $scalars = @{}
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $envelope.BodyLines) {
        if ($line.StartsWith("target=", [StringComparison]::Ordinal)) {
            $parts = @($line.Substring(7) -split '\|', 18)
            if ($parts.Count -ne 18 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or
                $parts[1] -notmatch '^(0|[1-9][0-9]*)$' -or $parts[4] -notin @("0", "1") -or
                $parts[5] -notin @("PASS", "FAIL", "SKIP") -or
                $parts[6] -notmatch '^-?(0|[1-9][0-9]*)$' -or $parts[7] -notin @("0", "1") -or
                @($parts[10..13] + @($parts[15], $parts[17]) | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
                throw "Shard receipt contains an invalid target record."
            }
            $targets.Add([pscustomobject]@{
                TargetIndex = [int]$parts[0]
                LocalIndex = [int]$parts[1]
                Name = ConvertFrom-TestRunReceiptField -Value $parts[2]
                Group = ConvertFrom-TestRunReceiptField -Value $parts[3]
                NativeWindow = $parts[4] -eq "1"
                Status = $parts[5]
                ExitCode = [int]$parts[6]
                BlockingFailure = $parts[7] -eq "1"
                RunId = ConvertFrom-TestRunReceiptField -Value $parts[8]
                UserDirectoryName = ConvertFrom-TestRunReceiptField -Value $parts[9]
                InputBeforeDigest = $parts[10]
                InputAfterDigest = $parts[11]
                InvocationDigest = $parts[12]
                OutputDigest = $parts[13]
                CompletionVersion = ConvertFrom-TestRunReceiptField -Value $parts[14]
                CompletionDigest = $parts[15]
                TargetOverlayVersion = ConvertFrom-TestRunReceiptField -Value $parts[16]
                TargetOverlayDigest = $parts[17]
            })
            continue
        }
        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) { throw "Shard receipt contains an invalid scalar record." }
        $key = $line.Substring(0, $separatorIndex)
        if ($scalars.ContainsKey($key)) { throw "Shard receipt contains duplicate scalar key '$key'." }
        $scalars[$key] = $line.Substring($separatorIndex + 1)
    }
    $requiredKeys = @(
        "version", "plan_sha256", "shard_id", "shard_lane", "source_head", "source_tree",
        "source_worktree_clean", "source_status_digest", "source_snapshot", "test_overlay",
        "overlay_version", "overlay_project_before", "overlay_project_after", "overlay_run_id",
        "overlay_user_directory", "structure_overlay", "structure_overlay_version", "runner_sha256",
        "godot_version", "suite_mode", "import", "godot_service_port_scope", "debug_server_port",
        "dap_port", "lsp_port", "native_skip_policy", "target_count", "pass", "fail", "skip",
        "blocking", "overall"
    )
    if ($scalars.Count -ne $requiredKeys.Count -or
        @($requiredKeys | Where-Object { -not $scalars.ContainsKey($_) }).Count -gt 0 -or
        $scalars.version -ne "godot-test-shard-receipt-v2" -or $scalars.source_worktree_clean -ne "1" -or
        $scalars.structure_overlay -ne "none" -or $scalars.structure_overlay_version -ne "none" -or
        $scalars.suite_mode -ne "shard" -or $scalars.import -ne "PASS" -or
        $scalars.godot_service_port_scope -ne "import-and-tests" -or
        $scalars.native_skip_policy -ne "blocking" -or $scalars.target_count -notmatch '^[1-9][0-9]*$' -or
        [int]$scalars.target_count -ne $targets.Count) {
        throw "Shard receipt scalar key set, import, overlay or target count is invalid."
    }
    $reconstructed = New-GodotTestShardReceipt `
        -PlanDigest $scalars.plan_sha256 `
        -ShardId (ConvertFrom-TestRunReceiptField -Value $scalars.shard_id) `
        -ShardLane $scalars.shard_lane `
        -SourceHead $scalars.source_head `
        -SourceTree $scalars.source_tree `
        -SourceWorktreeClean $true `
        -SourceStatusDigest $scalars.source_status_digest `
        -SourceSnapshotDigest $scalars.source_snapshot `
        -TestOverlayDigest $scalars.test_overlay `
        -TestOverlayVersion $scalars.overlay_version `
        -OverlayProjectBeforeSha256 $scalars.overlay_project_before `
        -OverlayProjectAfterSha256 $scalars.overlay_project_after `
        -OverlayRunId (ConvertFrom-TestRunReceiptField -Value $scalars.overlay_run_id) `
        -OverlayUserDirectoryName (ConvertFrom-TestRunReceiptField -Value $scalars.overlay_user_directory) `
        -RunnerSha256 $scalars.runner_sha256 `
        -GodotVersion (ConvertFrom-TestRunReceiptField -Value $scalars.godot_version) `
        -DebugServerPort ([int]$scalars.debug_server_port) `
        -DapPort ([int]$scalars.dap_port) `
        -LspPort ([int]$scalars.lsp_port) `
        -Results @($targets)
    if ($reconstructed.Digest -ne $envelope.Digest -or $reconstructed.CanonicalReceipt -cne $envelope.CanonicalEvidence) {
        throw "Shard receipt is not canonical or has inconsistent summaries."
    }
    return $reconstructed
}

function New-GodotTestAggregateReceipt {
    param(
        [string]$PlanDigest,
        [string]$SourceHead,
        [string]$SourceTree,
        [bool]$SourceWorktreeClean,
        [string]$SourceStatusDigest,
        [string]$SourceSnapshotDigest,
        [string]$OverlayProjectBeforeSha256,
        [string]$RunnerSha256,
        [string]$GodotVersion,
        [string]$SuiteMode,
        [object[]]$ShardRecords,
        [object[]]$Results
    )

    if ($PlanDigest -notmatch '^[0-9a-f]{64}$' -or
        $SourceHead -notmatch '^[0-9a-f]{40,64}$' -or $SourceTree -notmatch '^[0-9a-f]{40,64}$' -or
        -not $SourceWorktreeClean -or $SuiteMode -notin @("full", "full-with-snapshots") -or
        [string]::IsNullOrWhiteSpace($GodotVersion)) {
        throw "Aggregate receipt identity/suite metadata is invalid."
    }
    foreach ($digest in @($SourceStatusDigest, $SourceSnapshotDigest, $OverlayProjectBeforeSha256, $RunnerSha256)) {
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw "Aggregate receipt requires lowercase SHA-256 digests."
        }
    }
    $orderedShards = @($ShardRecords)
    $orderedResults = @($Results)
    if ($orderedShards.Count -lt 2 -or $orderedResults.Count -lt 1) {
        throw "Aggregate receipt requires at least two shards and one target."
    }
    $shardIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $orderedShards.Count; $index++) {
        $shard = $orderedShards[$index]
        if ([int]$shard.Index -ne $index -or [string]$shard.Id -notmatch '^(headless|native)-(0|[1-9][0-9]*)$' -or
            -not $shardIds.Add([string]$shard.Id) -or [string]$shard.Digest -notmatch '^[0-9a-f]{64}$') {
            throw "Aggregate receipt contains invalid or unordered shard metadata."
        }
    }
    $targetRunIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $orderedResults.Count; $index++) {
        $result = $orderedResults[$index]
        if ([int]$result.TargetIndex -ne $index -or
            [string]::IsNullOrWhiteSpace([string]$result.Name) -or
            [string]$result.Group -notin @("headless script", "headless flow", "native window", "native snapshot") -or
            ([bool]$result.NativeWindow -ne ([string]$result.Group -in @("native window", "native snapshot"))) -or
            [string]$result.Status -ne "PASS" -or [int]$result.ExitCode -ne 0 -or [bool]$result.BlockingFailure) {
            throw "Aggregate receipt requires the exact ordered zero-failure, zero-skip target union."
        }
        [void](Assert-TrustedTargetEvidence -Result $result)
        if (-not $targetRunIds.Add([string]$result.RunId)) {
            throw "Aggregate target run IDs must be globally unique."
        }
    }

    $receiptLines = [System.Collections.Generic.List[string]]::new()
    $receiptLines.Add("version=godot-test-aggregate-receipt-v2")
    $receiptLines.Add("plan_sha256=$PlanDigest")
    $receiptLines.Add("source_head=$SourceHead")
    $receiptLines.Add("source_tree=$SourceTree")
    $receiptLines.Add("source_worktree_clean=1")
    $receiptLines.Add("source_status_digest=$SourceStatusDigest")
    $receiptLines.Add("source_snapshot=$SourceSnapshotDigest")
    $receiptLines.Add("overlay_project_before=$OverlayProjectBeforeSha256")
    $receiptLines.Add("runner_sha256=$RunnerSha256")
    $receiptLines.Add("godot_version=$(ConvertTo-TestRunReceiptField -Value $GodotVersion)")
    $receiptLines.Add("suite_mode=$SuiteMode")
    $receiptLines.Add("import=PASS")
    $receiptLines.Add("native_skip_policy=blocking")
    $receiptLines.Add("shard_count=$($orderedShards.Count)")
    foreach ($shard in $orderedShards) {
        $receiptLines.Add(("shard={0}|{1}|{2}" -f
            ([int]$shard.Index),
            (ConvertTo-TestRunReceiptField -Value ([string]$shard.Id)),
            ([string]$shard.Digest)))
    }
    $receiptLines.Add("target_count=$($orderedResults.Count)")
    foreach ($result in $orderedResults) {
        $receiptLines.Add(("target={0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}" -f
            ([int]$result.TargetIndex),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.Name)),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.Group)),
            $(if ([bool]$result.NativeWindow) { "1" } else { "0" }),
            ([string]$result.Status),
            ([int]$result.ExitCode),
            $(if ([bool]$result.BlockingFailure) { "1" } else { "0" }),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.RunId)),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.UserDirectoryName)),
            ([string]$result.InputBeforeDigest),
            ([string]$result.InputAfterDigest),
            ([string]$result.InvocationDigest),
            ([string]$result.OutputDigest),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.CompletionVersion)),
            ([string]$result.CompletionDigest),
            (ConvertTo-TestRunReceiptField -Value ([string]$result.TargetOverlayVersion)),
            ([string]$result.TargetOverlayDigest)))
    }
    $receiptLines.Add("pass=$($orderedResults.Count)")
    $receiptLines.Add("fail=0")
    $receiptLines.Add("skip=0")
    $receiptLines.Add("blocking=0")
    $receiptLines.Add("overall=PASS")
    $canonicalReceipt = $receiptLines -join "`n"
    return [pscustomobject]@{
        Version = "godot-test-aggregate-receipt-v2"
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonicalReceipt
        PlanDigest = $PlanDigest
        SourceHead = $SourceHead
        SourceTree = $SourceTree
        SourceWorktreeClean = $true
        SourceStatusDigest = $SourceStatusDigest
        SourceSnapshotDigest = $SourceSnapshotDigest
        OverlayProjectBeforeSha256 = $OverlayProjectBeforeSha256
        RunnerSha256 = $RunnerSha256
        GodotVersion = $GodotVersion
        SuiteMode = $SuiteMode
        NativeSkipPolicy = "blocking"
        ShardCount = $orderedShards.Count
        Shards = @($orderedShards)
        TargetCount = $orderedResults.Count
        PassCount = $orderedResults.Count
        FailCount = 0
        SkipCount = 0
        BlockingFailureCount = 0
        Overall = "PASS"
        Results = @($orderedResults)
        CanonicalReceipt = $canonicalReceipt
    }
}

function Merge-GodotTestShardReceipts {
    param(
        [pscustomobject]$Plan,
        [object[]]$ShardReceipts
    )

    if ($Plan.Version -ne "godot-test-shard-plan-v1") {
        throw "Aggregate input is not a canonical shard plan."
    }
    $receipts = @($ShardReceipts)
    if ($receipts.Count -ne $Plan.ShardCount) {
        throw "Aggregate requires exactly one receipt for every planned shard."
    }
    $receiptsById = @{}
    foreach ($receipt in $receipts) {
        if ($receipt.Version -ne "godot-test-shard-receipt-v2" -or
            $receiptsById.ContainsKey([string]$receipt.ShardId)) {
            throw "Aggregate contains an unknown or duplicate shard receipt."
        }
        $receiptsById[[string]$receipt.ShardId] = $receipt
    }
    $orderedShardRecords = [System.Collections.Generic.List[object]]::new()
    $globalResults = [System.Collections.Generic.List[object]]::new()
    $godotVersion = $null
    $projectBefore = $null
    foreach ($plannedShard in $Plan.Shards) {
        if (-not $receiptsById.ContainsKey([string]$plannedShard.Id)) {
            throw "Aggregate is missing planned shard '$($plannedShard.Id)'."
        }
        $receipt = $receiptsById[[string]$plannedShard.Id]
        if ($receipt.PlanDigest -ne $Plan.Digest -or $receipt.ShardLane -ne $plannedShard.Lane -or
            $receipt.SourceHead -ne $Plan.SourceHead -or $receipt.SourceTree -ne $Plan.SourceTree -or
            -not $receipt.SourceWorktreeClean -or $receipt.SourceStatusDigest -ne $Plan.SourceStatusDigest -or
            $receipt.SourceSnapshotDigest -ne $Plan.SourceSnapshotDigest -or $receipt.RunnerSha256 -ne $Plan.RunnerSha256 -or
            $receipt.StructureOverlayVersion -ne "none" -or $receipt.NativeSkipPolicy -ne "blocking" -or
            $receipt.Overall -ne "PASS" -or $receipt.FailCount -ne 0 -or $receipt.SkipCount -ne 0 -or
            $receipt.BlockingFailureCount -ne 0) {
            throw "Shard '$($plannedShard.Id)' is not exact zero-failure evidence for this plan."
        }
        if ($null -eq $godotVersion) {
            $godotVersion = [string]$receipt.GodotVersion
            $projectBefore = [string]$receipt.OverlayProjectBeforeSha256
        }
        elseif ([string]$receipt.GodotVersion -cne $godotVersion -or
            [string]$receipt.OverlayProjectBeforeSha256 -ne $projectBefore) {
            throw "Shard receipts do not bind the same Godot version and source project.godot."
        }
        $expectedTargets = @($Plan.Targets | Where-Object ShardId -ceq $plannedShard.Id | Sort-Object LocalIndex)
        if ($receipt.TargetCount -ne $expectedTargets.Count -or $receipt.Results.Count -ne $expectedTargets.Count) {
            throw "Shard '$($plannedShard.Id)' target count differs from its plan assignment."
        }
        for ($index = 0; $index -lt $expectedTargets.Count; $index++) {
            $expected = $expectedTargets[$index]
            $actual = $receipt.Results[$index]
            if ([int]$actual.TargetIndex -ne [int]$expected.TargetIndex -or
                [int]$actual.LocalIndex -ne [int]$expected.LocalIndex -or
                [string]$actual.Name -cne [string]$expected.Name -or
                [string]$actual.Group -cne [string]$expected.Group -or
                [bool]$actual.NativeWindow -ne [bool]$expected.NativeWindow -or
                [string]$actual.Status -ne "PASS" -or [int]$actual.ExitCode -ne 0 -or [bool]$actual.BlockingFailure) {
                throw "Shard '$($plannedShard.Id)' changed, reordered, skipped or failed a planned target."
            }
            $globalResults.Add([pscustomobject]@{
                TargetIndex = [int]$actual.TargetIndex
                Name = [string]$actual.Name
                Group = [string]$actual.Group
                NativeWindow = [bool]$actual.NativeWindow
                Status = "PASS"
                ExitCode = 0
                BlockingFailure = $false
                RunId = [string]$actual.RunId
                UserDirectoryName = [string]$actual.UserDirectoryName
                InputBeforeDigest = [string]$actual.InputBeforeDigest
                InputAfterDigest = [string]$actual.InputAfterDigest
                InvocationDigest = [string]$actual.InvocationDigest
                OutputDigest = [string]$actual.OutputDigest
                CompletionVersion = [string]$actual.CompletionVersion
                CompletionDigest = [string]$actual.CompletionDigest
                TargetOverlayVersion = [string]$actual.TargetOverlayVersion
                TargetOverlayDigest = [string]$actual.TargetOverlayDigest
            })
        }
        $orderedShardRecords.Add([pscustomobject]@{
            Index = [int]$plannedShard.Index
            Id = [string]$plannedShard.Id
            Digest = [string]$receipt.Digest
        })
    }
    $orderedGlobalResults = @($globalResults | Sort-Object TargetIndex)
    if ($orderedGlobalResults.Count -ne $Plan.TargetCount) {
        throw "Aggregate shard union is missing or duplicates planned targets."
    }
    for ($index = 0; $index -lt $Plan.TargetCount; $index++) {
        $plannedTarget = $Plan.Targets[$index]
        $actualTarget = $orderedGlobalResults[$index]
        if ([int]$actualTarget.TargetIndex -ne $index -or
            [string]$actualTarget.Name -cne [string]$plannedTarget.Name -or
            [string]$actualTarget.Group -cne [string]$plannedTarget.Group -or
            [bool]$actualTarget.NativeWindow -ne [bool]$plannedTarget.NativeWindow) {
            throw "Aggregate shard union is not the plan's exact global target order."
        }
    }
    return New-GodotTestAggregateReceipt `
        -PlanDigest $Plan.Digest `
        -SourceHead $Plan.SourceHead `
        -SourceTree $Plan.SourceTree `
        -SourceWorktreeClean $true `
        -SourceStatusDigest $Plan.SourceStatusDigest `
        -SourceSnapshotDigest $Plan.SourceSnapshotDigest `
        -OverlayProjectBeforeSha256 $projectBefore `
        -RunnerSha256 $Plan.RunnerSha256 `
        -GodotVersion $godotVersion `
        -SuiteMode $Plan.SuiteMode `
        -ShardRecords @($orderedShardRecords) `
        -Results @($orderedGlobalResults)
}

function Read-GodotTestAggregateReceipt {
    param([string]$ReceiptPath)

    $envelope = Read-GodotCanonicalEvidenceEnvelope -EvidencePath $ReceiptPath
    if ($envelope.Version -ne "godot-test-aggregate-receipt-v2") {
        throw "Aggregate receipt has unsupported version '$($envelope.Version)'."
    }
    $scalars = @{}
    $shards = [System.Collections.Generic.List[object]]::new()
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $envelope.BodyLines) {
        if ($line.StartsWith("shard=", [StringComparison]::Ordinal)) {
            $parts = @($line.Substring(6) -split '\|', 3)
            if ($parts.Count -ne 3 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or $parts[2] -notmatch '^[0-9a-f]{64}$') {
                throw "Aggregate receipt contains an invalid shard record."
            }
            $shards.Add([pscustomobject]@{
                Index = [int]$parts[0]
                Id = ConvertFrom-TestRunReceiptField -Value $parts[1]
                Digest = $parts[2]
            })
            continue
        }
        if ($line.StartsWith("target=", [StringComparison]::Ordinal)) {
            $parts = @($line.Substring(7) -split '\|', 17)
            if ($parts.Count -ne 17 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or
                $parts[3] -notin @("0", "1") -or $parts[4] -notin @("PASS", "FAIL", "SKIP") -or
                $parts[5] -notmatch '^-?(0|[1-9][0-9]*)$' -or $parts[6] -notin @("0", "1") -or
                @($parts[9..12] + @($parts[14], $parts[16]) | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
                throw "Aggregate receipt contains an invalid target record."
            }
            $targets.Add([pscustomobject]@{
                TargetIndex = [int]$parts[0]
                Name = ConvertFrom-TestRunReceiptField -Value $parts[1]
                Group = ConvertFrom-TestRunReceiptField -Value $parts[2]
                NativeWindow = $parts[3] -eq "1"
                Status = $parts[4]
                ExitCode = [int]$parts[5]
                BlockingFailure = $parts[6] -eq "1"
                RunId = ConvertFrom-TestRunReceiptField -Value $parts[7]
                UserDirectoryName = ConvertFrom-TestRunReceiptField -Value $parts[8]
                InputBeforeDigest = $parts[9]
                InputAfterDigest = $parts[10]
                InvocationDigest = $parts[11]
                OutputDigest = $parts[12]
                CompletionVersion = ConvertFrom-TestRunReceiptField -Value $parts[13]
                CompletionDigest = $parts[14]
                TargetOverlayVersion = ConvertFrom-TestRunReceiptField -Value $parts[15]
                TargetOverlayDigest = $parts[16]
            })
            continue
        }
        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) { throw "Aggregate receipt contains an invalid scalar record." }
        $key = $line.Substring(0, $separatorIndex)
        if ($scalars.ContainsKey($key)) { throw "Aggregate receipt contains duplicate scalar key '$key'." }
        $scalars[$key] = $line.Substring($separatorIndex + 1)
    }
    $requiredKeys = @(
        "version", "plan_sha256", "source_head", "source_tree", "source_worktree_clean",
        "source_status_digest", "source_snapshot", "overlay_project_before", "runner_sha256",
        "godot_version", "suite_mode", "import", "native_skip_policy", "shard_count", "target_count",
        "pass", "fail", "skip", "blocking", "overall"
    )
    if ($scalars.Count -ne $requiredKeys.Count -or
        @($requiredKeys | Where-Object { -not $scalars.ContainsKey($_) }).Count -gt 0 -or
        $scalars.version -ne "godot-test-aggregate-receipt-v2" -or $scalars.source_worktree_clean -ne "1" -or
        $scalars.import -ne "PASS" -or $scalars.native_skip_policy -ne "blocking" -or
        $scalars.shard_count -notmatch '^[1-9][0-9]*$' -or $scalars.target_count -notmatch '^[1-9][0-9]*$' -or
        [int]$scalars.shard_count -ne $shards.Count -or [int]$scalars.target_count -ne $targets.Count -or
        $scalars.pass -ne [string]$targets.Count -or $scalars.fail -ne "0" -or $scalars.skip -ne "0" -or
        $scalars.blocking -ne "0" -or $scalars.overall -ne "PASS") {
        throw "Aggregate receipt scalar key set, import or summaries are invalid."
    }
    $reconstructed = New-GodotTestAggregateReceipt `
        -PlanDigest $scalars.plan_sha256 `
        -SourceHead $scalars.source_head `
        -SourceTree $scalars.source_tree `
        -SourceWorktreeClean $true `
        -SourceStatusDigest $scalars.source_status_digest `
        -SourceSnapshotDigest $scalars.source_snapshot `
        -OverlayProjectBeforeSha256 $scalars.overlay_project_before `
        -RunnerSha256 $scalars.runner_sha256 `
        -GodotVersion (ConvertFrom-TestRunReceiptField -Value $scalars.godot_version) `
        -SuiteMode $scalars.suite_mode `
        -ShardRecords @($shards) `
        -Results @($targets)
    if ($reconstructed.Digest -ne $envelope.Digest -or $reconstructed.CanonicalReceipt -cne $envelope.CanonicalEvidence) {
        throw "Aggregate receipt is not canonical or has inconsistent summaries."
    }
    return $reconstructed
}

function Assert-GodotTestAggregateReceiptBinding {
    param(
        [pscustomobject]$Receipt,
        [pscustomobject]$CandidateReceipt,
        [pscustomobject]$CurrentIdentity,
        [pscustomobject]$CurrentSnapshot,
        [string]$CurrentRunnerSha256,
        [string[]]$ExpectedTargets
    )

    if ($CandidateReceipt.status -ne "PUBLICATION_READY" -or [int]$CandidateReceipt.schema_version -ne 1) {
        throw "Candidate publication receipt is not schema 1 PUBLICATION_READY."
    }
    if ($Receipt.Version -ne "godot-test-aggregate-receipt-v2" -or
        -not $Receipt.SourceWorktreeClean -or -not $CurrentIdentity.WorktreeClean) {
        throw "Only a clean canonical aggregate receipt is admissible as sharded full-suite evidence."
    }
    if ($Receipt.SourceHead -ne [string]$CandidateReceipt.head -or
        $Receipt.SourceTree -ne [string]$CandidateReceipt.tree -or
        $Receipt.SourceHead -ne [string]$CurrentIdentity.HeadCommit -or
        $Receipt.SourceTree -ne [string]$CurrentIdentity.HeadTree -or
        $Receipt.SourceStatusDigest -ne [string]$CurrentIdentity.StatusDigest -or
        $Receipt.SourceSnapshotDigest -ne [string]$CurrentSnapshot.Digest) {
        throw "Aggregate receipt, candidate receipt and current source binding do not match."
    }
    if ($Receipt.RunnerSha256 -ne $CurrentRunnerSha256) {
        throw "Aggregate receipt runner SHA-256 does not match the candidate runner."
    }
    $projectEntries = @($CurrentSnapshot.Entries | Where-Object RelativePath -ceq "project.godot")
    if ($projectEntries.Count -ne 1 -or -not $projectEntries[0].Exists -or
        $Receipt.OverlayProjectBeforeSha256 -ne [string]$projectEntries[0].Sha256) {
        throw "Aggregate shard overlays are not based on candidate project.godot."
    }
    if ($Receipt.SuiteMode -notin @("full", "full-with-snapshots") -or
        $Receipt.NativeSkipPolicy -ne "blocking" -or $Receipt.ShardCount -lt 2 -or
        $Receipt.Overall -ne "PASS" -or $Receipt.FailCount -ne 0 -or $Receipt.SkipCount -ne 0 -or
        $Receipt.BlockingFailureCount -ne 0 -or $Receipt.TargetCount -lt 1 -or
        @($Receipt.Results | Where-Object { $_.Status -ne "PASS" -or $_.ExitCode -ne 0 -or $_.BlockingFailure }).Count -gt 0) {
        throw "Aggregate receipt is not a zero-failure, zero-skip required full-suite PASS."
    }
    $actualTargets = @($Receipt.Results | ForEach-Object { [string]$_.Name })
    if ($actualTargets.Count -ne $ExpectedTargets.Count -or
        [string]::Join("`n", $actualTargets) -cne [string]::Join("`n", @($ExpectedTargets))) {
        throw "Aggregate receipt target union is not the candidate runner's closed full-suite manifest."
    }
    return $Receipt
}

function Read-GodotCandidateRunEvidence {
    param([string]$ReceiptPath)

    $envelope = Read-GodotCanonicalEvidenceEnvelope -EvidencePath $ReceiptPath
    switch ($envelope.Version) {
        "godot-test-run-receipt-v2" { return Read-GodotTestRunReceipt -ReceiptPath $ReceiptPath }
        "godot-test-aggregate-receipt-v2" { return Read-GodotTestAggregateReceipt -ReceiptPath $ReceiptPath }
        "godot-test-shard-receipt-v2" { throw "An individual shard receipt cannot certify a full candidate; aggregate every planned shard first." }
        default { throw "Unsupported candidate run evidence version '$($envelope.Version)'." }
    }
}

function Read-GodotTestRunReceipt {
    param([string]$ReceiptPath)

    $resolvedPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ReceiptPath))
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Test run receipt does not exist: '$resolvedPath'."
    }
    $content = [System.IO.File]::ReadAllText($resolvedPath)
    if ($content.Contains("`r") -or -not $content.EndsWith("`n") -or $content.EndsWith("`n`n")) {
        throw "Test run receipt must use canonical LF lines and exactly one final newline."
    }
    $lines = @($content.Substring(0, $content.Length - 1).Split([char]"`n"))
    if ($lines.Count -lt 2 -or $lines[0] -notmatch '^canonical_sha256=([0-9a-f]{64})$') {
        throw "Test run receipt has no valid canonical_sha256 envelope."
    }
    $declaredDigest = $Matches[1]
    $canonicalReceipt = [string]::Join("`n", $lines[1..($lines.Count - 1)])
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalReceipt)
        $actualDigest = [System.BitConverter]::ToString($hasher.ComputeHash($receiptBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
    if ($actualDigest -ne $declaredDigest) {
        throw "Test run receipt canonical SHA-256 is invalid."
    }

    $scalarValues = @{}
    $targetRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line.StartsWith("target=", [StringComparison]::Ordinal)) {
            $parts = @($line.Substring(7) -split '\|', 16)
            if ($parts.Count -ne 16 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or
                $parts[3] -notin @("PASS", "FAIL", "SKIP") -or
                $parts[4] -notmatch '^-?(0|[1-9][0-9]*)$' -or
                $parts[5] -notin @("0", "1") -or
                @($parts[8..11] + @($parts[13], $parts[15]) | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
                throw "Test run receipt contains an invalid target record."
            }
            $targetRecords.Add([pscustomobject]@{
                Index = [int]$parts[0]
                Name = ConvertFrom-TestRunReceiptField -Value $parts[1]
                Group = ConvertFrom-TestRunReceiptField -Value $parts[2]
                Status = $parts[3]
                ExitCode = [int]$parts[4]
                BlockingFailure = $parts[5] -eq "1"
                RunId = ConvertFrom-TestRunReceiptField -Value $parts[6]
                UserDirectoryName = ConvertFrom-TestRunReceiptField -Value $parts[7]
                InputBeforeDigest = $parts[8]
                InputAfterDigest = $parts[9]
                InvocationDigest = $parts[10]
                OutputDigest = $parts[11]
                CompletionVersion = ConvertFrom-TestRunReceiptField -Value $parts[12]
                CompletionDigest = $parts[13]
                TargetOverlayVersion = ConvertFrom-TestRunReceiptField -Value $parts[14]
                TargetOverlayDigest = $parts[15]
            })
            continue
        }
        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 1) {
            throw "Test run receipt contains an invalid scalar record."
        }
        $key = $line.Substring(0, $separatorIndex)
        $value = $line.Substring($separatorIndex + 1)
        if ($scalarValues.ContainsKey($key)) {
            throw "Test run receipt contains duplicate scalar key '$key'."
        }
        $scalarValues[$key] = $value
    }
    $requiredScalarKeys = @(
        "version", "source_head", "source_tree", "source_worktree_clean",
        "source_status_digest", "source_snapshot", "test_overlay", "overlay_version",
        "overlay_project_before", "overlay_project_after", "overlay_run_id",
        "overlay_user_directory", "structure_overlay", "structure_overlay_version",
        "structure_overlay_id", "structure_overlay_file_count",
        "structure_overlay_content_digest", "structure_overlay_manifest",
        "runner_sha256", "godot_version", "suite_mode",
        "import", "godot_service_port_scope", "debug_server_port", "dap_port",
        "lsp_port", "native_skip_policy", "target_count", "pass", "fail", "skip",
        "blocking", "overall"
    )
    if ($scalarValues.Count -ne $requiredScalarKeys.Count -or
        @($requiredScalarKeys | Where-Object { -not $scalarValues.ContainsKey($_) }).Count -gt 0) {
        throw "Test run receipt scalar key set is not exact."
    }
    if ($scalarValues.version -ne "godot-test-run-receipt-v2" -or
        $scalarValues.import -ne "PASS" -or
        $scalarValues.godot_service_port_scope -ne "import-and-tests") {
        throw "Test run receipt version/import/port scope is invalid."
    }
    if ($scalarValues.source_worktree_clean -notin @("0", "1") -or
        $scalarValues.target_count -notmatch '^(0|[1-9][0-9]*)$') {
        throw "Test run receipt clean/target count field is invalid."
    }
    for ($index = 0; $index -lt $targetRecords.Count; $index++) {
        if ($targetRecords[$index].Index -ne $index) {
            throw "Test run receipt target indexes must be contiguous and ordered."
        }
    }
    if ([int]$scalarValues.target_count -ne $targetRecords.Count) {
        throw "Test run receipt target_count differs from its closed target list."
    }

    $reconstructed = New-GodotTestRunReceipt `
        -SourceHead $scalarValues.source_head `
        -SourceTree $scalarValues.source_tree `
        -SourceWorktreeClean ($scalarValues.source_worktree_clean -eq "1") `
        -SourceStatusDigest $scalarValues.source_status_digest `
        -SourceSnapshotDigest $scalarValues.source_snapshot `
        -TestOverlayDigest $scalarValues.test_overlay `
        -TestOverlayVersion $scalarValues.overlay_version `
        -OverlayProjectBeforeSha256 $scalarValues.overlay_project_before `
        -OverlayProjectAfterSha256 $scalarValues.overlay_project_after `
        -OverlayRunId (ConvertFrom-TestRunReceiptField -Value $scalarValues.overlay_run_id) `
        -OverlayUserDirectoryName (ConvertFrom-TestRunReceiptField -Value $scalarValues.overlay_user_directory) `
        -StructureOverlayVersion $scalarValues.structure_overlay_version `
        -StructureOverlayDigest $scalarValues.structure_overlay `
        -StructureOverlayId (ConvertFrom-TestRunReceiptField -Value $scalarValues.structure_overlay_id) `
        -StructureOverlayFileCount ([int]$scalarValues.structure_overlay_file_count) `
        -StructureOverlayContentDigest $scalarValues.structure_overlay_content_digest `
        -StructureOverlayManifest (ConvertFrom-TestRunReceiptField -Value $scalarValues.structure_overlay_manifest) `
        -RunnerSha256 $scalarValues.runner_sha256 `
        -GodotVersion (ConvertFrom-TestRunReceiptField -Value $scalarValues.godot_version) `
        -SuiteMode $scalarValues.suite_mode `
        -NativeSkipPolicy $scalarValues.native_skip_policy `
        -DebugServerPort ([int]$scalarValues.debug_server_port) `
        -DapPort ([int]$scalarValues.dap_port) `
        -LspPort ([int]$scalarValues.lsp_port) `
        -Results @($targetRecords)
    if ($reconstructed.Digest -ne $declaredDigest -or $reconstructed.CanonicalReceipt -cne $canonicalReceipt) {
        throw "Test run receipt is not in canonical schema order or has inconsistent summaries."
    }
    return $reconstructed
}

function Assert-GodotTestRunReceiptBinding {
    param(
        [pscustomobject]$Receipt,
        [pscustomobject]$CandidateReceipt,
        [pscustomobject]$CurrentIdentity,
        [pscustomobject]$CurrentSnapshot,
        [string]$CurrentRunnerSha256,
        [string[]]$ExpectedTargets
    )

    if ($CandidateReceipt.status -ne "PUBLICATION_READY" -or
        [int]$CandidateReceipt.schema_version -ne 1) {
        throw "Candidate publication receipt is not schema 1 PUBLICATION_READY."
    }
    if (-not $Receipt.SourceWorktreeClean -or -not $CurrentIdentity.WorktreeClean) {
        throw "A full-suite run receipt is admissible only for a clean committed source."
    }
    if ($Receipt.SourceHead -ne [string]$CandidateReceipt.head -or
        $Receipt.SourceTree -ne [string]$CandidateReceipt.tree -or
        $Receipt.SourceHead -ne [string]$CurrentIdentity.HeadCommit -or
        $Receipt.SourceTree -ne [string]$CurrentIdentity.HeadTree) {
        throw "Run receipt, candidate receipt and current Git HEAD/tree do not match."
    }
    if ($Receipt.SourceStatusDigest -ne [string]$CurrentIdentity.StatusDigest -or
        $Receipt.SourceSnapshotDigest -ne [string]$CurrentSnapshot.Digest) {
        throw "Run receipt source status/snapshot digest does not match the clean candidate."
    }
    if ($Receipt.RunnerSha256 -ne $CurrentRunnerSha256) {
        throw "Run receipt runner SHA-256 does not match the candidate runner."
    }
    $projectEntries = @($CurrentSnapshot.Entries | Where-Object RelativePath -ceq "project.godot")
    if ($projectEntries.Count -ne 1 -or -not $projectEntries[0].Exists -or
        $Receipt.OverlayProjectBeforeSha256 -ne [string]$projectEntries[0].Sha256) {
        throw "Run receipt overlay is not based on candidate project.godot."
    }
    if ($Receipt.SuiteMode -notin @("full", "full-with-snapshots") -or
        $Receipt.StructureOverlayVersion -ne "none" -or
        $Receipt.NativeSkipPolicy -ne "blocking" -or
        $Receipt.Overall -ne "PASS" -or
        $Receipt.FailCount -ne 0 -or
        $Receipt.SkipCount -ne 0 -or
        $Receipt.BlockingFailureCount -ne 0 -or
        $Receipt.TargetCount -lt 1 -or
        @($Receipt.Results | Where-Object {
            $_.Status -ne "PASS" -or $_.ExitCode -ne 0 -or $_.BlockingFailure
        }).Count -gt 0) {
        throw "Run receipt is not a zero-failure, zero-skip required full-suite PASS."
    }
    $actualTargets = @($Receipt.Results | ForEach-Object { [string]$_.Name })
    if ($actualTargets.Count -ne $ExpectedTargets.Count -or
        [string]::Join("`n", $actualTargets) -cne [string]::Join("`n", @($ExpectedTargets))) {
        throw "Run receipt target list is not the candidate runner's closed full-suite manifest."
    }
    return $Receipt
}

function Invoke-PublicationReceiptVerification {
    param(
        [string]$ProjectRoot,
        [string]$CandidateReceiptPath
    )

    $resolvedCandidatePath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CandidateReceiptPath))
    if (-not (Test-Path -LiteralPath $resolvedCandidatePath -PathType Leaf)) {
        throw "Candidate publication receipt does not exist: '$resolvedCandidatePath'."
    }
    $contractTool = $controlContractToolPath
    if (-not (Test-Path -LiteralPath $contractTool -PathType Leaf)) {
        throw "Publication receipt verifier is missing: '$contractTool'."
    }
    $pythonCommand = Get-Command -Name "python" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $pythonCommand) {
        throw "Python is required to verify the candidate publication receipt."
    }

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pythonCommand.Source
        $arguments = @(
            "-I", "-B", $isolatedPythonEntryPath,
            "--preload", "workbench_lock=$controlLockToolPath",
            "--script", $contractTool, "--",
            "--repo", $ProjectRoot,
            "publication", "verify",
            "--receipt", $resolvedCandidatePath
        )
        $startInfo.Arguments = (@($arguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $ProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Publication receipt verification process could not be started."
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            try { $process.Kill($true) } catch { $process.Kill() }
            $process.WaitForExit()
            throw "Publication receipt verification timed out after 60 seconds."
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult().Trim()
        $standardError = $standardErrorTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            throw "Candidate publication receipt verification failed: $standardOutput $standardError"
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    try {
        return Get-Content -LiteralPath $resolvedCandidatePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Candidate publication receipt is unreadable after verification: $($_.Exception.Message)"
    }
}

function Test-GodotTestRunReceipt {
    param(
        [string]$ProjectRoot,
        [string]$RunReceiptPath,
        [string]$CandidateReceiptPath,
        [string]$CurrentRunnerSha256,
        [string[]]$FullHeadlessScriptTests,
        [string[]]$FullHeadlessFlowScenes,
        [string[]]$SnapshotScenes
    )

    $receipt = Read-GodotCandidateRunEvidence -ReceiptPath $RunReceiptPath
    $candidateReceipt = Invoke-PublicationReceiptVerification `
        -ProjectRoot $ProjectRoot `
        -CandidateReceiptPath $CandidateReceiptPath
    $identityBefore = Get-GitSourceIdentity -ProjectRoot $ProjectRoot
    $snapshotBefore = Get-ProjectSnapshotFingerprint -ProjectRoot $ProjectRoot
    $includeSnapshotScenes = $receipt.SuiteMode -eq "full-with-snapshots"
    $expectedSelection = Get-RunnerTestSelection `
        -ResolvedTarget $null `
        -ProjectRoot $ProjectRoot `
        -FullSuite $true `
        -IncludeSnapshotScenes $includeSnapshotScenes `
        -DefaultHeadlessScriptTests $FullHeadlessScriptTests `
        -DefaultHeadlessFlowScenes $FullHeadlessFlowScenes `
        -SnapshotScenes $SnapshotScenes
    $snapshotAfter = Get-ProjectSnapshotFingerprint -ProjectRoot $ProjectRoot
    $identityAfter = Get-GitSourceIdentity -ProjectRoot $ProjectRoot
    if ($identityBefore.HeadCommit -ne $identityAfter.HeadCommit -or
        $identityBefore.HeadTree -ne $identityAfter.HeadTree -or
        $identityBefore.WorktreeClean -ne $identityAfter.WorktreeClean -or
        $identityBefore.StatusDigest -ne $identityAfter.StatusDigest -or
        $snapshotBefore.Digest -ne $snapshotAfter.Digest) {
        throw "Candidate source moved while the run receipt was verified. Retry from a stable clean candidate."
    }
    if ($receipt.Version -eq "godot-test-aggregate-receipt-v2") {
        return Assert-GodotTestAggregateReceiptBinding `
            -Receipt $receipt `
            -CandidateReceipt $candidateReceipt `
            -CurrentIdentity $identityAfter `
            -CurrentSnapshot $snapshotAfter `
            -CurrentRunnerSha256 $CurrentRunnerSha256 `
            -ExpectedTargets @($expectedSelection.ManifestTargets)
    }
    return Assert-GodotTestRunReceiptBinding `
        -Receipt $receipt `
        -CandidateReceipt $candidateReceipt `
        -CurrentIdentity $identityAfter `
        -CurrentSnapshot $snapshotAfter `
        -CurrentRunnerSha256 $CurrentRunnerSha256 `
        -ExpectedTargets @($expectedSelection.ManifestTargets)
}

function ConvertTo-TestProjectRelativePath {
    param([string]$TargetName)

    if ([string]::IsNullOrWhiteSpace($TargetName)) {
        throw "Test target name cannot be empty."
    }

    $normalized = $TargetName.Trim().Replace('\', '/')
    if ($normalized.StartsWith("tests/", [StringComparison]::OrdinalIgnoreCase)) {
        return $normalized
    }
    if ($normalized -match '(?i)^underwater_map_workbench/tests/[^/]+\.gd$') {
        return $normalized
    }
    if ($normalized -match '(?i)^underwater_map_workbench/structures/[^/]+/tests/[^/]+\.gd$') {
        return $normalized
    }
    if ($normalized -match '(?i)^diver_workbench/tests/[^/]+\.(?:gd|tscn)$') {
        return $normalized
    }
    if ($normalized.Contains('/')) {
        throw "Manifest test target must be a tests/ entry, a direct underwater_map_workbench/tests/*.gd script, a package-local underwater_map_workbench/structures/*/tests/*.gd script, or a direct diver_workbench/tests/*.(gd|tscn) target: '$TargetName'."
    }
    return "tests/$normalized"
}


function ConvertTo-TestResourcePath {
    param([string]$TargetName)

    return "res://$(ConvertTo-TestProjectRelativePath -TargetName $TargetName)"
}


function Resolve-TestTarget {
    param(
        [string]$RequestedTarget,
        [string]$SourceProjectRoot,
        [string]$ParameterName = "-Target"
    )

    if ([string]::IsNullOrWhiteSpace($RequestedTarget)) {
        throw "$ParameterName requires a .gd script or .tscn scene from tests/, a direct .gd script from underwater_map_workbench/tests/, a package-local .gd script from underwater_map_workbench/structures/*/tests/, or a direct .gd/.tscn target from diver_workbench/tests/."
    }

    $testsRoot = [System.IO.Path]::GetFullPath((Join-Path $SourceProjectRoot "tests")).TrimEnd([char[]]"\/")
    $workbenchTestsRoot = [System.IO.Path]::GetFullPath((Join-Path $SourceProjectRoot "underwater_map_workbench/tests")).TrimEnd([char[]]"\/")
    $structurePackagesRoot = [System.IO.Path]::GetFullPath((Join-Path $SourceProjectRoot "underwater_map_workbench/structures")).TrimEnd([char[]]"\/")
    $diverWorkbenchTestsRoot = [System.IO.Path]::GetFullPath((Join-Path $SourceProjectRoot "diver_workbench/tests")).TrimEnd([char[]]"\/")
    $targetText = $RequestedTarget.Trim()
    $candidatePath = $null
    if ($targetText.StartsWith("res://", [StringComparison]::OrdinalIgnoreCase)) {
        $resourceRelative = $targetText.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $candidatePath = Join-Path $SourceProjectRoot $resourceRelative
    }
    elseif ([System.IO.Path]::IsPathRooted($targetText)) {
        $candidatePath = $targetText
    }
    else {
        $normalizedRelative = $targetText.Replace('\', '/')
        if ($normalizedRelative.StartsWith("tests/", [StringComparison]::OrdinalIgnoreCase) -or
            $normalizedRelative.StartsWith("underwater_map_workbench/tests/", [StringComparison]::OrdinalIgnoreCase) -or
            $normalizedRelative.StartsWith("underwater_map_workbench/structures/", [StringComparison]::OrdinalIgnoreCase) -or
            $normalizedRelative.StartsWith("diver_workbench/tests/", [StringComparison]::OrdinalIgnoreCase)) {
            $candidatePath = Join-Path $SourceProjectRoot ($normalizedRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        }
        else {
            $candidatePath = Join-Path $testsRoot ($normalizedRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        }
    }

    $absoluteTarget = [System.IO.Path]::GetFullPath($candidatePath)
    $testsPrefix = $testsRoot + [System.IO.Path]::DirectorySeparatorChar
    $extension = [System.IO.Path]::GetExtension($absoluteTarget).ToLowerInvariant()
    $isTestsTarget = $absoluteTarget.StartsWith($testsPrefix, [StringComparison]::OrdinalIgnoreCase)
    $isDirectWorkbenchScript = (
        $extension -eq ".gd" -and
        [string]::Equals(
            [System.IO.Path]::GetDirectoryName($absoluteTarget).TrimEnd([char[]]"\/"),
            $workbenchTestsRoot,
            [StringComparison]::OrdinalIgnoreCase
        )
    )
    $structurePackagesPrefix = $structurePackagesRoot + [System.IO.Path]::DirectorySeparatorChar
    $isStructurePackageScript = $false
    if ($extension -eq ".gd" -and $absoluteTarget.StartsWith($structurePackagesPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $relativeStructureTarget = $absoluteTarget.Substring($structurePackagesPrefix.Length).Replace('\', '/')
        $isStructurePackageScript = $relativeStructureTarget -match '(?i)^[^/]+/tests/[^/]+\.gd$'
    }
    $isDirectDiverWorkbenchTarget = (
        $extension -in @(".gd", ".tscn") -and
        [string]::Equals(
            [System.IO.Path]::GetDirectoryName($absoluteTarget).TrimEnd([char[]]"\/"),
            $diverWorkbenchTestsRoot,
            [StringComparison]::OrdinalIgnoreCase
        )
    )
    if (-not $isTestsTarget -and -not $isDirectWorkbenchScript -and -not $isStructurePackageScript -and -not $isDirectDiverWorkbenchTarget) {
        throw "Test target must stay inside '$testsRoot', be a direct .gd script inside '$workbenchTestsRoot', be a package-local .gd script inside '$structurePackagesRoot/*/tests', or be a direct .gd/.tscn target inside '$diverWorkbenchTestsRoot': '$RequestedTarget'."
    }
    if (-not (Test-Path -LiteralPath $absoluteTarget -PathType Leaf)) {
        throw "Test target does not exist: '$RequestedTarget'."
    }
    if ($extension -notin @(".gd", ".tscn") -or (($isDirectWorkbenchScript -or $isStructurePackageScript) -and $extension -ne ".gd")) {
        throw "Test target must be a .gd script or .tscn scene: '$RequestedTarget'."
    }

    if ($isDirectWorkbenchScript) {
        return "underwater_map_workbench/tests/$([System.IO.Path]::GetFileName($absoluteTarget))"
    }
    if ($isStructurePackageScript) {
        return "underwater_map_workbench/structures/$relativeStructureTarget"
    }
    if ($isDirectDiverWorkbenchTarget) {
        return "diver_workbench/tests/$([System.IO.Path]::GetFileName($absoluteTarget))"
    }
    return "tests/$($absoluteTarget.Substring($testsPrefix.Length).Replace('\', '/'))"
}

function New-TestCase {
    param(
        [string]$Name,
        [string]$Group,
        [string[]]$Arguments,
        [string[]]$UserArguments = @(),
        [bool]$NativeWindow = $false
    )

    return [pscustomobject]@{
        Name = $Name
        Group = $Group
        Arguments = $Arguments
        UserArguments = $UserArguments
        NativeWindow = $NativeWindow
        TimeoutSeconds = if (-not $testTimeoutWasExplicit -and $testSpecificDefaultTimeoutSeconds.ContainsKey($Name)) {
            [int]$testSpecificDefaultTimeoutSeconds[$Name]
        }
        else {
            $TestTimeoutSeconds
        }
    }
}

function Set-NativeShardDummyAudio {
    param(
        [object[]]$TestCases,
        [ValidateSet("headless", "native")]
        [string]$ShardLane
    )

    $cases = @($TestCases)
    if ($cases.Count -lt 1) {
        throw "Shard lane '$ShardLane' cannot configure an empty test case set."
    }

    foreach ($testCase in $cases) {
        $isNativeWindow = [bool]$testCase.NativeWindow
        if ($ShardLane -eq "headless") {
            if ($isNativeWindow) {
                throw "Headless shard lane contains native target '$($testCase.Name)'."
            }
            continue
        }

        if (-not $isNativeWindow) {
            throw "Native shard lane contains non-native target '$($testCase.Name)'."
        }

        $arguments = @($testCase.Arguments)
        $existingAudioDriver = @($arguments | Where-Object {
            $argumentText = [string]$_
            $argumentText -ceq "--audio-driver" -or
                $argumentText.StartsWith("--audio-driver=", [StringComparison]::Ordinal)
        })
        if ($existingAudioDriver.Count -gt 0) {
            throw "Native shard target '$($testCase.Name)' already declares an audio driver."
        }

        $testCase.Arguments = [string[]](@("--audio-driver", "Dummy") + $arguments)
    }
}

function Remove-AnsiEscapes {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }
    return [System.Text.RegularExpressions.Regex]::Replace($Text, $ansiEscapePattern, "")
}

function Get-IsolatedWorkspaceInputFingerprint {
    param([string]$ProjectRoot)

    $normalizedRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]"\/")
    if (-not (Test-Path -LiteralPath $normalizedRoot -PathType Container)) {
        throw "Cannot fingerprint missing isolated project '$normalizedRoot'."
    }
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @(Get-ChildItem -LiteralPath $normalizedRoot -Force -Recurse)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Isolated project contains an unsupported reparse point: '$($item.FullName)'."
        }
        if ($item.PSIsContainer) {
            continue
        }
        $absolutePath = [System.IO.Path]::GetFullPath($item.FullName)
        if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Isolated input escaped its project root: '$absolutePath'."
        }
        $relativePath = $absolutePath.Substring($rootPrefix.Length).Replace('\', '/')
        if ($relativePath -eq ".godot" -or $relativePath.StartsWith(".godot/", [StringComparison]::Ordinal)) {
            continue
        }
        $paths.Add($relativePath)
    }
    $orderedPaths = @($paths)
    [Array]::Sort($orderedPaths, [StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[string]]::new()
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($relativePath in $orderedPaths) {
        $absolutePath = Join-Path $normalizedRoot $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $file = Get-Item -LiteralPath $absolutePath
        $sha256 = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $records.Add("$(ConvertTo-TestRunReceiptField -Value $relativePath)|$($file.Length)|$sha256")
        $entries.Add([pscustomobject]@{
            RelativePath = $relativePath
            Length = [long]$file.Length
            Sha256 = $sha256
        })
    }
    $canonicalManifest = [string]::Join("`n", $records)
    return [pscustomobject]@{
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonicalManifest
        FileCount = $orderedPaths.Count
        Paths = @($orderedPaths)
        Entries = @($entries)
        CanonicalManifest = $canonicalManifest
    }
}

function Assert-IsolatedImportInputTransition {
    param(
        [pscustomobject]$Before,
        [pscustomobject]$After
    )

    $beforeByPath = @{}
    foreach ($entry in @($Before.Entries)) { $beforeByPath[[string]$entry.RelativePath] = $entry }
    $afterByPath = @{}
    foreach ($entry in @($After.Entries)) { $afterByPath[[string]$entry.RelativePath] = $entry }
    foreach ($path in $beforeByPath.Keys) {
        if (-not $afterByPath.ContainsKey($path)) {
            throw "Godot import removed immutable input '$path'."
        }
        $beforeEntry = $beforeByPath[$path]
        $afterEntry = $afterByPath[$path]
        if ([long]$beforeEntry.Length -ne [long]$afterEntry.Length -or
            [string]$beforeEntry.Sha256 -ne [string]$afterEntry.Sha256) {
            throw "Godot import modified immutable input '$path'."
        }
    }
    $addedPaths = @($afterByPath.Keys | Where-Object { -not $beforeByPath.ContainsKey($_) })
    foreach ($path in $addedPaths) {
        if (-not $path.EndsWith(".uid", [StringComparison]::Ordinal) -and
            -not $path.EndsWith(".import", [StringComparison]::Ordinal)) {
            throw "Godot import created unexpected source-tree output '$path'."
        }
    }
    [Array]::Sort($addedPaths, [StringComparer]::Ordinal)
    $addedUidPaths = @($addedPaths | Where-Object { $_.EndsWith(".uid", [StringComparison]::Ordinal) })
    $addedImportPaths = @($addedPaths | Where-Object { $_.EndsWith(".import", [StringComparison]::Ordinal) })
    $canonical = @(
        "version=godot-import-input-transition-v1",
        "before=$($Before.Digest)",
        "after=$($After.Digest)",
        "added_uid_count=$($addedUidPaths.Count)",
        "added_uid_paths=$(ConvertTo-TestRunReceiptField -Value ([string]::Join("`n", $addedUidPaths)))",
        "added_import_count=$($addedImportPaths.Count)",
        "added_import_paths=$(ConvertTo-TestRunReceiptField -Value ([string]::Join("`n", $addedImportPaths)))"
    ) -join "`n"
    return [pscustomobject]@{
        Version = "godot-import-input-transition-v1"
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonical
        AddedUidCount = $addedUidPaths.Count
        AddedUidPaths = @($addedUidPaths)
        AddedImportCount = $addedImportPaths.Count
        AddedImportPaths = @($addedImportPaths)
    }
}

function New-IsolatedTargetWorkspace {
    param(
        [string]$SeedProjectRoot,
        [string]$WorkspaceRoot,
        [int]$TargetIndex,
        [pscustomobject]$ExpectedSeedFingerprint
    )

    $seedRoot = [System.IO.Path]::GetFullPath($SeedProjectRoot).TrimEnd([char[]]"\/")
    $targetName = "target_{0:D3}_{1}_{2}" -f $TargetIndex, $PID, [Guid]::NewGuid().ToString("N")
    $targetRoot = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $targetName))
    [void](New-Item -ItemType Directory -Path $targetRoot)
    try {
        foreach ($entry in @(Get-ChildItem -LiteralPath $seedRoot -Force)) {
            Copy-Item -LiteralPath $entry.FullName -Destination $targetRoot -Recurse -Force
        }
        $copyFingerprint = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $targetRoot
        if ($copyFingerprint.Digest -ne [string]$ExpectedSeedFingerprint.Digest -or
            $copyFingerprint.FileCount -ne [int]$ExpectedSeedFingerprint.FileCount -or
            [string]::Join("`n", @($copyFingerprint.Paths)) -cne [string]::Join("`n", @($ExpectedSeedFingerprint.Paths))) {
            throw "Fresh target materialization differs from the immutable imported seed."
        }
        return [pscustomobject]@{
            WorkspacePath = $targetRoot
            SeedDigest = [string]$copyFingerprint.Digest
            SeedFileCount = [int]$copyFingerprint.FileCount
        }
    }
    catch {
        if (Test-Path -LiteralPath $targetRoot) {
            Remove-IsolatedTestWorkspace -WorkspacePath $targetRoot -WorkspaceRoot $WorkspaceRoot
        }
        throw
    }
}

function Set-IsolatedGodotTargetConfiguration {
    param(
        [string]$SeedProjectRoot,
        [string]$TargetProjectRoot,
        [pscustomobject]$RunContext
    )

    $seedProjectFile = Join-Path $SeedProjectRoot "project.godot"
    $targetProjectFile = Join-Path $TargetProjectRoot "project.godot"
    $seedHash = (Get-FileHash -LiteralPath $seedProjectFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $beforeHash = (Get-FileHash -LiteralPath $targetProjectFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($seedHash -ne $beforeHash) {
        throw "Fresh target project.godot differs from its imported seed."
    }
    $content = [System.IO.File]::ReadAllText($targetProjectFile)
    $lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*(?:\r?\n)?',
        ''
    )
    $applicationHeader = [System.Text.RegularExpressions.Regex]::Match($content, '(?m)^\[application\]\r?$')
    if (-not $applicationHeader.Success) {
        throw "Fresh target project.godot has no [application] section."
    }
    $insertIndex = $applicationHeader.Index + $applicationHeader.Length
    if ($content.Substring($insertIndex).StartsWith("`r`n")) { $insertIndex += 2 }
    elseif ($content.Substring($insertIndex).StartsWith("`n")) { $insertIndex += 1 }
    $block = (
        'config/use_custom_user_dir=true' + $lineEnding +
        'config/custom_user_dir_name="' + $RunContext.UserDirectoryName + '"' + $lineEnding
    )
    $content = $content.Insert($insertIndex, $block)
    [System.IO.File]::WriteAllText($targetProjectFile, $content, [System.Text.UTF8Encoding]::new($false))
    $afterHash = (Get-FileHash -LiteralPath $targetProjectFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $canonical = @(
        "version=godot-target-overlay-v1",
        "seed_project=$seedHash",
        "target_project=$afterHash",
        "run_id=$($RunContext.RunId)",
        "user_directory=$($RunContext.UserDirectoryName)"
    ) -join "`n"
    return [pscustomobject]@{
        Version = "godot-target-overlay-v1"
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonical
        SeedProjectSha256 = $seedHash
        TargetProjectSha256 = $afterHash
        RunId = [string]$RunContext.RunId
        UserDirectoryName = [string]$RunContext.UserDirectoryName
    }
}

function Copy-TestCaseForWorkspace {
    param(
        [pscustomobject]$TestCase,
        [string]$SeedProjectRoot,
        [string]$TargetProjectRoot
    )

    $arguments = @($TestCase.Arguments | ForEach-Object {
        if ([string]::Equals([string]$_, $SeedProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $TargetProjectRoot
        }
        else {
            [string]$_
        }
    })
    return [pscustomobject]@{
        Name = [string]$TestCase.Name
        Group = [string]$TestCase.Group
        Arguments = @($arguments)
        UserArguments = @($TestCase.UserArguments)
        NativeWindow = [bool]$TestCase.NativeWindow
        TimeoutSeconds = [int]$TestCase.TimeoutSeconds
    }
}

function Set-TrustedChildEnvironment {
    param(
        [System.Diagnostics.ProcessStartInfo]$StartInfo,
        [string]$TemporaryDirectory,
        [string]$InvocationId
    )

    [void](New-Item -ItemType Directory -Path $TemporaryDirectory -Force)
    $preservedNames = @(
        "SystemRoot", "WINDIR", "SystemDrive", "COMSPEC", "PATHEXT", "OS",
        "PROCESSOR_ARCHITECTURE", "PROCESSOR_IDENTIFIER", "NUMBER_OF_PROCESSORS",
        "USERPROFILE", "HOMEDRIVE", "HOMEPATH", "APPDATA", "LOCALAPPDATA", "PROGRAMDATA"
    )
    $StartInfo.EnvironmentVariables.Clear()
    foreach ($name in $preservedNames) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $StartInfo.EnvironmentVariables[$name] = $value
        }
    }
    $StartInfo.EnvironmentVariables["TEMP"] = $TemporaryDirectory
    $StartInfo.EnvironmentVariables["TMP"] = $TemporaryDirectory
    $StartInfo.EnvironmentVariables["OSTATNI_POMOST_TEST_INVOCATION"] = $InvocationId
}

function New-RunnerKillOnCloseJob {
    if ($env:OS -ne "Windows_NT") {
        return [IntPtr]::Zero
    }
    $interopType = "OstatniPomost.RunnerJob" -as [type]
    if ($null -eq $interopType) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace OstatniPomost {
  public static class RunnerJob {
    [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS {
      public UInt64 ReadOperationCount, WriteOperationCount, OtherOperationCount;
      public UInt64 ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT {
      public Int64 PerProcessUserTimeLimit, PerJobUserTimeLimit;
      public UInt32 LimitFlags;
      public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
      public UInt32 ActiveProcessLimit;
      public Int64 Affinity;
      public UInt32 PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT {
      public BASIC_LIMIT BasicLimitInformation;
      public IO_COUNTERS IoInfo;
      public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [StructLayout(LayoutKind.Sequential)] struct BASIC_ACCOUNTING {
      public Int64 TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime;
      public UInt32 TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j, int c, IntPtr i, UInt32 l);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr j, int c, IntPtr i, UInt32 l, IntPtr r);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr j, UInt32 e);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    public static IntPtr Create() {
      IntPtr job = CreateJobObject(IntPtr.Zero, null);
      if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
      EXTENDED_LIMIT info = new EXTENDED_LIMIT(); info.BasicLimitInformation.LimitFlags = 0x00002000;
      int size = Marshal.SizeOf(typeof(EXTENDED_LIMIT)); IntPtr ptr = Marshal.AllocHGlobal(size);
      try { Marshal.StructureToPtr(info, ptr, false); if (!SetInformationJobObject(job, 9, ptr, (UInt32)size)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
      catch { CloseHandle(job); throw; } finally { Marshal.FreeHGlobal(ptr); }
      return job;
    }
    public static void Assign(IntPtr job, Process process) { if (!AssignProcessToJobObject(job, process.Handle)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static UInt32 Active(IntPtr job) { int size=Marshal.SizeOf(typeof(BASIC_ACCOUNTING)); IntPtr ptr=Marshal.AllocHGlobal(size); try { if(!QueryInformationJobObject(job,1,ptr,(UInt32)size,IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error()); return ((BASIC_ACCOUNTING)Marshal.PtrToStructure(ptr,typeof(BASIC_ACCOUNTING))).ActiveProcesses; } finally { Marshal.FreeHGlobal(ptr); } }
    public static void Terminate(IntPtr job) { if (!TerminateJobObject(job, 1)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static void Close(IntPtr job) { if (job != IntPtr.Zero && !CloseHandle(job)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  }
}
'@
        $interopType = "OstatniPomost.RunnerJob" -as [type]
    }
    return $interopType::Create()
}

function Complete-RunnerJob {
    param(
        [IntPtr]$JobHandle,
        [bool]$Terminate
    )
    if ($JobHandle -eq [IntPtr]::Zero) { return 0 }
    $interopType = "OstatniPomost.RunnerJob" -as [type]
    $active = [int]$interopType::Active($JobHandle)
    try {
        if ($Terminate -or $active -gt 0) { $interopType::Terminate($JobHandle) }
    }
    finally {
        $interopType::Close($JobHandle)
    }
    return $active
}

function New-TrustedCompletionRecord {
    param(
        [string]$InvocationDigest,
        [string]$TargetName,
        [int]$ExitCode,
        [string]$OutputDigest,
        [string]$InputBeforeDigest,
        [string]$InputAfterDigest,
        [int]$RecordCount = 1
    )
    foreach ($digest in @($InvocationDigest, $OutputDigest, $InputBeforeDigest, $InputAfterDigest)) {
        if ($digest -notmatch '^[0-9a-f]{64}$') { throw "Completion record digest is malformed." }
    }
    if ($RecordCount -ne 1 -or [string]::IsNullOrWhiteSpace($TargetName)) {
        throw "Completion record must be emitted exactly once for one exact target."
    }
    $canonical = @(
        "version=godot-trusted-completion-v1",
        "invocation=$InvocationDigest",
        "target=$(ConvertTo-TestRunReceiptField -Value $TargetName)",
        "exit_code=$ExitCode",
        "output=$OutputDigest",
        "input_before=$InputBeforeDigest",
        "input_after=$InputAfterDigest"
    ) -join "`n"
    return [pscustomobject]@{
        Version = "godot-trusted-completion-v1"
        Digest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $canonical
        CanonicalRecord = $canonical
    }
}

function Assert-TrustedTargetEvidence {
    param([pscustomobject]$Result)

    $requiredProperties = @(
        "RunId", "UserDirectoryName", "InputBeforeDigest", "InputAfterDigest",
        "InvocationDigest", "OutputDigest", "CompletionVersion", "CompletionDigest",
        "TargetOverlayVersion", "TargetOverlayDigest"
    )
    foreach ($propertyName in $requiredProperties) {
        if ($null -eq $Result.PSObject.Properties[$propertyName]) {
            throw "Target result is missing trusted isolation field '$propertyName'."
        }
    }
    foreach ($digest in @(
        [string]$Result.InputBeforeDigest, [string]$Result.InputAfterDigest,
        [string]$Result.InvocationDigest, [string]$Result.OutputDigest,
        [string]$Result.CompletionDigest, [string]$Result.TargetOverlayDigest
    )) {
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw "Target result contains a malformed trusted digest."
        }
    }
    if ([string]$Result.InputBeforeDigest -ne [string]$Result.InputAfterDigest -or
        [string]$Result.CompletionVersion -ne "godot-trusted-completion-v1" -or
        [string]$Result.TargetOverlayVersion -ne "godot-target-overlay-v1" -or
        [string]::IsNullOrWhiteSpace([string]$Result.RunId) -or
        [string]::IsNullOrWhiteSpace([string]$Result.UserDirectoryName)) {
        throw "Target result does not prove an immutable fresh target boundary."
    }
    $expectedCompletion = New-TrustedCompletionRecord `
        -InvocationDigest ([string]$Result.InvocationDigest) `
        -TargetName ([string]$Result.Name) `
        -ExitCode ([int]$Result.ExitCode) `
        -OutputDigest ([string]$Result.OutputDigest) `
        -InputBeforeDigest ([string]$Result.InputBeforeDigest) `
        -InputAfterDigest ([string]$Result.InputAfterDigest)
    if ([string]$Result.CompletionDigest -ne [string]$expectedCompletion.Digest) {
        throw "Target trusted completion digest is not bound to its exact invocation/result."
    }
    return $Result
}

function Write-TestOutput {
    param([string]$Output)

    foreach ($line in ($Output -split "\r?\n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host ("    " + $line)
        }
    }
}

function Invoke-GodotImportPreflight {
    param(
        [string]$GodotExecutable,
        [string]$ProjectRoot,
        [int]$TimeoutSeconds,
        [pscustomobject]$RunContext
    )

    Write-Host "[IMPORT] RUN  isolated project import"

    $standardOutput = ""
    $standardError = ""
    $exitCode = -1
    $launchError = $null
    $process = $null
    $jobHandle = [IntPtr]::Zero
    $jobClosed = $false
    $inputBefore = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $ProjectRoot
    $invocationId = [Guid]::NewGuid().ToString("N")
    $temporaryDirectory = Join-Path $ProjectRoot ".godot/runner-temp/import-$invocationId"
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotExecutable
        $processArguments = @(
            "--headless",
            "--editor",
            "--path", $ProjectRoot,
            "--import",
            "--debug-server", $RunContext.DebugServerUri,
            "--dap-port", [string]$RunContext.DapPort,
            "--lsp-port", [string]$RunContext.LspPort
        )
        $startInfo.Arguments = (@($processArguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $ProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        Set-TrustedChildEnvironment `
            -StartInfo $startInfo `
            -TemporaryDirectory $temporaryDirectory `
            -InvocationId $invocationId

        $jobHandle = New-RunnerKillOnCloseJob
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Godot import process could not be started."
        }
        if ($jobHandle -ne [IntPtr]::Zero) {
            $interopType = "OstatniPomost.RunnerJob" -as [type]
            $interopType::Assign($jobHandle, $process)
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            [void](Complete-RunnerJob -JobHandle $jobHandle -Terminate $true)
            $jobClosed = $true
            if (-not $process.HasExited) { $process.Kill() }
            $process.WaitForExit()
            $launchError = "project import timed out after $TimeoutSeconds seconds"
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        if (-not $jobClosed) {
            $activeAfterExit = Complete-RunnerJob -JobHandle $jobHandle -Terminate $false
            $jobClosed = $true
            if ($activeAfterExit -gt 0) {
                $launchError = "project import left $activeAfterExit process(es) in its isolated Job Object"
            }
        }
    }
    catch {
        $launchError = $_.Exception.Message
    }
    finally {
        if (-not $jobClosed -and $jobHandle -ne [IntPtr]::Zero) {
            try { [void](Complete-RunnerJob -JobHandle $jobHandle -Terminate $true) }
            catch { $launchError = "failed to close import process tree: $($_.Exception.Message)" }
        }
        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    $inputAfter = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $ProjectRoot

    $outputParts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($standardOutput)) {
        $outputParts.Add($standardOutput.TrimEnd([char[]]"`r`n"))
    }
    if (-not [string]::IsNullOrEmpty($standardError)) {
        $outputParts.Add($standardError.TrimEnd([char[]]"`r`n"))
    }
    $cleanOutput = Remove-AnsiEscapes -Text ($outputParts -join [Environment]::NewLine)
    $engineErrorLines = @($cleanOutput -split "\r?\n" | Where-Object {
        $_ -match "^\s*(?:SCRIPT ERROR|ERROR):"
    })

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $launchError) {
        $reasons.Add($launchError)
    }
    if ($exitCode -ne 0) {
        $reasons.Add("exit code $exitCode")
    }
    if ($engineErrorLines.Count -gt 0) {
        $reasons.Add("engine output contains ERROR:/SCRIPT ERROR:")
    }
    $importTransition = $null
    try { $importTransition = Assert-IsolatedImportInputTransition -Before $inputBefore -After $inputAfter }
    catch { $reasons.Add($_.Exception.Message) }

    if ($reasons.Count -gt 0) {
        $reasonText = $reasons -join "; "
        Write-Host ("[IMPORT] FAIL {0}" -f $reasonText) -ForegroundColor Red
        Write-TestOutput -Output $cleanOutput
        throw "Godot import preflight failed: $reasonText"
    }

    Write-Host "[IMPORT] PASS isolated project import" -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($cleanOutput)) {
        Write-Verbose $cleanOutput
    }
    return [pscustomobject]@{
        InputBeforeDigest = [string]$inputBefore.Digest
        InputAfterDigest = [string]$inputAfter.Digest
        OutputDigest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $cleanOutput
        InvocationId = $invocationId
        TransitionVersion = [string]$importTransition.Version
        TransitionDigest = [string]$importTransition.Digest
        AddedUidCount = [int]$importTransition.AddedUidCount
    }
}

function Invoke-GodotTest {
    param(
        [string]$GodotExecutable,
        [pscustomobject]$TestCase,
        [int]$Index,
        [int]$Total,
        [pscustomobject]$RunContext,
        [string]$ProjectRoot
    )

    Write-Host ("[{0,2}/{1}] RUN  {2} ({3})" -f $Index, $Total, $TestCase.Name, $TestCase.Group)

    $standardOutput = ""
    $standardError = ""
    $exitCode = -1
    $launchError = $null
    $process = $null
    $jobHandle = [IntPtr]::Zero
    $jobClosed = $false
    $inputBefore = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $ProjectRoot
    $invocationId = [Guid]::NewGuid().ToString("N")
    $invocationCanonical = @(
        "version=godot-test-invocation-v1",
        "id=$invocationId",
        "target=$(ConvertTo-TestRunReceiptField -Value ([string]$TestCase.Name))",
        "group=$(ConvertTo-TestRunReceiptField -Value ([string]$TestCase.Group))",
        "input=$($inputBefore.Digest)",
        "run_id=$($RunContext.RunId)",
        "arguments=$(ConvertTo-TestRunReceiptField -Value ([string]::Join("`n", @($TestCase.Arguments) + @("--") + @($TestCase.UserArguments))))"
    ) -join "`n"
    $invocationDigest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $invocationCanonical
    $temporaryDirectory = Join-Path $ProjectRoot ".godot/runner-temp/test-$invocationId"
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotExecutable
        # Engine options and the scene/script target stay before `--`.
        # Verdict output is captured only through trusted parent-owned pipes.
        $processArguments = @(
            "--debug-server", $RunContext.DebugServerUri,
            "--dap-port", [string]$RunContext.DapPort,
            "--lsp-port", [string]$RunContext.LspPort
        ) + @($TestCase.Arguments)
        if (@($TestCase.UserArguments).Count -gt 0) {
            $processArguments += @("--") + @($TestCase.UserArguments)
        }
        $startInfo.Arguments = (@($processArguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $ProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $false
        Set-TrustedChildEnvironment `
            -StartInfo $startInfo `
            -TemporaryDirectory $temporaryDirectory `
            -InvocationId $invocationId

        $jobHandle = New-RunnerKillOnCloseJob
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Godot process could not be started."
        }
        if ($jobHandle -ne [IntPtr]::Zero) {
            $interopType = "OstatniPomost.RunnerJob" -as [type]
            $interopType::Assign($jobHandle, $process)
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TestCase.TimeoutSeconds * 1000)) {
            [void](Complete-RunnerJob -JobHandle $jobHandle -Terminate $true)
            $jobClosed = $true
            if (-not $process.HasExited) { $process.Kill() }
            $process.WaitForExit()
            $launchError = "test timed out after $($TestCase.TimeoutSeconds) seconds"
        }
        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        if (-not $jobClosed) {
            $activeAfterExit = Complete-RunnerJob -JobHandle $jobHandle -Terminate $false
            $jobClosed = $true
            if ($activeAfterExit -gt 0) {
                $launchError = "test left $activeAfterExit process(es) in its isolated Job Object"
            }
        }
    }
    catch {
        $launchError = $_.Exception.Message
    }
    finally {
        if (-not $jobClosed -and $jobHandle -ne [IntPtr]::Zero) {
            try { [void](Complete-RunnerJob -JobHandle $jobHandle -Terminate $true) }
            catch { $launchError = "failed to close test process tree: $($_.Exception.Message)" }
        }
        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    $inputAfter = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $ProjectRoot

    $outputParts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($standardOutput)) {
        $outputParts.Add($standardOutput.TrimEnd([char[]]"`r`n"))
    }
    if (-not [string]::IsNullOrEmpty($standardError)) {
        $outputParts.Add($standardError.TrimEnd([char[]]"`r`n"))
    }
    $rawOutput = $outputParts -join [Environment]::NewLine
    $cleanOutput = Remove-AnsiEscapes -Text $rawOutput
    $lines = @($cleanOutput -split "\r?\n")
    $engineErrorLines = @($lines | Where-Object { $_ -match "^\s*(?:SCRIPT ERROR|ERROR):" })
    $nativeSkipLine = $null
    if ($TestCase.NativeWindow) {
        $nativeSkipLine = $lines |
            Where-Object { $_ -match "^\s*Native window settings test SKIP:" } |
            Select-Object -First 1
    }

    $status = "FAIL"
    $blockingFailure = $true
    $reasons = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $launchError) {
        $status = "FAIL"
        $blockingFailure = $true
        $reasons.Add($launchError)
    }
    if ($exitCode -ne 0) {
        $status = "FAIL"
        $blockingFailure = $true
        $reasons.Add("exit code $exitCode")
    }
    if ($engineErrorLines.Count -gt 0) {
        $reasons.Add("engine output contains ERROR:/SCRIPT ERROR:")
    }
    if ($inputBefore.Digest -ne $inputAfter.Digest -or
        $inputBefore.FileCount -ne $inputAfter.FileCount -or
        [string]::Join("`n", @($inputBefore.Paths)) -cne [string]::Join("`n", @($inputAfter.Paths))) {
        $reasons.Add("test mutated immutable project inputs outside .godot")
    }

    $outputDigest = Get-GodotCanonicalEvidenceDigest -CanonicalEvidence $cleanOutput
    $completionRecord = $null
    try {
        $completionRecord = New-TrustedCompletionRecord `
            -InvocationDigest $invocationDigest `
            -TargetName ([string]$TestCase.Name) `
            -ExitCode $exitCode `
            -OutputDigest $outputDigest `
            -InputBeforeDigest ([string]$inputBefore.Digest) `
            -InputAfterDigest ([string]$inputAfter.Digest)
    }
    catch {
        $reasons.Add("trusted completion record failed: $($_.Exception.Message)")
    }

    if ($reasons.Count -eq 0 -and $null -ne $completionRecord) {
        $status = "PASS"
        $blockingFailure = $false
    }
    if (-not $blockingFailure -and $null -ne $nativeSkipLine) {
        $status = "SKIP"
        $blockingFailure = -not $AllowNativeSkip
        $reasons.Add($nativeSkipLine.Trim())
        if ($blockingFailure) {
            $reasons.Add("native test is required by default; use -AllowNativeSkip only for an explicitly unsupported environment")
        }
    }

    $reasonText = $reasons -join "; "
    switch ($status) {
        "PASS" {
            Write-Host ("[{0,2}/{1}] PASS {2}" -f $Index, $Total, $TestCase.Name) -ForegroundColor Green
            if (-not [string]::IsNullOrWhiteSpace($cleanOutput)) {
                Write-Verbose $cleanOutput
            }
        }
        "SKIP" {
            $suffix = if ($blockingFailure) { " [required: overall run will fail]" } else { "" }
            Write-Host ("[{0,2}/{1}] SKIP {2}: {3}{4}" -f $Index, $Total, $TestCase.Name, $reasonText, $suffix) -ForegroundColor Yellow
        }
        default {
            Write-Host ("[{0,2}/{1}] FAIL {2}: {3}" -f $Index, $Total, $TestCase.Name, $reasonText) -ForegroundColor Red
            Write-TestOutput -Output $cleanOutput
        }
    }

    return [pscustomobject]@{
        Name = $TestCase.Name
        Group = $TestCase.Group
        Status = $status
        ExitCode = $exitCode
        BlockingFailure = $blockingFailure
        Reason = $reasonText
        RunId = [string]$RunContext.RunId
        UserDirectoryName = [string]$RunContext.UserDirectoryName
        InputBeforeDigest = [string]$inputBefore.Digest
        InputAfterDigest = [string]$inputAfter.Digest
        InvocationDigest = $invocationDigest
        OutputDigest = $outputDigest
        CompletionVersion = if ($null -eq $completionRecord) { "none" } else { [string]$completionRecord.Version }
        CompletionDigest = if ($null -eq $completionRecord) { "none" } else { [string]$completionRecord.Digest }
    }
}

$manifestGroups = [ordered]@{
    "quick headless scripts" = $quickHeadlessScriptTests
    "full headless scripts" = $fullHeadlessScriptTests
    "quick headless flows" = $quickHeadlessFlowScenes
    "full headless flows" = $fullHeadlessFlowScenes
    "native snapshots" = $nativeSnapshotScenes
}
foreach ($manifestGroup in $manifestGroups.GetEnumerator()) {
    $duplicates = @($manifestGroup.Value | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    if ($duplicates.Count -gt 0) {
        throw "The $($manifestGroup.Key) manifest contains duplicate targets: $($duplicates -join ', ')"
    }
}

$missingQuickScripts = @($quickHeadlessScriptTests | Where-Object { $fullHeadlessScriptTests -notcontains $_ })
$missingQuickFlows = @($quickHeadlessFlowScenes | Where-Object { $fullHeadlessFlowScenes -notcontains $_ })
if ($missingQuickScripts.Count -gt 0 -or $missingQuickFlows.Count -gt 0) {
    $missingQuickTargets = @($missingQuickScripts) + @($missingQuickFlows)
    throw "Every quick target must also belong to the full manifest. Missing: $($missingQuickTargets -join ', ')"
}

$hasWriteShardPlan = -not [string]::IsNullOrWhiteSpace($WriteShardPlan)
$hasShardPlan = -not [string]::IsNullOrWhiteSpace($ShardPlan)
$hasShardId = -not [string]::IsNullOrWhiteSpace($ShardId)
$hasAggregateShardReceipts = @($AggregateShardReceipt | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
$aggregateMode = $hasShardPlan -and $hasAggregateShardReceipts -and -not $hasShardId
$shardMode = $hasShardPlan -and $hasShardId -and -not $hasAggregateShardReceipts
$activeShardPlan = $null
$activePlannedShard = $null
$activeShardTargets = @()

if ($hasWriteShardPlan) {
    $planForbiddenParameters = @(
        "GodotConsolePath", "Target", "NativeTarget", "TargetUserArgument", "TargetUserArgumentsJson",
        "TargetUserArgumentsBase64", "NativeMovieOutputPath", "NativeMovieFps", "KeepWorkspace",
        "RunReceiptOutputPath", "VerifyRunReceipt", "CandidateReceipt", "ShardPlan", "ShardId",
        "AggregateShardReceipt", "InPlace", "ImportTimeoutSeconds", "TestTimeoutSeconds", "AllowNativeSkip"
    )
    $providedPlanForbidden = @($planForbiddenParameters | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if (-not $Full -or $providedPlanForbidden.Count -gt 0) {
        throw "-WriteShardPlan requires only -Full, optional -IncludeSnapshots and shard counts; forbidden: $($providedPlanForbidden -join ', ')."
    }
    Assert-RunnerInvocationMode -InPlaceRequested $false
    Assert-TrackedLfEol -ProjectRoot $sourceProjectRoot
    $planIdentityBefore = Get-GitSourceIdentity -ProjectRoot $sourceProjectRoot
    $planSnapshotBefore = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceProjectRoot
    if (-not $planIdentityBefore.WorktreeClean) {
        throw "Shard plans can be written only from a clean committed source."
    }
    $planRunnerEntries = @($planSnapshotBefore.Entries | Where-Object RelativePath -ceq "tests/run_all_tests.ps1")
    if ($planRunnerEntries.Count -ne 1 -or -not $planRunnerEntries[0].Exists -or
        [string]$planRunnerEntries[0].Sha256 -ne $runnerSourceSha256) {
        throw "Shard plan cannot bind the executing runner to the source snapshot."
    }
    $planSelection = Get-RunnerTestSelection `
        -ResolvedTarget $null `
        -ProjectRoot $sourceProjectRoot `
        -FullSuite $true `
        -IncludeSnapshotScenes ([bool]$IncludeSnapshots) `
        -DefaultHeadlessScriptTests $fullHeadlessScriptTests `
        -DefaultHeadlessFlowScenes $fullHeadlessFlowScenes `
        -SnapshotScenes $nativeSnapshotScenes
    $planTargetGroups = [System.Collections.Generic.List[string]]::new()
    foreach ($targetName in @($planSelection.ManifestTargets)) {
        if (@($planSelection.HeadlessScriptTests) -ccontains $targetName) {
            $planTargetGroups.Add("headless script")
        }
        elseif ($targetName -ceq "native_window_settings_test.gd") {
            $planTargetGroups.Add("native window")
        }
        elseif ($fullHeadlessFlowScenes -ccontains $targetName) {
            $planTargetGroups.Add("headless flow")
        }
        elseif ($IncludeSnapshots -and $nativeSnapshotScenes -ccontains $targetName) {
            $planTargetGroups.Add("native snapshot")
        }
        else {
            throw "Full-suite target '$targetName' has no canonical shard lane/group."
        }
    }
    $planSnapshotAfter = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceProjectRoot
    $planIdentityAfter = Get-GitSourceIdentity -ProjectRoot $sourceProjectRoot
    if ($planIdentityBefore.HeadCommit -ne $planIdentityAfter.HeadCommit -or
        $planIdentityBefore.HeadTree -ne $planIdentityAfter.HeadTree -or
        $planIdentityBefore.WorktreeClean -ne $planIdentityAfter.WorktreeClean -or
        $planIdentityBefore.StatusDigest -ne $planIdentityAfter.StatusDigest -or
        $planSnapshotBefore.Digest -ne $planSnapshotAfter.Digest) {
        throw "Source moved while the shard plan was created. Retry from a stable clean source."
    }
    $writtenPlan = New-GodotTestShardPlan `
        -SourceHead ([string]$planIdentityAfter.HeadCommit) `
        -SourceTree ([string]$planIdentityAfter.HeadTree) `
        -SourceWorktreeClean ([bool]$planIdentityAfter.WorktreeClean) `
        -SourceStatusDigest ([string]$planIdentityAfter.StatusDigest) `
        -SourceSnapshotDigest ([string]$planSnapshotAfter.Digest) `
        -RunnerSha256 $runnerSourceSha256 `
        -SuiteMode $(if ($IncludeSnapshots) { "full-with-snapshots" } else { "full" }) `
        -HeadlessShardCount $HeadlessShardCount `
        -NativeShardCount $NativeShardCount `
        -TargetNames @($planSelection.ManifestTargets) `
        -TargetGroups @($planTargetGroups)
    $writtenPlanPath = Write-GodotTestRunReceipt `
        -Receipt $writtenPlan `
        -WorkspaceRoot (Get-TestWorkspaceRoot) `
        -OutputPath $WriteShardPlan
    Write-Host ("SHARD PLAN WRITTEN: {0}" -f $writtenPlan.Digest) -ForegroundColor Green
    Write-Host ("  HEAD: {0}; shards: {1}; targets: {2}; algorithm: {3}" -f $writtenPlan.SourceHead, $writtenPlan.ShardCount, $writtenPlan.TargetCount, $writtenPlan.Algorithm)
    Write-Host ("  Plan file: {0}" -f $writtenPlanPath)
    exit 0
}

if ($hasAggregateShardReceipts -and -not $aggregateMode) {
    throw "-AggregateShardReceipt requires -ShardPlan, must not use -ShardId, and cannot be empty."
}
if ($aggregateMode) {
    $aggregateForbiddenParameters = @(
        "GodotConsolePath", "Full", "IncludeSnapshots", "Target", "NativeTarget", "TargetUserArgument",
        "TargetUserArgumentsJson", "TargetUserArgumentsBase64", "NativeMovieOutputPath", "NativeMovieFps",
        "KeepWorkspace", "VerifyRunReceipt", "CandidateReceipt", "WriteShardPlan", "HeadlessShardCount",
        "NativeShardCount", "ShardId", "InPlace", "ImportTimeoutSeconds", "TestTimeoutSeconds", "AllowNativeSkip"
    )
    $providedAggregateForbidden = @($aggregateForbiddenParameters | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if ([string]::IsNullOrWhiteSpace($RunReceiptOutputPath) -or $providedAggregateForbidden.Count -gt 0) {
        throw "Shard aggregation requires only -ShardPlan, -AggregateShardReceipt and -RunReceiptOutputPath; forbidden: $($providedAggregateForbidden -join ', ')."
    }
    Assert-RunnerInvocationMode -InPlaceRequested $false
    Assert-TrackedLfEol -ProjectRoot $sourceProjectRoot
    $aggregatePlan = Read-GodotTestShardPlan -PlanPath $ShardPlan
    $aggregateIdentityBefore = Get-GitSourceIdentity -ProjectRoot $sourceProjectRoot
    $aggregateSnapshotBefore = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceProjectRoot
    [void](Assert-GodotTestShardPlanSourceBinding `
        -Plan $aggregatePlan `
        -CurrentIdentity $aggregateIdentityBefore `
        -CurrentSnapshot $aggregateSnapshotBefore `
        -CurrentRunnerSha256 $runnerSourceSha256)
    $parsedShardReceipts = @($AggregateShardReceipt | ForEach-Object {
        Read-GodotTestShardReceipt -ReceiptPath $_
    })
    $aggregateReceipt = Merge-GodotTestShardReceipts -Plan $aggregatePlan -ShardReceipts $parsedShardReceipts
    $aggregateSnapshotAfter = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceProjectRoot
    $aggregateIdentityAfter = Get-GitSourceIdentity -ProjectRoot $sourceProjectRoot
    [void](Assert-GodotTestShardPlanSourceBinding `
        -Plan $aggregatePlan `
        -CurrentIdentity $aggregateIdentityAfter `
        -CurrentSnapshot $aggregateSnapshotAfter `
        -CurrentRunnerSha256 $runnerSourceSha256)
    if ($aggregateSnapshotBefore.Digest -ne $aggregateSnapshotAfter.Digest) {
        throw "Source moved while shard receipts were aggregated."
    }
    $aggregatePath = Write-GodotTestRunReceipt `
        -Receipt $aggregateReceipt `
        -WorkspaceRoot (Get-TestWorkspaceRoot) `
        -OutputPath $RunReceiptOutputPath
    Write-Host ("AGGREGATE RECEIPT WRITTEN: {0}" -f $aggregateReceipt.Digest) -ForegroundColor Green
    Write-Host ("  shards: {0}/{0}; targets: {1}/{1} PASS" -f $aggregateReceipt.ShardCount, $aggregateReceipt.TargetCount)
    Write-Host ("  Receipt file: {0}" -f $aggregatePath)
    exit 0
}

if (($hasShardPlan -or $hasShardId) -and -not $shardMode) {
    throw "Shard execution requires both -ShardPlan and -ShardId, with no aggregate receipts."
}
if ($shardMode) {
    $shardForbiddenParameters = @(
        "Full", "IncludeSnapshots", "Target", "NativeTarget", "TargetUserArgument", "TargetUserArgumentsJson",
        "TargetUserArgumentsBase64", "NativeMovieOutputPath", "NativeMovieFps", "VerifyRunReceipt",
        "CandidateReceipt", "WriteShardPlan", "HeadlessShardCount", "NativeShardCount", "AggregateShardReceipt",
        "InPlace", "AllowNativeSkip"
    )
    $providedShardForbidden = @($shardForbiddenParameters | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if ([string]::IsNullOrWhiteSpace($RunReceiptOutputPath) -or $providedShardForbidden.Count -gt 0) {
        throw "Shard execution requires a plan, shard ID and output receipt; forbidden: $($providedShardForbidden -join ', ')."
    }
    Assert-RunnerInvocationMode -InPlaceRequested $false
    Assert-TrackedLfEol -ProjectRoot $sourceProjectRoot
    $activeShardPlan = Read-GodotTestShardPlan -PlanPath $ShardPlan
    $shardIdentityBefore = Get-GitSourceIdentity -ProjectRoot $sourceProjectRoot
    $shardSnapshotBefore = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceProjectRoot
    [void](Assert-GodotTestShardPlanSourceBinding `
        -Plan $activeShardPlan `
        -CurrentIdentity $shardIdentityBefore `
        -CurrentSnapshot $shardSnapshotBefore `
        -CurrentRunnerSha256 $runnerSourceSha256)
    $matchingShards = @($activeShardPlan.Shards | Where-Object Id -ceq $ShardId)
    if ($matchingShards.Count -ne 1) {
        throw "Shard ID '$ShardId' is not an exact member of the plan."
    }
    $activePlannedShard = $matchingShards[0]
    $activeShardTargets = @($activeShardPlan.Targets | Where-Object ShardId -ceq $ShardId | Sort-Object LocalIndex)
    if ($activeShardTargets.Count -ne $activePlannedShard.TargetCount -or $activeShardTargets.Count -lt 1) {
        throw "Shard '$ShardId' has an invalid or empty target assignment."
    }
}

if (-not $hasWriteShardPlan -and -not $aggregateMode -and -not $shardMode) {
    $unusedShardParameters = @(
        "WriteShardPlan", "HeadlessShardCount", "NativeShardCount", "ShardPlan", "ShardId", "AggregateShardReceipt"
    ) | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if (@($unusedShardParameters).Count -gt 0) {
        throw "Shard parameters cannot be ignored by a non-sharded invocation: $(@($unusedShardParameters) -join ', ')."
    }
}

$hasRunReceiptVerification = -not [string]::IsNullOrWhiteSpace($VerifyRunReceipt)
$hasCandidateReceipt = -not [string]::IsNullOrWhiteSpace($CandidateReceipt)
if ($hasRunReceiptVerification -xor $hasCandidateReceipt) {
    throw "-VerifyRunReceipt and -CandidateReceipt must be provided together."
}
if ($hasRunReceiptVerification) {
    $forbiddenVerificationParameters = @(
        "GodotConsolePath", "Full", "IncludeSnapshots", "Target", "NativeTarget",
        "TargetUserArgument", "TargetUserArgumentsJson", "TargetUserArgumentsBase64",
        "NativeMovieOutputPath", "NativeMovieFps", "KeepWorkspace", "RunReceiptOutputPath",
        "WriteShardPlan", "HeadlessShardCount", "NativeShardCount", "ShardPlan", "ShardId",
        "AggregateShardReceipt", "InPlace", "ImportTimeoutSeconds", "TestTimeoutSeconds", "AllowNativeSkip"
    )
    $providedForbiddenParameters = @($forbiddenVerificationParameters | Where-Object {
        $PSBoundParameters.ContainsKey($_)
    })
    if ($providedForbiddenParameters.Count -gt 0) {
        throw "Run receipt verification cannot be combined with test execution parameters: $($providedForbiddenParameters -join ', ')."
    }
    $verifiedRunReceipt = Test-GodotTestRunReceipt `
        -ProjectRoot $sourceProjectRoot `
        -RunReceiptPath $VerifyRunReceipt `
        -CandidateReceiptPath $CandidateReceipt `
        -CurrentRunnerSha256 $runnerSourceSha256 `
        -FullHeadlessScriptTests $fullHeadlessScriptTests `
        -FullHeadlessFlowScenes $fullHeadlessFlowScenes `
        -SnapshotScenes $nativeSnapshotScenes
    Write-Host ("RUN RECEIPT VERIFIED: {0}" -f $verifiedRunReceipt.Digest) -ForegroundColor Green
    Write-Host ("  HEAD:  {0}" -f $verifiedRunReceipt.SourceHead)
    Write-Host ("  tree:  {0}" -f $verifiedRunReceipt.SourceTree)
    Write-Host ("  suite: {0}, {1}/{1} PASS, 0 FAIL, 0 SKIP" -f $verifiedRunReceipt.SuiteMode, $verifiedRunReceipt.TargetCount)
    exit 0
}

$resolvedTargetUserArguments = @($TargetUserArgument)
$targetUserArgumentsPayload = $TargetUserArgumentsJson
$targetUserArgumentsPayloadParameter = "-TargetUserArgumentsJson"
if (-not [string]::IsNullOrWhiteSpace($TargetUserArgumentsBase64)) {
    if (-not [string]::IsNullOrWhiteSpace($TargetUserArgumentsJson)) {
        throw "-TargetUserArgumentsJson and -TargetUserArgumentsBase64 are mutually exclusive."
    }
    try {
        $payloadBytes = [Convert]::FromBase64String($TargetUserArgumentsBase64.Trim())
        $targetUserArgumentsPayload = [Text.Encoding]::UTF8.GetString($payloadBytes)
    }
    catch {
        throw "-TargetUserArgumentsBase64 must contain Base64-encoded UTF-8 JSON: $($_.Exception.Message)"
    }
    $targetUserArgumentsPayloadParameter = "-TargetUserArgumentsBase64"
}
if (-not [string]::IsNullOrWhiteSpace($targetUserArgumentsPayload)) {
    if ($resolvedTargetUserArguments.Count -gt 0) {
        throw "-TargetUserArgument and $targetUserArgumentsPayloadParameter are mutually exclusive."
    }
    if (-not $targetUserArgumentsPayload.TrimStart().StartsWith("[")) {
        throw "$targetUserArgumentsPayloadParameter must represent a JSON array of strings."
    }
    try {
        $decodedTargetUserArguments = $targetUserArgumentsPayload | ConvertFrom-Json -ErrorAction Stop
        $decodedTargetUserArguments = @($decodedTargetUserArguments)
    }
    catch {
        throw "$targetUserArgumentsPayloadParameter must represent a JSON array of strings: $($_.Exception.Message)"
    }
    if ($decodedTargetUserArguments.Count -eq 0 -or @($decodedTargetUserArguments | Where-Object { $_ -isnot [string] }).Count -gt 0) {
        throw "$targetUserArgumentsPayloadParameter must represent a non-empty JSON array containing only strings."
    }
    $resolvedTargetUserArguments = @($decodedTargetUserArguments | ForEach-Object { [string]$_ })
}

$hasTarget = -not [string]::IsNullOrWhiteSpace($Target)
$hasNativeTarget = -not [string]::IsNullOrWhiteSpace($NativeTarget)
$hasTargetUserArguments = $resolvedTargetUserArguments.Count -gt 0
$hasNativeMovieOutput = -not [string]::IsNullOrWhiteSpace($NativeMovieOutputPath)
if ($hasTarget -and $hasNativeTarget) {
    throw "-Target and -NativeTarget are mutually exclusive."
}
if (($hasTarget -or $hasNativeTarget) -and ($Full -or $IncludeSnapshots)) {
    throw "-Target and -NativeTarget cannot be combined with -Full or -IncludeSnapshots."
}
if ($InPlace -and $KeepWorkspace) {
    throw "-KeepWorkspace applies only to the default isolated workspace mode and cannot be combined with -InPlace."
}
Assert-RunnerInvocationMode -InPlaceRequested ([bool]$InPlace)
Assert-TrackedLfEol -ProjectRoot $sourceProjectRoot
if ($hasTargetUserArguments -and -not ($hasTarget -or $hasNativeTarget)) {
    throw "Target user arguments require -Target or -NativeTarget."
}
if ($hasNativeMovieOutput -and -not $hasNativeTarget) {
    throw "-NativeMovieOutputPath requires -NativeTarget."
}

$resolvedNativeMovieOutputPath = $null
if ($hasNativeMovieOutput) {
    $expandedMoviePath = [Environment]::ExpandEnvironmentVariables($NativeMovieOutputPath.Trim())
    if (-not [System.IO.Path]::IsPathRooted($expandedMoviePath)) {
        throw "-NativeMovieOutputPath must be an absolute path outside the project: '$NativeMovieOutputPath'."
    }
    $resolvedNativeMovieOutputPath = [System.IO.Path]::GetFullPath($expandedMoviePath)
    $movieExtension = [System.IO.Path]::GetExtension($resolvedNativeMovieOutputPath).ToLowerInvariant()
    if ($movieExtension -notin @(".avi", ".ogv", ".png")) {
        throw "-NativeMovieOutputPath must use a Godot Movie Maker extension: .avi, .ogv or .png."
    }
    $sourcePrefix = $sourceProjectRoot.TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedNativeMovieOutputPath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "-NativeMovieOutputPath must stay outside the source project: '$resolvedNativeMovieOutputPath'."
    }
    $workspacePrefix = (Get-TestWorkspaceRoot).TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedNativeMovieOutputPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "-NativeMovieOutputPath must stay outside disposable test workspaces: '$resolvedNativeMovieOutputPath'."
    }
    $movieDirectory = [System.IO.Path]::GetDirectoryName($resolvedNativeMovieOutputPath)
    if ([string]::IsNullOrWhiteSpace($movieDirectory)) {
        throw "-NativeMovieOutputPath has no parent directory: '$resolvedNativeMovieOutputPath'."
    }
    [void](New-Item -ItemType Directory -Path $movieDirectory -Force)
}

$resolvedTarget = $null
$targetUsesNativeWindow = $false
if ($hasTarget) {
    $resolvedTarget = Resolve-TestTarget `
        -RequestedTarget $Target `
        -SourceProjectRoot $sourceProjectRoot `
        -ParameterName "-Target"
}
elseif ($hasNativeTarget) {
    $resolvedTarget = Resolve-TestTarget `
        -RequestedTarget $NativeTarget `
        -SourceProjectRoot $sourceProjectRoot `
        -ParameterName "-NativeTarget"
    $targetUsesNativeWindow = $true
}

if ($hasNativeMovieOutput -and [System.IO.Path]::GetExtension($resolvedTarget).ToLowerInvariant() -ne ".tscn") {
    throw "-NativeMovieOutputPath requires a native .tscn target so the production renderer is preserved."
}

$godotExecutable = Find-GodotConsole -RequestedPath $GodotConsolePath
$godotVersion = Get-GodotVersionString -GodotExecutable $godotExecutable
$workspaceRoot = Get-TestWorkspaceRoot
$workspacePath = $null
$sourceSnapshotReceipt = $null
$testOverlayReceipt = $null
$structureOverlayReceipt = $null
$runContext = New-IsolatedTestRunContext
$targetWorkspacePaths = [System.Collections.Generic.List[string]]::new()
$exitCode = 1

try {
    $sourceSnapshotReceipt = New-IsolatedTestWorkspace `
        -SourceProjectRoot $sourceProjectRoot `
        -WorkspaceRoot $workspaceRoot
    $runnerSnapshotEntries = @($sourceSnapshotReceipt.SourceSnapshot.Entries | Where-Object RelativePath -ceq "tests/run_all_tests.ps1")
    if ($runnerSnapshotEntries.Count -ne 1 -or
        -not $runnerSnapshotEntries[0].Exists -or
        [string]$runnerSnapshotEntries[0].Sha256 -ne $runnerSourceSha256) {
        throw "The executing runner changed before the immutable source snapshot was closed. Retry from a stable runner revision."
    }
    if ($shardMode) {
        [void](Assert-GodotTestShardPlanSourceBinding `
            -Plan $activeShardPlan `
            -CurrentIdentity $sourceSnapshotReceipt.SourceIdentity `
            -CurrentSnapshot $sourceSnapshotReceipt.SourceSnapshot `
            -CurrentRunnerSha256 $runnerSourceSha256)
    }
    $workspacePath = [string]$sourceSnapshotReceipt.WorkspacePath
    $projectRoot = $workspacePath
    $structureTargetId = Get-ExplicitStructureTestPackageId -ResolvedTarget $resolvedTarget
    if ($null -ne $structureTargetId) {
        $structureOverlayReceipt = Invoke-IsolatedStructureTargetOverlay `
            -SourceProjectRoot $sourceProjectRoot `
            -IsolatedProjectRoot $projectRoot `
            -StructureId $structureTargetId `
            -SourceSnapshotDigest ([string]$sourceSnapshotReceipt.SourceSnapshot.Digest) `
            -TimeoutSeconds $ImportTimeoutSeconds
        Write-Host ("  Structure overlay: {0} ({1}, {2} files, package={3})" -f $structureOverlayReceipt.Digest, $structureOverlayReceipt.Version, $structureOverlayReceipt.FileCount, $structureOverlayReceipt.StructureId)
    }
    else {
        $structureOverlayReceipt = [pscustomobject]@{
            Version = "none"
            Digest = "none"
            StructureId = ""
            FileCount = 0
            ContentDigest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            CanonicalFileManifest = ""
        }
    }
    $testOverlayReceipt = Set-IsolatedGodotRunConfiguration `
        -SourceProjectRoot $sourceProjectRoot `
        -IsolatedProjectRoot $projectRoot `
        -RunContext $runContext `
        -SourceSnapshot $sourceSnapshotReceipt.SourceSnapshot
    Write-Host ("  Test overlay:   {0} ({1}, project.godot {2} -> {3})" -f $testOverlayReceipt.Digest, $testOverlayReceipt.Version, $testOverlayReceipt.BeforeSha256, $testOverlayReceipt.AfterSha256)
    Assert-ProjectGodotCacheAvailable -ProjectRoot $projectRoot

    $testSelection = if ($shardMode) {
        [pscustomobject]@{
            HeadlessScriptTests = @($activeShardTargets | Where-Object Group -ceq "headless script" | ForEach-Object Name)
            ManifestTargets = @($activeShardTargets | ForEach-Object Name)
        }
    }
    else {
        Get-RunnerTestSelection `
            -ResolvedTarget $resolvedTarget `
            -ProjectRoot $projectRoot `
            -FullSuite ([bool]$Full) `
            -IncludeSnapshotScenes ([bool]$IncludeSnapshots) `
            -DefaultHeadlessScriptTests $headlessScriptTests `
            -DefaultHeadlessFlowScenes $headlessFlowScenes `
            -SnapshotScenes $nativeSnapshotScenes
    }
    $headlessScriptTests = @($testSelection.HeadlessScriptTests)
    $manifestTargets = @($testSelection.ManifestTargets)
    $missingTargets = @($manifestTargets | Where-Object {
        $projectRelativeTarget = ConvertTo-TestProjectRelativePath -TargetName ([string]$_)
        $relativeTarget = $projectRelativeTarget.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        -not (Test-Path -LiteralPath (Join-Path $projectRoot $relativeTarget) -PathType Leaf)
    })
    if ($missingTargets.Count -gt 0) {
        throw "The test manifest references missing files in the FROZEN project snapshot: $($missingTargets -join ', ')"
    }

    $importReceipt = Invoke-GodotImportPreflight `
        -GodotExecutable $godotExecutable `
        -ProjectRoot $projectRoot `
        -TimeoutSeconds $ImportTimeoutSeconds `
        -RunContext $runContext
    $importedSeedFingerprint = Get-IsolatedWorkspaceInputFingerprint -ProjectRoot $projectRoot
    if ($importReceipt.InputAfterDigest -ne $importedSeedFingerprint.Digest -or
        $importReceipt.TransitionVersion -ne "godot-import-input-transition-v1" -or
        $importReceipt.TransitionDigest -notmatch '^[0-9a-f]{64}$') {
        throw "Imported seed does not match the trusted import transition receipt."
    }

    $testCases = [System.Collections.Generic.List[object]]::new()
    if ($shardMode) {
        foreach ($plannedTarget in $activeShardTargets) {
            $targetResourcePath = ConvertTo-TestResourcePath -TargetName ([string]$plannedTarget.Name)
            $targetArguments = switch ([string]$plannedTarget.Group) {
                "headless script" { @("--headless", "--path", $projectRoot, "--script", $targetResourcePath); break }
                "headless flow" { @("--headless", "--path", $projectRoot, $targetResourcePath); break }
                "native window" { @("--path", $projectRoot, "--rendering-method", "gl_compatibility", "--script", $targetResourcePath); break }
                "native snapshot" { @("--path", $projectRoot, $targetResourcePath); break }
                default { throw "Planned target '$($plannedTarget.Name)' has unsupported group '$($plannedTarget.Group)'." }
            }
            $testCases.Add((New-TestCase `
                -Name ([string]$plannedTarget.Name) `
                -Group ([string]$plannedTarget.Group) `
                -NativeWindow ([bool]$plannedTarget.NativeWindow) `
                -Arguments $targetArguments))
        }
    }
    elseif ($null -ne $resolvedTarget) {
        $targetExtension = [System.IO.Path]::GetExtension($resolvedTarget).ToLowerInvariant()
        $isNativeTarget = $targetUsesNativeWindow
        $targetResourcePath = "res://$resolvedTarget"
        if ($targetExtension -eq ".gd") {
            $targetArguments = if ($isNativeTarget) {
                @("--path", $projectRoot, "--rendering-method", "gl_compatibility", "--script", $targetResourcePath)
            }
            else {
                @("--headless", "--path", $projectRoot, "--script", $targetResourcePath)
            }
            $targetGroup = if ($isNativeTarget) { "native window" } else { "headless script" }
        }
        else {
            $targetArguments = if ($isNativeTarget) {
                $nativeSceneArguments = @("--path", $projectRoot)
                if ($null -ne $resolvedNativeMovieOutputPath) {
                    $nativeSceneArguments += @(
                        "--write-movie", $resolvedNativeMovieOutputPath,
                        "--fixed-fps", [string]$NativeMovieFps,
                        "--disable-vsync"
                    )
                }
                $nativeSceneArguments + @($targetResourcePath)
            }
            else {
                @("--headless", "--path", $projectRoot, $targetResourcePath)
            }
            $targetGroup = if ($isNativeTarget) { "native snapshot" } else { "headless flow" }
        }
        $testCases.Add((New-TestCase `
            -Name $resolvedTarget `
            -Group $targetGroup `
            -NativeWindow $isNativeTarget `
            -UserArguments @($resolvedTargetUserArguments) `
            -Arguments $targetArguments))
    }
    else {
        foreach ($scriptName in $headlessScriptTests) {
            $scriptResourcePath = ConvertTo-TestResourcePath -TargetName $scriptName
            $testCases.Add((New-TestCase `
                -Name $scriptName `
                -Group "headless script" `
                -Arguments @("--headless", "--path", $projectRoot, "--script", $scriptResourcePath)))
        }

        if ($Full) {
            $testCases.Add((New-TestCase `
                -Name "native_window_settings_test.gd" `
                -Group "native window" `
                -NativeWindow $true `
                -Arguments @("--path", $projectRoot, "--rendering-method", "gl_compatibility", "--script", "res://tests/native_window_settings_test.gd")))
        }

        foreach ($sceneName in $headlessFlowScenes) {
            $sceneResourcePath = ConvertTo-TestResourcePath -TargetName $sceneName
            $testCases.Add((New-TestCase `
                -Name $sceneName `
                -Group "headless flow" `
                -Arguments @("--headless", "--path", $projectRoot, $sceneResourcePath)))
        }

        if ($IncludeSnapshots) {
            foreach ($sceneName in $nativeSnapshotScenes) {
                $sceneResourcePath = ConvertTo-TestResourcePath -TargetName $sceneName
                $testCases.Add((New-TestCase `
                    -Name $sceneName `
                    -Group "native snapshot" `
                    -NativeWindow $true `
                    -Arguments @("--path", $projectRoot, $sceneResourcePath)))
            }
        }
    }

    if ($shardMode) {
        Set-NativeShardDummyAudio `
            -TestCases @($testCases) `
            -ShardLane ([string]$activePlannedShard.Lane)
    }

    $suiteDescription = if ($shardMode) {
        "planned shard '$($activePlannedShard.Id)' ($($activePlannedShard.Lane), $($activeShardTargets.Count) targets)"
    }
    elseif ($null -ne $resolvedTarget) {
        "{0} target '$resolvedTarget'" -f $(if ($targetUsesNativeWindow) { "native" } else { "headless" })
    }
    else {
        "{0} ({1} headless scripts + {2} headless flows{3}{4})" -f `
            $(if ($Full) { "full" } else { "quick" }), `
            $headlessScriptTests.Count, `
            $headlessFlowScenes.Count, `
            $(if ($Full) { " + 1 native window" } else { "" }), `
            $(if ($IncludeSnapshots) { " + $($nativeSnapshotScenes.Count) native snapshots" } else { "" })
    }

    Write-Host "Godot test runner"
    Write-Host ("  Godot:     {0}" -f $godotExecutable)
    Write-Host ("  Source:    {0}" -f $sourceProjectRoot)
    Write-Host ("  Project:   {0}" -f $projectRoot)
    Write-Host "  Isolation: immutable imported seed + fresh workspace/user/temp/ports per target"
    Write-Host ("  Import ID: {0}" -f $runContext.RunId)
    Write-Host ("  Seed:      {0} ({1} immutable input files)" -f $importedSeedFingerprint.Digest, $importedSeedFingerprint.FileCount)
    Write-Host ("  Ports:     import debug={0}, DAP={1}, LSP={2}" -f $runContext.DebugServerPort, $runContext.DapPort, $runContext.LspPort)
    Write-Host ("  Suite:     {0}" -f $suiteDescription)
    if (@($testCases | Where-Object { $_.NativeWindow }).Count -gt 0) {
        Write-Host ("  Native SKIP policy: {0}" -f $(if ($AllowNativeSkip) { "allowed" } else { "required; SKIP fails the run" }))
    }
    Write-Host ""

    $results = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $testCases.Count; $index++) {
        $targetWorkspacePath = $null
        $targetContext = $null
        $targetResult = $null
        try {
            $targetMaterialization = New-IsolatedTargetWorkspace `
                -SeedProjectRoot $projectRoot `
                -WorkspaceRoot $workspaceRoot `
                -TargetIndex $index `
                -ExpectedSeedFingerprint $importedSeedFingerprint
            $targetWorkspacePath = [string]$targetMaterialization.WorkspacePath
            $targetWorkspacePaths.Add($targetWorkspacePath)
            $targetContext = New-IsolatedTestRunContext
            $targetOverlay = Set-IsolatedGodotTargetConfiguration `
                -SeedProjectRoot $projectRoot `
                -TargetProjectRoot $targetWorkspacePath `
                -RunContext $targetContext
            $targetTestCase = Copy-TestCaseForWorkspace `
                -TestCase $testCases[$index] `
                -SeedProjectRoot $projectRoot `
                -TargetProjectRoot $targetWorkspacePath
            Assert-ProjectGodotCacheAvailable -ProjectRoot $targetWorkspacePath
            $targetResult = Invoke-GodotTest `
                -GodotExecutable $godotExecutable `
                -TestCase $targetTestCase `
                -Index ($index + 1) `
                -Total $testCases.Count `
                -RunContext $targetContext `
                -ProjectRoot $targetWorkspacePath
            $targetResult | Add-Member -NotePropertyName TargetOverlayVersion -NotePropertyValue ([string]$targetOverlay.Version)
            $targetResult | Add-Member -NotePropertyName TargetOverlayDigest -NotePropertyValue ([string]$targetOverlay.Digest)
            $results.Add($targetResult)
        }
        finally {
            if ($null -ne $targetContext) {
                try {
                    Complete-IsolatedTestUserDirectory `
                        -RunContext $targetContext `
                        -Preserve ([bool]($KeepWorkspace -or ($null -eq $targetResult) -or $targetResult.BlockingFailure))
                }
                finally {
                    Release-IsolatedTestRunContext -RunContext $targetContext
                }
            }
            if ($null -ne $targetWorkspacePath -and -not $KeepWorkspace) {
                Remove-IsolatedTestWorkspace -WorkspacePath $targetWorkspacePath -WorkspaceRoot $workspaceRoot
                [void]$targetWorkspacePaths.Remove($targetWorkspacePath)
            }
        }
    }

    $passCount = @($results | Where-Object { $_.Status -eq "PASS" }).Count
    $skipCount = @($results | Where-Object { $_.Status -eq "SKIP" }).Count
    $blockingFailureCount = @($results | Where-Object { $_.BlockingFailure }).Count
    $ordinaryFailureCount = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

    Write-Host ""
    Write-Host "Godot test summary"
    Write-Host ("  PASS: {0}" -f $passCount) -ForegroundColor Green
    Write-Host ("  FAIL: {0}" -f $ordinaryFailureCount) -ForegroundColor $(if ($ordinaryFailureCount -gt 0) { "Red" } else { "Gray" })
    Write-Host ("  SKIP: {0}" -f $skipCount) -ForegroundColor $(if ($skipCount -gt 0) { "Yellow" } else { "Gray" })
    Write-Host ("  TOTAL: {0}" -f $results.Count)

    if ($blockingFailureCount -gt 0) {
        Write-Host "  BLOCKING:" -ForegroundColor Red
        foreach ($blockingResult in @($results | Where-Object { $_.BlockingFailure })) {
            Write-Host ("    - {0} [{1}]: {2}" -f $blockingResult.Name, $blockingResult.Status, $blockingResult.Reason) -ForegroundColor Red
        }
        Write-Host ("OVERALL: FAIL ({0} blocking result(s); a required SKIP is blocking)" -f $blockingFailureCount) -ForegroundColor Red
        $exitCode = 1
    }
    else {
        Write-Host "OVERALL: PASS" -ForegroundColor Green
        $exitCode = 0
    }

    $suiteMode = if ($hasNativeTarget) {
        "native-target"
    }
    elseif ($hasTarget) {
        "target"
    }
    elseif ($Full -and $IncludeSnapshots) {
        "full-with-snapshots"
    }
    elseif ($Full) {
        "full"
    }
    elseif ($IncludeSnapshots) {
        "quick-with-snapshots"
    }
    else {
        "quick"
    }
    $sourceIdentity = $sourceSnapshotReceipt.SourceIdentity
    if ($shardMode) {
        $shardIdentityAfter = Get-GitSourceIdentity -ProjectRoot $sourceProjectRoot
        $shardSnapshotAfter = Get-ProjectSnapshotFingerprint -ProjectRoot $sourceProjectRoot
        [void](Assert-GodotTestShardPlanSourceBinding `
            -Plan $activeShardPlan `
            -CurrentIdentity $shardIdentityAfter `
            -CurrentSnapshot $shardSnapshotAfter `
            -CurrentRunnerSha256 $runnerSourceSha256)
        $shardResults = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $results.Count; $index++) {
            $plannedTarget = $activeShardTargets[$index]
            $result = $results[$index]
            $shardResults.Add([pscustomobject]@{
                TargetIndex = [int]$plannedTarget.TargetIndex
                LocalIndex = [int]$plannedTarget.LocalIndex
                Name = [string]$result.Name
                Group = [string]$result.Group
                NativeWindow = [bool]$plannedTarget.NativeWindow
                Status = [string]$result.Status
                ExitCode = [int]$result.ExitCode
                BlockingFailure = [bool]$result.BlockingFailure
                RunId = [string]$result.RunId
                UserDirectoryName = [string]$result.UserDirectoryName
                InputBeforeDigest = [string]$result.InputBeforeDigest
                InputAfterDigest = [string]$result.InputAfterDigest
                InvocationDigest = [string]$result.InvocationDigest
                OutputDigest = [string]$result.OutputDigest
                CompletionVersion = [string]$result.CompletionVersion
                CompletionDigest = [string]$result.CompletionDigest
                TargetOverlayVersion = [string]$result.TargetOverlayVersion
                TargetOverlayDigest = [string]$result.TargetOverlayDigest
            })
        }
        $runReceipt = New-GodotTestShardReceipt `
            -PlanDigest $activeShardPlan.Digest `
            -ShardId $activePlannedShard.Id `
            -ShardLane $activePlannedShard.Lane `
            -SourceHead ([string]$sourceIdentity.HeadCommit) `
            -SourceTree ([string]$sourceIdentity.HeadTree) `
            -SourceWorktreeClean ([bool]$sourceIdentity.WorktreeClean) `
            -SourceStatusDigest ([string]$sourceIdentity.StatusDigest) `
            -SourceSnapshotDigest ([string]$sourceSnapshotReceipt.SourceSnapshot.Digest) `
            -TestOverlayDigest ([string]$testOverlayReceipt.Digest) `
            -TestOverlayVersion ([string]$testOverlayReceipt.Version) `
            -OverlayProjectBeforeSha256 ([string]$testOverlayReceipt.BeforeSha256) `
            -OverlayProjectAfterSha256 ([string]$testOverlayReceipt.AfterSha256) `
            -OverlayRunId ([string]$testOverlayReceipt.RunId) `
            -OverlayUserDirectoryName ([string]$testOverlayReceipt.UserDirectoryName) `
            -RunnerSha256 $runnerSourceSha256 `
            -GodotVersion $godotVersion `
            -DebugServerPort ([int]$runContext.DebugServerPort) `
            -DapPort ([int]$runContext.DapPort) `
            -LspPort ([int]$runContext.LspPort) `
            -Results @($shardResults)
    }
    else {
        $runReceipt = New-GodotTestRunReceipt `
            -SourceHead ([string]$sourceIdentity.HeadCommit) `
            -SourceTree ([string]$sourceIdentity.HeadTree) `
            -SourceWorktreeClean ([bool]$sourceIdentity.WorktreeClean) `
            -SourceStatusDigest ([string]$sourceIdentity.StatusDigest) `
            -SourceSnapshotDigest ([string]$sourceSnapshotReceipt.SourceSnapshot.Digest) `
            -TestOverlayDigest ([string]$testOverlayReceipt.Digest) `
            -TestOverlayVersion ([string]$testOverlayReceipt.Version) `
            -OverlayProjectBeforeSha256 ([string]$testOverlayReceipt.BeforeSha256) `
            -OverlayProjectAfterSha256 ([string]$testOverlayReceipt.AfterSha256) `
            -OverlayRunId ([string]$testOverlayReceipt.RunId) `
            -OverlayUserDirectoryName ([string]$testOverlayReceipt.UserDirectoryName) `
            -StructureOverlayVersion ([string]$structureOverlayReceipt.Version) `
            -StructureOverlayDigest ([string]$structureOverlayReceipt.Digest) `
            -StructureOverlayId ([string]$structureOverlayReceipt.StructureId) `
            -StructureOverlayFileCount ([int]$structureOverlayReceipt.FileCount) `
            -StructureOverlayContentDigest ([string]$structureOverlayReceipt.ContentDigest) `
            -StructureOverlayManifest ([string]$structureOverlayReceipt.CanonicalFileManifest) `
            -RunnerSha256 $runnerSourceSha256 `
            -GodotVersion $godotVersion `
            -SuiteMode $suiteMode `
            -NativeSkipPolicy $(if ($AllowNativeSkip) { "allowed" } else { "blocking" }) `
            -DebugServerPort ([int]$runContext.DebugServerPort) `
            -DapPort ([int]$runContext.DapPort) `
            -LspPort ([int]$runContext.LspPort) `
            -Results @($results)
    }
    $runReceiptPath = Write-GodotTestRunReceipt `
        -Receipt $runReceipt `
        -WorkspaceRoot $workspaceRoot `
        -OutputPath $RunReceiptOutputPath
    Write-Host ("Run receipt: {0} ({1}, overall={2}; evidence only, not last-green)" -f $runReceipt.Digest, $runReceipt.Version, $runReceipt.Overall)
    Write-Host ("  Receipt file: {0}" -f $runReceiptPath)
}
finally {
    foreach ($targetWorkspacePath in @($targetWorkspacePaths)) {
        if ($KeepWorkspace) {
            Write-Host ("Target workspace preserved: {0}" -f $targetWorkspacePath) -ForegroundColor Yellow
        }
        elseif (Test-Path -LiteralPath $targetWorkspacePath) {
            try {
                Remove-IsolatedTestWorkspace -WorkspacePath $targetWorkspacePath -WorkspaceRoot $workspaceRoot
            }
            catch {
                Write-Warning "Failed to remove target workspace '$targetWorkspacePath': $($_.Exception.Message)"
                $exitCode = 1
            }
        }
    }
    if ($null -ne $workspacePath) {
        if ($KeepWorkspace) {
            Write-Host ("Test workspace preserved: {0}" -f $workspacePath) -ForegroundColor Yellow
        }
        else {
            try {
                Remove-IsolatedTestWorkspace -WorkspacePath $workspacePath -WorkspaceRoot $workspaceRoot
            }
            catch {
                Write-Warning "Failed to remove test workspace '$workspacePath': $($_.Exception.Message)"
                $exitCode = 1
            }
        }
    }
    try {
        Complete-IsolatedTestUserDirectory `
            -RunContext $runContext `
            -Preserve ([bool]($KeepWorkspace -or $exitCode -ne 0))
    }
    catch {
        Write-Warning "Failed to finalize isolated test user://: $($_.Exception.Message)"
        $exitCode = 1
    }
    Release-IsolatedTestRunContext -RunContext $runContext
}

exit $exitCode
