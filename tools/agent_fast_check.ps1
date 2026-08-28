#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseRef = 'refs/remotes/origin/main',
    [string]$GodotConsolePath,
    [string[]]$TestTarget = @(),
    [string[]]$AllowedPath = @(),
    [switch]$AllowControlPlane
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-NativeResult {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $script:RepositoryPath
    )

    $previousLocation = Get-Location
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location -LiteralPath $previousLocation
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).TrimEnd()
    }
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $script:RepositoryPath
    )

    $result = Invoke-NativeResult $FilePath $Arguments $WorkingDirectory
    if ($result.ExitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed (exit $($result.ExitCode)):`n$($result.Output)"
    }
    return $result.Output
}

function Normalize-RepoPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $portable = $Path.Replace('\', '/').Trim()
    while ($portable.StartsWith('./')) { $portable = $portable.Substring(2) }
    if ([string]::IsNullOrWhiteSpace($portable) -or $portable.StartsWith('/') -or
        $portable -match '^[A-Za-z]:' -or $portable -match '(^|/)\.\.(/|$)') {
        throw "Invalid repository-relative path: '$Path'."
    }
    return $portable
}

function Test-AllowedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Allowlist
    )
    foreach ($entry in $Allowlist) {
        $normalized = (Normalize-RepoPath $entry).TrimEnd('/')
        if ($Path -ceq $normalized -or $Path.StartsWith($normalized + '/', [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Add-ChangedPaths {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [Parameter(Mandatory = $true)][string[]]$GitArguments
    )
    $raw = Invoke-NativeChecked git (@('-C', $script:RepositoryPath) + $GitArguments)
    foreach ($line in @($raw -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$Set.Add((Normalize-RepoPath $line))
        }
    }
}

function Resolve-GodotPath {
    if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
        $resolved = [System.IO.Path]::GetFullPath($GodotConsolePath)
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "Godot executable does not exist: '$resolved'."
        }
        return $resolved
    }
    foreach ($name in @('godot4', 'godot')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Godot is required for changed Godot files or targeted tests. Pass -GodotConsolePath.'
}

$script:RepositoryPath = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
$top = [System.IO.Path]::GetFullPath(
    (Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'rev-parse', '--show-toplevel')).Trim()
).TrimEnd('\', '/')
if (-not [string]::Equals($top, $script:RepositoryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository must be the Git top level: '$top'."
}
$branch = (Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'branch', '--show-current')).Trim()
if ($branch -cnotmatch '^codex/.+') {
    throw "Fast-check must run from a codex/* branch; current branch is '$branch'."
}
Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'rev-parse', '--verify', "$BaseRef^{commit}") | Out-Null

$changed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
Add-ChangedPaths $changed @('diff', '--name-only', '--no-renames', "$BaseRef...HEAD")
Add-ChangedPaths $changed @('diff', '--cached', '--name-only', '--no-renames')
Add-ChangedPaths $changed @('diff', '--name-only', '--no-renames')
Add-ChangedPaths $changed @('ls-files', '--others', '--exclude-standard')
$changedPaths = @($changed | Sort-Object)
if ($changedPaths.Count -eq 0) {
    throw 'Fast-check found no changes relative to the selected base.'
}

if ($AllowedPath.Count -gt 0) {
    $outside = @($changedPaths | Where-Object { -not (Test-AllowedPath $_ $AllowedPath) })
    if ($outside.Count -gt 0) {
        throw "Changed paths outside -AllowedPath: $($outside -join ', ')"
    }
}

if (-not $AllowControlPlane) {
    $arguments = @('-B', (Join-Path $script:RepositoryPath 'tools/ci_protected_paths.py'), 'validate-paths')
    foreach ($path in $changedPaths) { $arguments += @('--path', $path) }
    Invoke-NativeChecked python $arguments | Out-Null
}

Invoke-NativeChecked python @(
    '-B', (Join-Path $script:RepositoryPath 'tools/workbench_contract.py'),
    '--repo', $script:RepositoryPath, 'eol-check'
) | Out-Null
Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'lfs', 'version') | Out-Null
Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'lfs', 'fsck') | Out-Null
Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'lfs', 'status', '--porcelain') | Out-Null

foreach ($path in $changedPaths) {
    $absolute = Join-Path $script:RepositoryPath $path
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
    switch -Regex ($path) {
        '\.py$' {
            Invoke-NativeChecked python @(
                '-B', '-c',
                'import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])',
                $absolute
            ) | Out-Null
            break
        }
        '\.json$' {
            Get-Content -LiteralPath $absolute -Raw | ConvertFrom-Json | Out-Null
            break
        }
        '\.ps1$' {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $absolute, [ref]$tokens, [ref]$errors
            ) | Out-Null
            if (@($errors).Count -gt 0) {
                throw "PowerShell parser errors in '$path': $([string]::Join('; ', @($errors)))"
            }
            break
        }
    }
}

foreach ($path in $changedPaths) {
    $absolute = Join-Path $script:RepositoryPath $path
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
    if ($path -match '(^|/)tests/.+_test\.py$') {
        Invoke-NativeChecked python @('-B', $absolute) | Out-Null
    }
    elseif ($path -match '(^|/)tests/.+_test\.ps1$') {
        Invoke-NativeChecked pwsh @('-NoLogo', '-NoProfile', '-File', $absolute) | Out-Null
    }
}

$godotExtensions = @('.gd', '.tscn', '.tres', '.res', '.godot')
$godotChanged = @($changedPaths | Where-Object {
    $godotExtensions -contains [System.IO.Path]::GetExtension($_).ToLowerInvariant()
})
$targets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($target in $TestTarget) { [void]$targets.Add((Normalize-RepoPath $target)) }
foreach ($path in $changedPaths) {
    if ($path -match '(^|/)tests/.+_test\.gd$') { [void]$targets.Add($path) }
}
if ($godotChanged.Count -gt 0 -and $targets.Count -eq 0) {
    [void]$targets.Add('tests/smoke_test.gd')
}

if ($godotChanged.Count -gt 0 -or $targets.Count -gt 0) {
    $godot = Resolve-GodotPath
    foreach ($target in @($targets | Sort-Object)) {
        $targetPath = Join-Path $script:RepositoryPath $target
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            throw "Fast-check target does not exist: '$target'."
        }
        # The project runner owns the complete isolation boundary: immutable
        # snapshot, private .godot/user/temp directories, ports and ERROR scan.
        & (Join-Path $script:RepositoryPath 'tests/run_all_tests.ps1') `
            -GodotConsolePath $godot `
            -SourceRepositoryPath $script:RepositoryPath `
            -Target $target
        if (-not $?) { throw "Targeted test failed: '$target'." }
    }
}

Write-Host "FAST-CHECK PASS paths=$($changedPaths.Count) godot_targets=$($targets.Count) head=$((Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'rev-parse', 'HEAD')).Trim())"
