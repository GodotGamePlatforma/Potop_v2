#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Join-Path $projectRoot 'tools/build_playable_main.ps1'
$presetPath = Join-Path $projectRoot 'export_presets.cfg'
$projectPath = Join-Path $projectRoot 'project.godot'
$ignorePath = Join-Path $projectRoot '.gitignore'

foreach ($path in @($toolPath, $presetPath, $projectPath, $ignorePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Builder contract input is missing: $path"
    }
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $toolPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
    $details = ($parseErrors | ForEach-Object {
        "line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join '; '
    throw "Builder script does not parse: $details"
}

$source = Get-Content -LiteralPath $toolPath -Raw
$requiredFragments = @(
    "Join-Path `$script:RepoRoot 'tools/sync_play_main.ps1'",
    "'-Repository', `$script:RepoRoot",
    "`$branch -cne 'main'",
    "`$sha -cne `$mainSha",
    "`$sha -cne `$remoteSha",
    "'status', '--porcelain=v1', '--untracked-files=all'",
    "'worktree', 'add', '--detach', `$workspace, `$Sha",
    "'lfs', 'fetch', 'origin', `$Sha",
    "'lfs', 'checkout'",
    "'lfs', 'fsck', `$Sha",
    'version https://git-lfs.github.com/spec/v1',
    "'--export-release', `$ExportPreset, `$exe",
    "'--headless', '--quit-after', [string]`$SmokeFrames",
    "(?im)^\s*(?:ERROR|SCRIPT ERROR):",
    "schema = 'potop-playable-build-v1'",
    "status = 'PASS'",
    '[System.IO.Directory]::Move($staging, $finalDirectory)',
    '[System.IO.File]::Move($temporary, $current, $true)',
    'Set-CurrentPointer -Sha $Sha',
    "Join-Path `$script:BuildRootPath 'last-failure'",
    'Remove-StaleStaging',
    '$sha -ceq $lastFailedSha',
    'PLAYABLE BUILD WAITING: unchanged failed SHA',
    'Builder attempt failed; current is unchanged.'
)
foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Builder contract fragment is missing: $fragment"
    }
}

if ($source.Contains('[System.IO.File]::Replace(')) {
    throw 'Builder must not use File.Replace without a backup path for current.'
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    $pointerRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'potop-builder-current-{0}' -f [guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $pointerRoot | Out-Null
    try {
        . $toolPath
        $script:BuildRootPath = $pointerRoot
        $currentPath = Join-Path $pointerRoot 'current'
        foreach ($sha in @(('1' * 40), ('2' * 40), ('3' * 40))) {
            Set-CurrentPointer -Sha $sha
            $actual = Get-Content -LiteralPath $currentPath -Raw
            if ($actual -cne "$sha`n") {
                throw "Current pointer replacement produced unexpected content: '$actual'."
            }
        }
        if (@(Get-ChildItem -LiteralPath $pointerRoot -Filter '.current-*.tmp' -Force).Count -ne 0) {
            throw 'Current pointer replacement left a temporary file behind.'
        }
    }
    finally {
        [System.IO.Directory]::Delete($pointerRoot, $true)
    }
}
else {
    Write-Host 'SKIP current replacement runtime test: PowerShell 7 is required by the builder.'
}

$publishArtifact = $source.IndexOf(
    '[System.IO.Directory]::Move($staging, $finalDirectory)',
    [System.StringComparison]::Ordinal
)
$publishCurrent = $source.IndexOf(
    'Set-CurrentPointer -Sha $Sha',
    $publishArtifact + 1,
    [System.StringComparison]::Ordinal
)
if ($publishArtifact -lt 0 -or $publishCurrent -le $publishArtifact) {
    throw 'Builder must publish a complete by-SHA directory before changing current.'
}

$catchIndex = $source.IndexOf("    catch {`r`n        `$failure = `$_", [System.StringComparison]::Ordinal)
if ($catchIndex -lt 0) {
    $catchIndex = $source.IndexOf("    catch {`n        `$failure = `$_", [System.StringComparison]::Ordinal)
}
$failurePublish = $source.IndexOf('Publish-LastFailure -Staging $staging', [System.StringComparison]::Ordinal)
$failureCurrent = if ($catchIndex -ge 0) {
    $source.IndexOf('Set-CurrentPointer', $catchIndex, [System.StringComparison]::Ordinal)
}
else { -2 }
if ($catchIndex -lt 0 -or $failurePublish -lt $catchIndex -or $failureCurrent -ne -1) {
    throw 'Failure path must retain bounded diagnostics without changing current.'
}

foreach ($forbiddenPattern in @(
    'reset --hard',
    'git clean',
    'run_all_tests',
    'integration-green',
    'refs/last-green',
    '\bFROZEN\b',
    '\bassignment\b',
    '\breceipt\b',
    '\bACK\b'
)) {
    if ($source -match "(?i)$forbiddenPattern") {
        throw "Builder contains obsolete or out-of-scope mechanism: $forbiddenPattern"
    }
}

$preset = Get-Content -LiteralPath $presetPath -Raw
foreach ($required in @(
    'name="Windows Desktop"',
    'platform="Windows Desktop"',
    'export_filter="all_resources"',
    'include_filter="*.json,*.txt"',
    'binary_format/embed_pck=false',
    'application/modify_resources=false'
)) {
    if (-not $preset.Contains($required)) {
        throw "Windows export preset is missing: $required"
    }
}

$project = Get-Content -LiteralPath $projectPath -Raw
if ($project -notmatch '(?ms)^\[editor\]\s+export/convert_text_resources_to_binary=false\s*(?:\r?\n\[|\z)') {
    throw 'project.godot must preserve text resources in the exported PCK.'
}

$ignore = Get-Content -LiteralPath $ignorePath -Raw
if ($ignore -notmatch '(?m)^/builds/\s*$') {
    throw 'Local builder artifacts must be excluded by /builds/.'
}

Write-Host 'PASS exact-main-SHA/LFS/export/real-smoke/by-sha/atomic-current/failure-retention/watch-suppression contract'
