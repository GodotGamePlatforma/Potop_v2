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

    [switch]$KeepWorkspace,

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
    "dive_layout_story_regression_test.gd" = 600
    "dive_recovery_certification_test.gd" = 3600
}

# PowerShell 7 can otherwise promote native stderr to PowerShell errors. Godot's
# stdout and stderr are inspected together below, using the engine's own error
# prefixes and the process exit code as the test contract.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$sourceProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$projectRoot = $sourceProjectRoot
$ansiEscapePattern = "(?:\x1B\[[0-?]*[ -/]*[@-~])|(?:\x1B\][^\x07]*(?:\x07|\x1B\\))"

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
    "campaign_story_system_test.gd"
    "competency_system_test.gd"
    "expedition_preparation_selection_test.gd"
    "fixed_device_visual_scene_test.gd"
    "interactable_visual_style_test.gd"
    "macro_terrain_raster_test.gd"
    "narrative_content_test.gd"
    "profession_talent_system_test.gd"
    "production_system_test.gd"
    "roster_rotation_skeleton_test.gd"
    "campaign_format_test.gd"
    "smoke_test.gd"
    "tutorial_flow_test.gd"
    "underwater_environment_test.gd"
    "underwater_map_scene_test.gd"
)

$fullHeadlessScriptTests = @(
    "base_environment_test.gd"
    "building_system_test.gd"
    "campaign_story_system_test.gd"
    "career_progression_system_test.gd"
    "competency_system_test.gd"
    "profession_talent_system_test.gd"
    "continuous_map_collision_test.gd"
    "difficulty_director_test.gd"
    "difficulty_profile_test.gd"
    "difficulty_simulation_test.gd"
    "disease_definition_test.gd"
    "disease_end_of_day_test.gd"
    "disease_system_test.gd"
    "dive_layout_story_regression_test.gd"
    "dive_navigation_snapshot_test.gd"
    "dive_recovery_certification_test.gd"
    "dive_risk_system_test.gd"
    "dive_system_test.gd"
    "dive_visual_chunk_streaming_test.gd"
    "diving_equipment_test.gd"
    "expedition_preparation_selection_test.gd"
    "fixed_device_visual_scene_test.gd"
    "interactable_visual_style_test.gd"
    "macro_terrain_raster_test.gd"
    "mission_system_test.gd"
    "narrative_content_test.gd"
    "persistent_exploration_test.gd"
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
    "underwater_environment_test.gd"
    "underwater_map_scene_test.gd"
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
    "DiseaseEpidemicFlowTest.tscn"
    "DiverPresentationTest.tscn"
    "DiveRiskFlowTest.tscn"
    "IntroFlowTest.tscn"
    "MissionJournalFlowTest.tscn"
    "MorningEventFlowTest.tscn"
    "NarrativeDialogueFlowTest.tscn"
    "PauseMenuFlowTest.tscn"
    "PersistentExplorationFlowTest.tscn"
    "RescueFlowTest.tscn"
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
    "DiveUISnapshot.tscn"
    "IntroVisualSnapshot.tscn"
    "PngWorldSnapshot.tscn"
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

function New-IsolatedTestWorkspace {
    param(
        [string]$SourceProjectRoot,
        [string]$WorkspaceRoot
    )

    [void](New-Item -ItemType Directory -Path $WorkspaceRoot -Force)
    $workspaceName = "run_{0}_{1}_{2}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $PID, [Guid]::NewGuid().ToString("N")
    $workspacePath = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $workspaceName))
    [void](New-Item -ItemType Directory -Path $workspacePath)

    try {
        foreach ($entry in Get-ChildItem -LiteralPath $SourceProjectRoot -Force) {
            if ($entry.Name -iin @(".git", ".godot", "tmp")) {
                continue
            }
            Copy-Item -LiteralPath $entry.FullName -Destination $workspacePath -Recurse -Force
        }
        return $workspacePath
    }
    catch {
        try {
            Remove-IsolatedTestWorkspace -WorkspacePath $workspacePath -WorkspaceRoot $WorkspaceRoot
        }
        catch {
            Write-Warning "Failed to remove incomplete test workspace '$workspacePath': $($_.Exception.Message)"
        }
        throw
    }
}

function Resolve-TestTarget {
    param(
        [string]$RequestedTarget,
        [string]$SourceProjectRoot,
        [string]$ParameterName = "-Target"
    )

    if ([string]::IsNullOrWhiteSpace($RequestedTarget)) {
        throw "$ParameterName requires a .gd script or .tscn scene from the tests directory."
    }

    $testsRoot = [System.IO.Path]::GetFullPath((Join-Path $SourceProjectRoot "tests")).TrimEnd([char[]]"\/")
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
        if ($normalizedRelative.StartsWith("tests/", [StringComparison]::OrdinalIgnoreCase)) {
            $candidatePath = Join-Path $SourceProjectRoot ($normalizedRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        }
        else {
            $candidatePath = Join-Path $testsRoot ($normalizedRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        }
    }

    $absoluteTarget = [System.IO.Path]::GetFullPath($candidatePath)
    $testsPrefix = $testsRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $absoluteTarget.StartsWith($testsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Test target must stay inside '$testsRoot': '$RequestedTarget'."
    }
    if (-not (Test-Path -LiteralPath $absoluteTarget -PathType Leaf)) {
        throw "Test target does not exist: '$RequestedTarget'."
    }

    $extension = [System.IO.Path]::GetExtension($absoluteTarget).ToLowerInvariant()
    if ($extension -notin @(".gd", ".tscn")) {
        throw "Test target must be a .gd script or .tscn scene: '$RequestedTarget'."
    }

    return $absoluteTarget.Substring($testsPrefix.Length).Replace('\', '/')
}

function New-TestCase {
    param(
        [string]$Name,
        [string]$Group,
        [string[]]$Arguments,
        [bool]$NativeWindow = $false
    )

    return [pscustomobject]@{
        Name = $Name
        Group = $Group
        Arguments = $Arguments
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

function Invoke-GodotImportPreflight {
    param(
        [string]$GodotExecutable,
        [string]$ProjectRoot,
        [int]$TimeoutSeconds
    )

    Write-Host "[IMPORT] RUN  isolated project import"

    $standardOutput = ""
    $standardError = ""
    $exitCode = -1
    $launchError = $null
    $process = $null
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ostatni_pomost_import_{0}_{1}.log" -f $PID, [Guid]::NewGuid().ToString("N"))
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotExecutable
        $processArguments = @(
            "--headless",
            "--editor",
            "--path", $ProjectRoot,
            "--import",
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
        [int]$Total
    )

    Write-Host ("[{0,2}/{1}] RUN  {2} ({3})" -f $Index, $Total, $TestCase.Name, $TestCase.Group)

    $standardOutput = ""
    $standardError = ""
    $exitCode = -1
    $launchError = $null
    $process = $null
    $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ostatni_pomost_test_{0}_{1}.log" -f $PID, [Guid]::NewGuid().ToString("N"))
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotExecutable
        $processArguments = @($TestCase.Arguments) + @("--log-file", $logPath)
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

if ($quickHeadlessScriptTests.Count -ne 15 -or
    $quickHeadlessFlowScenes.Count -ne 3 -or
    $fullHeadlessScriptTests.Count -ne 42 -or
    $fullHeadlessFlowScenes.Count -ne 18 -or
    $nativeSnapshotScenes.Count -ne 11) {
    throw "The explicit test manifest has an invalid group size. Expected quick 15+3, full 42+18 and 11 snapshots."
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

$hasTarget = -not [string]::IsNullOrWhiteSpace($Target)
$hasNativeTarget = -not [string]::IsNullOrWhiteSpace($NativeTarget)
if ($hasTarget -and $hasNativeTarget) {
    throw "-Target and -NativeTarget are mutually exclusive."
}
if (($hasTarget -or $hasNativeTarget) -and ($Full -or $IncludeSnapshots)) {
    throw "-Target and -NativeTarget cannot be combined with -Full or -IncludeSnapshots."
}
if ($InPlace -and $KeepWorkspace) {
    throw "-KeepWorkspace applies only to the default isolated workspace mode and cannot be combined with -InPlace."
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

$manifestTargets = if ($null -ne $resolvedTarget) {
    @($resolvedTarget)
}
else {
    @($headlessScriptTests) +
        $(if ($Full) { @("native_window_settings_test.gd") } else { @() }) +
        @($headlessFlowScenes) +
        $(if ($IncludeSnapshots) { @($nativeSnapshotScenes) } else { @() })
}
$missingTargets = @($manifestTargets | Where-Object {
    $relativeTarget = ([string]$_).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    -not (Test-Path -LiteralPath (Join-Path (Join-Path $sourceProjectRoot "tests") $relativeTarget) -PathType Leaf)
})
if ($missingTargets.Count -gt 0) {
    throw "The test manifest references missing files: $($missingTargets -join ', ')"
}

$godotExecutable = Find-GodotConsole -RequestedPath $GodotConsolePath
$workspaceRoot = Get-TestWorkspaceRoot
$workspacePath = $null
$exitCode = 1

try {
    if ($InPlace) {
        $projectRoot = $sourceProjectRoot
        Assert-ProjectGodotCacheAvailable -ProjectRoot $projectRoot
    }
    else {
        $workspacePath = New-IsolatedTestWorkspace `
            -SourceProjectRoot $sourceProjectRoot `
            -WorkspaceRoot $workspaceRoot
        $projectRoot = $workspacePath
        Assert-ProjectGodotCacheAvailable -ProjectRoot $projectRoot
        Invoke-GodotImportPreflight `
            -GodotExecutable $godotExecutable `
            -ProjectRoot $projectRoot `
            -TimeoutSeconds $ImportTimeoutSeconds
    }

    $testCases = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $resolvedTarget) {
        $targetExtension = [System.IO.Path]::GetExtension($resolvedTarget).ToLowerInvariant()
        $isNativeTarget = $targetUsesNativeWindow
        $targetResourcePath = "res://tests/$resolvedTarget"
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
                @("--path", $projectRoot, $targetResourcePath)
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
            -Arguments $targetArguments))
    }
    else {
        foreach ($scriptName in $headlessScriptTests) {
            $testCases.Add((New-TestCase `
                -Name $scriptName `
                -Group "headless script" `
                -Arguments @("--headless", "--path", $projectRoot, "--script", "res://tests/$scriptName")))
        }

        if ($Full) {
            $testCases.Add((New-TestCase `
                -Name "native_window_settings_test.gd" `
                -Group "native window" `
                -NativeWindow $true `
                -Arguments @("--path", $projectRoot, "--rendering-method", "gl_compatibility", "--script", "res://tests/native_window_settings_test.gd")))
        }

        foreach ($sceneName in $headlessFlowScenes) {
            $testCases.Add((New-TestCase `
                -Name $sceneName `
                -Group "headless flow" `
                -Arguments @("--headless", "--path", $projectRoot, "res://tests/$sceneName")))
        }

        if ($IncludeSnapshots) {
            foreach ($sceneName in $nativeSnapshotScenes) {
                $testCases.Add((New-TestCase `
                    -Name $sceneName `
                    -Group "native snapshot" `
                    -NativeWindow $true `
                    -Arguments @("--path", $projectRoot, "res://tests/$sceneName")))
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
    Write-Host ("  Isolation: {0}" -f $(if ($InPlace) { "in-place (explicit)" } else { "external workspace" }))
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
            -Total $testCases.Count))
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
}

exit $exitCode
