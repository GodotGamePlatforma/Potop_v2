#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),
    [string]$BaseRef = 'refs/remotes/origin/main',
    [string]$GodotConsolePath,
    [string]$PowerShellCommand = 'pwsh',
    [string[]]$TestTarget = @(),
    [string[]]$AllowedPath = @(),
    [string]$ExpectedHeadSha,
    [string]$ExpectedBranch,
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
    $exitCode = 127
    $output = @()
    $ErrorActionPreference = 'Continue'
    try {
        $command = @(Get-Command -Name $FilePath -CommandType Application,ExternalScript -ErrorAction Stop)[0]
        $resolvedCommand = if (-not [string]::IsNullOrWhiteSpace([string]$command.Path)) {
            [string]$command.Path
        }
        else {
            [string]$command.Source
        }
        if ([string]::IsNullOrWhiteSpace($resolvedCommand)) {
            throw "Cannot resolve external command '$FilePath'."
        }
        Set-Location -LiteralPath $WorkingDirectory
        $output = @(& $resolvedCommand @Arguments 2>&1)
        if ($null -ne $LASTEXITCODE) {
            $exitCode = [int]$LASTEXITCODE
        }
        elseif ($?) {
            $exitCode = 0
        }
        else {
            $exitCode = 1
        }
    }
    catch {
        $output = @($output) + @($_.Exception.Message)
        $exitCode = 127
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

function Assert-LfsHydrated {
    Invoke-NativeChecked git-lfs @('version') | Out-Null
    Invoke-NativeChecked git-lfs @('checkout') | Out-Null
    Invoke-NativeChecked git-lfs @('fsck') | Out-Null

    $rawListing = Invoke-NativeChecked git-lfs @('ls-files', '--json')
    try {
        $listing = $rawListing | ConvertFrom-Json
    }
    catch {
        throw "git lfs ls-files --json returned invalid JSON: $rawListing"
    }
    try { $lfsEntries = @($listing.files) | Where-Object { $null -ne $_ } }
    catch { throw 'git lfs ls-files --json omitted the files collection.' }
    $pointerHeader = [System.Text.Encoding]::ASCII.GetBytes(
        'version https://git-lfs.github.com/spec/v1'
    )
    $remainingPointers = @()
    foreach ($entry in $lfsEntries) {
        try { $entryName = [string]$entry.name }
        catch { throw 'git lfs ls-files --json returned an entry without a path.' }
        if ([string]::IsNullOrWhiteSpace($entryName)) {
            throw 'git lfs ls-files --json returned an entry without a path.'
        }
        $path = Normalize-RepoPath $entryName
        $checkout = $false
        try { $checkout = [bool]$entry.checkout } catch { $checkout = $false }
        if (-not $checkout) {
            $remainingPointers += $path
            continue
        }
        $absolute = Join-Path $script:RepositoryPath $path
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            $remainingPointers += $path
            continue
        }

        $stream = [System.IO.File]::OpenRead($absolute)
        try {
            $prefix = New-Object byte[] $pointerHeader.Length
            $read = $stream.Read($prefix, 0, $prefix.Length)
        }
        finally {
            $stream.Dispose()
        }
        if ($read -eq $pointerHeader.Length) {
            $matches = $true
            for ($index = 0; $index -lt $pointerHeader.Length; $index++) {
                if ($prefix[$index] -ne $pointerHeader[$index]) {
                    $matches = $false
                    break
                }
            }
            if ($matches) { $remainingPointers += $path }
        }
    }
    if ($remainingPointers.Count -gt 0) {
        throw "Tracked LFS pointers remain unhydrated: $($remainingPointers -join ', ')"
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

function Assert-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Label = $Name
    )
    try {
        $command = @(Get-Command -Name $Name -CommandType Application,ExternalScript -ErrorAction Stop)[0]
    }
    catch {
        throw "Required external command '$Label' is unavailable: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$command.Path) -and
        [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        throw "Required external command '$Label' cannot be resolved."
    }
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
        $command = @(
            Get-Command -Name $name -CommandType Application,ExternalScript `
                -ErrorAction SilentlyContinue
        ) | Select-Object -First 1
        if ($null -eq $command) { continue }
        $resolved = if (-not [string]::IsNullOrWhiteSpace([string]$command.Path)) {
            [string]$command.Path
        }
        else {
            [string]$command.Source
        }
        if (-not [string]::IsNullOrWhiteSpace($resolved)) { return $resolved }
    }
    throw 'Godot is required for changed Godot files or targeted tests. Pass -GodotConsolePath.'
}

$script:RepositoryPath = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
foreach ($requiredCommand in @('git', 'git-lfs', 'python')) {
    Assert-ExternalCommand $requiredCommand
}
Assert-ExternalCommand -Name $PowerShellCommand -Label 'pwsh'
$top = [System.IO.Path]::GetFullPath(
    (Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'rev-parse', '--show-toplevel')).Trim()
).TrimEnd('\', '/')
if (-not [string]::Equals($top, $script:RepositoryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository must be the Git top level: '$top'."
}
$branch = (Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'branch', '--show-current')).Trim()
$actualHead = (Invoke-NativeChecked git @('-C', $script:RepositoryPath, 'rev-parse', 'HEAD')).Trim()
if ([string]::IsNullOrWhiteSpace($ExpectedHeadSha)) {
    if (-not [string]::IsNullOrWhiteSpace($ExpectedBranch)) {
        throw '-ExpectedBranch is valid only together with -ExpectedHeadSha.'
    }
    $gitDirectory = [System.IO.Path]::GetFullPath(
        (Invoke-NativeChecked git @(
            '-C', $script:RepositoryPath,
            'rev-parse', '--path-format=absolute', '--git-dir'
        )).Trim()
    ).TrimEnd('\', '/')
    $gitCommonDirectory = [System.IO.Path]::GetFullPath(
        (Invoke-NativeChecked git @(
            '-C', $script:RepositoryPath,
            'rev-parse', '--path-format=absolute', '--git-common-dir'
        )).Trim()
    ).TrimEnd('\', '/')
    if ([string]::Equals(
        $gitDirectory,
        $gitCommonDirectory,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw ('Local fast-check requires a separate linked Git worktree. ' +
            'Start the task as Worktree, or Hand off to Worktree before editing.')
    }
    if ($branch -cnotmatch '^codex/.+') {
        throw "Local fast-check must run from a codex/* branch; current branch is '$branch'."
    }
}
else {
    if ($ExpectedHeadSha -cnotmatch '^[0-9a-f]{40}$') {
        throw '-ExpectedHeadSha must be one exact lowercase 40-character commit SHA.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedBranch) -and
        $ExpectedBranch -cnotmatch '^codex/.+') {
        throw "CI expected branch must be under codex/*: '$ExpectedBranch'."
    }
    if (-not [string]::IsNullOrEmpty($branch)) {
        throw "CI fast-check requires detached HEAD; current branch is '$branch'."
    }
    if ($actualHead -cne $ExpectedHeadSha) {
        throw "CI fast-check HEAD mismatch. expected=$ExpectedHeadSha actual=$actualHead"
    }
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
Assert-LfsHydrated
Invoke-NativeChecked git-lfs @('status', '--porcelain') | Out-Null

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
        Invoke-NativeChecked $PowerShellCommand @('-NoLogo', '-NoProfile', '-File', $absolute) | Out-Null
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

Write-Host "FAST-CHECK PASS paths=$($changedPaths.Count) godot_targets=$($targets.Count) head=$actualHead"
