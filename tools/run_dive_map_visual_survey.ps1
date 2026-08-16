#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$OutputDirectory,

    [ValidateSet("low", "medium", "high")]
    [string]$Quality = "high",

    [switch]$ReducedMotion,

    [ValidateRange(100, 2400)]
    [int]$CameraSpeed = 600,

    [ValidateRange(1, 240)]
    [int]$MovieFps = 30,

    [ValidateRange(1, 3600)]
    [int]$ImportTimeoutSeconds = 600,

    [ValidateRange(1, 3600)]
    [int]$SurveyTimeoutSeconds = 1500,

    [string]$GodotConsolePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$maximumFramesPerWorldUnit = 0.1
$samplingDensity = [double]$MovieFps / [double]$CameraSpeed
if ($samplingDensity -gt $maximumFramesPerWorldUnit) {
    $maximumFpsAtSpeed = [Math]::Max(1, [Math]::Floor($CameraSpeed * $maximumFramesPerWorldUnit))
    throw "MovieFps=$MovieFps is too high for CameraSpeed=$CameraSpeed and the 4 GB Godot AVI limit; use at most $maximumFpsAtSpeed FPS at this speed, or increase CameraSpeed."
}

function Test-PathInsideRoot {
    param(
        [string]$Candidate,
        [string]$Root
    )

    $normalizedCandidate = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([char[]]"\/")
    $normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/")
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    return $normalizedCandidate -eq $normalizedRoot -or
        $normalizedCandidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function ConvertFrom-MediaRate {
    param([string]$Rate)

    $parts = $Rate.Split('/')
    if ($parts.Count -ne 2) {
        throw "FFprobe returned an invalid video rate: '$Rate'."
    }
    $numerator = [double]::Parse($parts[0], [Globalization.CultureInfo]::InvariantCulture)
    $denominator = [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)
    if ($denominator -eq 0.0) {
        throw "FFprobe returned a zero video-rate denominator: '$Rate'."
    }
    return $numerator / $denominator
}

function Get-VideoProbe {
    param(
        [string]$Path,
        [string]$FfprobePath
    )

    $probeLines = @(& $FfprobePath `
        -v error `
        -count_frames `
        -select_streams "v:0" `
        -show_entries "stream=avg_frame_rate,nb_read_frames:format=duration" `
        -of json `
        $Path)
    if ($LASTEXITCODE -ne 0) {
        throw "FFprobe could not inspect the video: '$Path'."
    }
    $probe = ($probeLines -join [Environment]::NewLine) | ConvertFrom-Json
    $streams = @($probe.streams)
    if ($streams.Count -ne 1) {
        throw "FFprobe expected one primary video stream in '$Path'; found $($streams.Count)."
    }
    if ([string]::IsNullOrWhiteSpace([string]$streams[0].nb_read_frames)) {
        throw "FFprobe did not return a decoded frame count for '$Path'."
    }
    return [pscustomobject]@{
        Duration = [double]::Parse([string]$probe.format.duration, [Globalization.CultureInfo]::InvariantCulture)
        FrameRate = ConvertFrom-MediaRate -Rate ([string]$streams[0].avg_frame_rate)
        FrameCount = [int64]::Parse([string]$streams[0].nb_read_frames, [Globalization.CultureInfo]::InvariantCulture)
    }
}

function Assert-VideoContract {
    param(
        [string]$Label,
        $Probe,
        [double]$ExpectedDuration,
        [double]$ExpectedFrameRate,
        [double]$DurationTolerance,
        [int64]$FrameTolerance
    )

    if ([Math]::Abs($Probe.FrameRate - $ExpectedFrameRate) -gt 0.001) {
        throw "$Label frame rate is $($Probe.FrameRate) FPS; expected $ExpectedFrameRate FPS."
    }
    if ([Math]::Abs($Probe.Duration - $ExpectedDuration) -gt $DurationTolerance) {
        throw "$Label duration is $($Probe.Duration) s; expected $ExpectedDuration s (+/- $DurationTolerance s)."
    }
    $expectedFrames = [int64][Math]::Round($ExpectedDuration * $ExpectedFrameRate)
    if ([Math]::Abs($Probe.FrameCount - $expectedFrames) -gt $FrameTolerance) {
        throw "$Label has $($Probe.FrameCount) decoded frames; expected $expectedFrames (+/- $FrameTolerance)."
    }
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$runnerPath = Join-Path $projectRoot "tests\run_all_tests.ps1"
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Godot test runner was not found: '$runnerPath'."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $artifactRoot = if ($env:OS -eq "Windows_NT" -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $env:LOCALAPPDATA "OstatniPomost\VisualSurveys"
    }
    else {
        Join-Path ([System.IO.Path]::GetTempPath()) "OstatniPomost/VisualSurveys"
    }
}
else {
    $expandedOutput = [Environment]::ExpandEnvironmentVariables($OutputDirectory.Trim())
    $artifactRoot = if ([System.IO.Path]::IsPathRooted($expandedOutput)) {
        [System.IO.Path]::GetFullPath($expandedOutput)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path ([string](Get-Location)) $expandedOutput))
    }
}

$artifactRoot = [System.IO.Path]::GetFullPath($artifactRoot)
if (Test-PathInsideRoot -Candidate $artifactRoot -Root $projectRoot) {
    throw "Visual-survey artifact root must stay outside the source project: '$artifactRoot'."
}
$runName = "run_{0}_{1}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), [Guid]::NewGuid().ToString("N").Substring(0, 8)
$artifactDirectory = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot $runName))
[void](New-Item -ItemType Directory -Path $artifactDirectory -Force)

$rawMoviePath = Join-Path $artifactDirectory "full_map_scan_raw.avi"
$mp4Path = Join-Path $artifactDirectory "full_map_scan.mp4"
$contactSheetPath = Join-Path $artifactDirectory "contact_sheet_11x11.png"
$manifestPath = Join-Path $artifactDirectory "run_manifest.json"
$framesDirectory = Join-Path $artifactDirectory "frames"
$reducedMotionValue = if ($ReducedMotion) { "true" } else { "false" }
$targetUserArguments = @(
    "--artifact-dir=$artifactDirectory",
    "--quality=$Quality",
    "--reduced-motion=$reducedMotionValue",
    "--speed=$CameraSpeed",
    "--movie-fps=$MovieFps"
)

$runnerArguments = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $runnerPath,
    "-NativeTarget", "tests/DiveMapVisualSurvey.tscn",
    "-NativeMovieOutputPath", $rawMoviePath,
    "-NativeMovieFps", [string]$MovieFps,
    "-ImportTimeoutSeconds", [string]$ImportTimeoutSeconds,
    "-TestTimeoutSeconds", [string]$SurveyTimeoutSeconds
)
if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
    $runnerArguments += @("-GodotConsolePath", $GodotConsolePath)
}
$targetUserArgumentsJson = $targetUserArguments | ConvertTo-Json -Compress
$targetUserArgumentsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($targetUserArgumentsJson))
$runnerArguments += @("-TargetUserArgumentsBase64", $targetUserArgumentsBase64)

$powershellExecutable = (Get-Process -Id $PID).Path
Write-Host "Dive map visual survey"
Write-Host ("  Artifacts: {0}" -f $artifactDirectory)
Write-Host ("  Quality:   {0}" -f $Quality)
Write-Host ("  Motion:    {0}" -f $(if ($ReducedMotion) { "reduced" } else { "full" }))
Write-Host ("  Speed:     {0} world units/s" -f $CameraSpeed)
Write-Host ("  Movie:     {0} FPS" -f $MovieFps)
Write-Host ""

& $powershellExecutable @runnerArguments
$runnerExitCode = $LASTEXITCODE
$runnerFailed = $runnerExitCode -ne 0

if ($runnerFailed) {
    Write-Warning "The strict Godot runner reported a failure. Complete survey artifacts will still be prepared when the internal manifest is valid."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host ("SURVEY_ARTIFACT_DIR={0}" -f $artifactDirectory)
    throw "Visual survey did not produce run_manifest.json."
}
if (-not (Test-Path -LiteralPath $rawMoviePath -PathType Leaf)) {
    Write-Host ("SURVEY_ARTIFACT_DIR={0}" -f $artifactDirectory)
    throw "Visual survey did not produce the raw movie."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]$manifest.status -ne "PASS") {
    throw "Visual survey manifest does not report PASS: '$($manifest.status)'."
}
$expectedFrameCount = [int]$manifest.keyframe_count
$frameFiles = @(Get-ChildItem -LiteralPath $framesDirectory -Filter "frame_*.png" -File)
if ($expectedFrameCount -ne 121 -or $frameFiles.Count -ne $expectedFrameCount) {
    throw "Visual survey requires exactly 121 keyframes; manifest=$expectedFrameCount files=$($frameFiles.Count)."
}
if ([string]$manifest.route_pattern -ne "horizontal_row_serpentine" -or
    [string]$manifest.route_start_cell -ne "C01-R01" -or
    [string]$manifest.route_end_cell -ne "C11-R11") {
    throw "Visual survey did not use the required left-to-right-first horizontal serpentine."
}

$ffmpegCommand = Get-Command "ffmpeg" -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $ffmpegCommand) {
    Write-Warning "FFmpeg was not found. Raw AVI, 121 PNG frames, telemetry and manifest are still available."
    Write-Host ("SURVEY_ARTIFACT_DIR={0}" -f $artifactDirectory)
    if ($runnerFailed) {
        throw "Dive map visual survey artifacts were preserved, but FFmpeg is missing and the strict Godot runner failed with exit code $runnerExitCode."
    }
    throw "FFmpeg is required to create the MP4 and 11x11 contact sheet; raw survey artifacts were preserved."
}
$ffprobeCommand = Get-Command "ffprobe" -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $ffprobeCommand) {
    Write-Host ("SURVEY_ARTIFACT_DIR={0}" -f $artifactDirectory)
    throw "FFprobe is required to validate the raw movie and final MP4; raw survey artifacts were preserved."
}

$invariantCulture = [Globalization.CultureInfo]::InvariantCulture
$trimStartValue = [double]$manifest.movie_visible_start_seconds
$trimDurationValue = [double]$manifest.movie_visible_duration_seconds
$trimStart = $trimStartValue.ToString("0.######", $invariantCulture)
$trimDuration = $trimDurationValue.ToString("0.######", $invariantCulture)
$durationTolerance = [Math]::Max(0.25, 2.0 / [double]$MovieFps)
$rawExpectedDuration = $trimStartValue + $trimDurationValue
$rawProbe = Get-VideoProbe -Path $rawMoviePath -FfprobePath $ffprobeCommand.Source
Assert-VideoContract `
    -Label "Raw visual-survey movie" `
    -Probe $rawProbe `
    -ExpectedDuration $rawExpectedDuration `
    -ExpectedFrameRate $MovieFps `
    -DurationTolerance $durationTolerance `
    -FrameTolerance 2

& $ffmpegCommand.Source `
    -hide_banner -loglevel error -y `
    -i $rawMoviePath `
    -ss $trimStart -t $trimDuration `
    -an -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p `
    -fps_mode cfr -r $MovieFps -movflags +faststart `
    $mp4Path
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $mp4Path -PathType Leaf)) {
    throw "FFmpeg could not create the trimmed MP4 survey."
}
$mp4Probe = Get-VideoProbe -Path $mp4Path -FfprobePath $ffprobeCommand.Source
Assert-VideoContract `
    -Label "Final visual-survey MP4" `
    -Probe $mp4Probe `
    -ExpectedDuration $trimDurationValue `
    -ExpectedFrameRate $MovieFps `
    -DurationTolerance $durationTolerance `
    -FrameTolerance 2
& $ffmpegCommand.Source -hide_banner -loglevel error -xerror -i $mp4Path -map "0:v:0" -f null NUL
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg could not fully decode the final MP4 survey."
}

$framePattern = Join-Path $framesDirectory "frame_%03d.png"
$contactFilter = "scale=320:180:force_original_aspect_ratio=decrease,pad=320:180:(ow-iw)/2:(oh-ih)/2:color=black,tile=11x11"
& $ffmpegCommand.Source `
    -hide_banner -loglevel error -y `
    -framerate 1 -start_number 0 -i $framePattern `
    -vf $contactFilter -frames:v 1 `
    $contactSheetPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $contactSheetPath -PathType Leaf)) {
    throw "FFmpeg could not create the 11x11 visual-survey contact sheet."
}

Write-Host ""
Write-Host "Visual survey artifacts are ready:" -ForegroundColor Green
Write-Host ("  MP4:          {0}" -f $mp4Path)
Write-Host ("  Contact sheet:{0}" -f $contactSheetPath)
Write-Host ("  Frames:       {0}" -f $framesDirectory)
Write-Host ("  Telemetry:    {0}" -f (Join-Path $artifactDirectory "telemetry.jsonl"))
Write-Host ("  Manifest:     {0}" -f $manifestPath)
Write-Host ("SURVEY_ARTIFACT_DIR={0}" -f $artifactDirectory)
if ($runnerFailed) {
    throw "Dive map visual survey artifacts are ready, but the strict Godot runner failed with exit code $runnerExitCode."
}
