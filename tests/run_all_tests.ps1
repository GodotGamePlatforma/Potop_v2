#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias("GodotPath")]
    [string]$GodotConsolePath,

    [switch]$Full,

    [switch]$IncludeSnapshots,

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
$testSpecificDefaultTimeoutSeconds = @{}

# PowerShell 7 can otherwise promote native stderr to PowerShell errors. Godot's
# stdout and stderr are inspected together below, using the engine's own error
# prefixes and the process exit code as the test contract.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$sourceProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
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
        $normalizedCandidatePath = ConvertTo-NormalizedProjectPath `
            -Candidate $candidatePath `
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

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pythonCommand.Source
        $arguments = @("-B", $builderPath, "--build-structure", $StructureId)
        $startInfo.Arguments = (@($arguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = Join-Path $isolatedRoot "underwater_map_workbench"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
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
    }
    $passCount = @($orderedResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failCount = @($orderedResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $skipCount = @($orderedResults | Where-Object { $_.Status -eq "SKIP" }).Count
    $blockingFailureCount = @($orderedResults | Where-Object { $_.BlockingFailure }).Count
    $overall = if ($blockingFailureCount -eq 0) { "PASS" } else { "FAIL" }

    $receiptLines = [System.Collections.Generic.List[string]]::new()
    $receiptLines.Add("version=godot-test-run-receipt-v1")
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
            "target={0}|{1}|{2}|{3}|{4}|{5}" -f `
                $index, `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.Name)), `
                (ConvertTo-TestRunReceiptField -Value ([string]$result.Group)), `
                ([string]$result.Status), `
                ([int]$result.ExitCode), `
                $(if ([bool]$result.BlockingFailure) { "1" } else { "0" })
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
        Version = "godot-test-run-receipt-v1"
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
            $parts = @($line.Substring(7) -split '\|', 6)
            if ($parts.Count -ne 6 -or $parts[0] -notmatch '^(0|[1-9][0-9]*)$' -or
                $parts[3] -notin @("PASS", "FAIL", "SKIP") -or
                $parts[4] -notmatch '^-?(0|[1-9][0-9]*)$' -or
                $parts[5] -notin @("0", "1")) {
                throw "Test run receipt contains an invalid target record."
            }
            $targetRecords.Add([pscustomobject]@{
                Index = [int]$parts[0]
                Name = ConvertFrom-TestRunReceiptField -Value $parts[1]
                Group = ConvertFrom-TestRunReceiptField -Value $parts[2]
                Status = $parts[3]
                ExitCode = [int]$parts[4]
                BlockingFailure = $parts[5] -eq "1"
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
    if ($scalarValues.version -ne "godot-test-run-receipt-v1" -or
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
    $contractTool = Join-Path $ProjectRoot "tools/workbench_contract.py"
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
            "-B", $contractTool,
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

    $receipt = Read-GodotTestRunReceipt -ReceiptPath $RunReceiptPath
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

function Remove-AnsiEscapes {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }
    return [System.Text.RegularExpressions.Regex]::Replace($Text, $ansiEscapePattern, "")
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
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ostatni_pomost_import_{0}_{1}.log" -f $RunContext.RunId, [Guid]::NewGuid().ToString("N"))
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
            "--lsp-port", [string]$RunContext.LspPort,
            "--log-file", $logPath
        )
        $startInfo.Arguments = (@($processArguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $ProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $false
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $false

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Godot import process could not be started."
        }
        $standardErrorTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            $process.WaitForExit()
            $launchError = "project import timed out after $TimeoutSeconds seconds"
        }
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $standardOutput = Get-Content -LiteralPath $logPath -Raw
        }
    }
    catch {
        $launchError = $_.Exception.Message
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
    }

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
}

function Invoke-GodotTest {
    param(
        [string]$GodotExecutable,
        [pscustomobject]$TestCase,
        [int]$Index,
        [int]$Total,
        [pscustomobject]$RunContext
    )

    Write-Host ("[{0,2}/{1}] RUN  {2} ({3})" -f $Index, $Total, $TestCase.Name, $TestCase.Group)

    $standardOutput = ""
    $standardError = ""
    $exitCode = -1
    $launchError = $null
    $process = $null
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ostatni_pomost_test_{0}_{1}.log" -f $RunContext.RunId, [Guid]::NewGuid().ToString("N"))
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotExecutable
        # Engine options, the scene/script target and the runner-owned log must
        # stay before `--`. Everything after it belongs to the target harness.
        $processArguments = @(
            "--debug-server", $RunContext.DebugServerUri,
            "--dap-port", [string]$RunContext.DapPort,
            "--lsp-port", [string]$RunContext.LspPort
        ) + @($TestCase.Arguments) + @("--log-file", $logPath)
        if (@($TestCase.UserArguments).Count -gt 0) {
            $processArguments += @("--") + @($TestCase.UserArguments)
        }
        $startInfo.Arguments = (@($processArguments) | ForEach-Object {
            ConvertTo-ProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $projectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $false
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $false

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Godot process could not be started."
        }
        $standardErrorTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TestCase.TimeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            $process.WaitForExit()
            $launchError = "test timed out after $($TestCase.TimeoutSeconds) seconds"
        }
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $standardOutput = Get-Content -LiteralPath $logPath -Raw
        }
    }
    catch {
        $launchError = $_.Exception.Message
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
    }

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

    $status = "PASS"
    $blockingFailure = $false
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
        $status = "FAIL"
        $blockingFailure = $true
        $reasons.Add("engine output contains ERROR:/SCRIPT ERROR:")
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
        "InPlace", "ImportTimeoutSeconds", "TestTimeoutSeconds", "AllowNativeSkip"
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

    $testSelection = Get-RunnerTestSelection `
        -ResolvedTarget $resolvedTarget `
        -ProjectRoot $projectRoot `
        -FullSuite ([bool]$Full) `
        -IncludeSnapshotScenes ([bool]$IncludeSnapshots) `
        -DefaultHeadlessScriptTests $headlessScriptTests `
        -DefaultHeadlessFlowScenes $headlessFlowScenes `
        -SnapshotScenes $nativeSnapshotScenes
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

    Invoke-GodotImportPreflight `
        -GodotExecutable $godotExecutable `
        -ProjectRoot $projectRoot `
        -TimeoutSeconds $ImportTimeoutSeconds `
        -RunContext $runContext

    $testCases = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $resolvedTarget) {
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

    $suiteDescription = if ($null -ne $resolvedTarget) {
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
    Write-Host "  Isolation: immutable source snapshot + deterministic test overlay"
    Write-Host ("  Run ID:    {0}" -f $runContext.RunId)
    Write-Host ("  user://:   {0}" -f $runContext.UserDirectoryName)
    Write-Host ("  Ports:     debug={0}, DAP={1}, LSP={2}" -f $runContext.DebugServerPort, $runContext.DapPort, $runContext.LspPort)
    Write-Host ("  Suite:     {0}" -f $suiteDescription)
    if (@($testCases | Where-Object { $_.NativeWindow }).Count -gt 0) {
        Write-Host ("  Native SKIP policy: {0}" -f $(if ($AllowNativeSkip) { "allowed" } else { "required; SKIP fails the run" }))
    }
    Write-Host ""

    $results = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $testCases.Count; $index++) {
        # Each invocation is deliberately awaited before the next process starts.
        Assert-ProjectGodotCacheAvailable -ProjectRoot $projectRoot
        $results.Add((Invoke-GodotTest `
            -GodotExecutable $godotExecutable `
            -TestCase $testCases[$index] `
            -Index ($index + 1) `
            -Total $testCases.Count `
            -RunContext $runContext))
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
    $runReceiptPath = Write-GodotTestRunReceipt `
        -Receipt $runReceipt `
        -WorkspaceRoot $workspaceRoot `
        -OutputPath $RunReceiptOutputPath
    Write-Host ("Run receipt: {0} ({1}, overall={2}; evidence only, not last-green)" -f $runReceipt.Digest, $runReceipt.Version, $runReceipt.Overall)
    Write-Host ("  Receipt file: {0}" -f $runReceiptPath)
}
finally {
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
