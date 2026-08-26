[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedHooksPath = '.githooks'
$candidateRoot = Split-Path -Parent $PSScriptRoot
$hookFile = Join-Path $candidateRoot '.githooks/pre-push'

function Invoke-GitChecked {
    param(
        [string]$Repository,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $exitCode): $($output | Out-String)"
    }

    return ($output | Out-String).Trim()
}

function Get-LocalHooksPathValues {
    param([string]$Repository)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $Repository config --local --get-all core.hooksPath 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -eq 1) {
        return @()
    }
    if ($exitCode -ne 0) {
        throw "Cannot read repo-local core.hooksPath (exit $exitCode): $($output | Out-String)"
    }

    return @($output | ForEach-Object { ([string]$_).Trim() })
}

function Test-IsRepositoryHookPath {
    param([string]$Value)

    $normalized = $Value.Replace('\', '/').TrimEnd('/')
    return $normalized -eq '.githooks' -or $normalized -eq './.githooks'
}

$repoRoot = Invoke-GitChecked $candidateRoot rev-parse --show-toplevel
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')
$expectedScriptRoot = [System.IO.Path]::GetFullPath($candidateRoot).TrimEnd('\', '/')
if (-not [string]::Equals(
    $repoRoot,
    $expectedScriptRoot,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Installer must live in <repo>/tools. Script root '$expectedScriptRoot' differs from Git root '$repoRoot'."
}

if (-not (Test-Path -LiteralPath $hookFile -PathType Leaf)) {
    throw "Hook file is missing: $hookFile"
}

$commonDirRaw = Invoke-GitChecked $repoRoot rev-parse --git-common-dir
if ([System.IO.Path]::IsPathRooted($commonDirRaw)) {
    $commonDir = [System.IO.Path]::GetFullPath($commonDirRaw)
}
else {
    $commonDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $commonDirRaw))
}

$currentValues = @(Get-LocalHooksPathValues -Repository $repoRoot)
$alreadyConfigured = (
    $currentValues.Count -eq 1 -and
    (Test-IsRepositoryHookPath -Value $currentValues[0])
)
$displayCurrent = if ($currentValues.Count -eq 0) {
    '<unset>'
}
else {
    $currentValues -join ', '
}

if (-not $Install) {
    Write-Host 'PLAN ONLY - no Git configuration was changed.'
    Write-Host "Repository: $repoRoot"
    Write-Host "Git common dir (shared by linked worktrees): $commonDir"
    Write-Host "Current repo-local core.hooksPath: $displayCurrent"
    Write-Host "Planned repo-local core.hooksPath: $expectedHooksPath"
    if ($currentValues.Count -gt 0 -and -not $alreadyConfigured -and -not $Force) {
        Write-Host 'A foreign custom value would be preserved. Use -Install -Force only after reviewing it.'
    }
    else {
        Write-Host 'Use -Install to apply this plan.'
    }
    return
}

if ($currentValues.Count -gt 0 -and -not $alreadyConfigured -and -not $Force) {
    throw "Refusing to overwrite foreign repo-local core.hooksPath '$displayCurrent'. Re-run with -Install -Force only after reviewing that configuration."
}

if ($alreadyConfigured) {
    Write-Host "ALREADY CONFIGURED - repo-local core.hooksPath=$expectedHooksPath"
}
else {
    Invoke-GitChecked $repoRoot config --local core.hooksPath $expectedHooksPath | Out-Null
    Write-Host "INSTALLED - repo-local core.hooksPath=$expectedHooksPath"
}

# Git for Windows executes shebang hooks from core.hooksPath without a POSIX
# mode bit. On Unix-like hosts, make the working-tree hook executable without
# staging or otherwise changing the repository index.
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & chmod +x -- $hookFile 2>&1 | Out-Null
        $chmodExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($chmodExit -ne 0) {
        throw "core.hooksPath was configured, but chmod +x failed for $hookFile"
    }
}

$effective = @(Get-LocalHooksPathValues -Repository $repoRoot)
if ($effective.Count -ne 1 -or -not (Test-IsRepositoryHookPath -Value $effective[0])) {
    throw "Post-install verification failed: repo-local core.hooksPath is '$($effective -join ', ')'."
}

Write-Host 'Linked worktrees that contain .githooks/pre-push share this repo-local configuration.'
