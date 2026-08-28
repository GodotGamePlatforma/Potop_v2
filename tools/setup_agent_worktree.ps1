#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9._-]*$')]
    [string]$TaskSlug,

    [ValidatePattern('^(root|map|diver|integration|structure-[a-z][a-z0-9_-]*)$')]
    [string]$OwnerSegment = 'root',

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$Branch,

    [switch]$Create
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-GitResult {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingRepository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $WorkingRepository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
    }
}

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingRepository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $result = Invoke-GitResult -WorkingRepository $WorkingRepository -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($result.Output)"
    }
    return $result.Output
}

function Normalize-Path {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd('\', '/')
}

$repositoryPath = Normalize-Path $Repository
$destinationPath = Normalize-Path $Destination
$repoTop = Normalize-Path (Invoke-GitChecked $repositoryPath @('rev-parse', '--show-toplevel'))
if (-not [string]::Equals($repoTop, $repositoryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository must be the top-level Git worktree: '$repoTop'."
}
if ($destinationPath.StartsWith($repositoryPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must be outside the source worktree.'
}

$targetBranch = if ([string]::IsNullOrWhiteSpace($Branch)) {
    "codex/$OwnerSegment/$TaskSlug"
}
else {
    $Branch
}
if ($targetBranch -cnotmatch '^codex/[a-z0-9][a-z0-9._/-]*$') {
    throw "Branch must be under codex/*: '$targetBranch'."
}
$branchCheck = Invoke-GitResult $repositoryPath @('check-ref-format', '--branch', $targetBranch)
if ($branchCheck.ExitCode -ne 0) {
    throw "Invalid branch name '$targetBranch'."
}

Invoke-GitChecked $repositoryPath @(
    'fetch', '--no-tags', '--prune', 'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null
$baseSha = (Invoke-GitChecked $repositoryPath @('rev-parse', 'refs/remotes/origin/main')).Trim()
$baseTree = (Invoke-GitChecked $repositoryPath @('rev-parse', "$baseSha`^{tree}")).Trim()
if ($baseSha -cnotmatch '^[0-9a-f]{40}$' -or $baseTree -cnotmatch '^[0-9a-f]{40}$') {
    throw 'origin/main did not resolve to exact SHA-1 commit and tree IDs.'
}

$branchExists = Invoke-GitResult $repositoryPath @('show-ref', '--verify', '--quiet', "refs/heads/$targetBranch")
if ($branchExists.ExitCode -eq 0) {
    throw "Branch already exists: '$targetBranch'."
}
if ($branchExists.ExitCode -ne 1) {
    throw "Could not determine whether branch '$targetBranch' exists."
}
if (Test-Path -LiteralPath $destinationPath) {
    throw "Destination already exists: '$destinationPath'."
}

$registeredPaths = @()
$worktreeList = Invoke-GitChecked $repositoryPath @('worktree', 'list', '--porcelain')
foreach ($line in @($worktreeList -split "`r?`n")) {
    if ($line.StartsWith('worktree ')) {
        $registeredPaths += Normalize-Path $line.Substring(9)
    }
}
foreach ($registeredPath in $registeredPaths) {
    $separator = [System.IO.Path]::DirectorySeparatorChar
    if ([string]::Equals($registeredPath, $destinationPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        $destinationPath.StartsWith($registeredPath + $separator, [System.StringComparison]::OrdinalIgnoreCase) -or
        $registeredPath.StartsWith($destinationPath + $separator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination overlaps registered worktree '$registeredPath': '$destinationPath'."
    }
}

Write-Host 'AGENT WORKTREE PLAN'
Write-Host "source=$repositoryPath"
Write-Host "origin_main=$baseSha"
Write-Host "origin_tree=$baseTree"
Write-Host "branch=$targetBranch"
Write-Host "destination=$destinationPath"

if (-not $Create) {
    Write-Host 'PLAN ONLY - rerun with -Create to materialize this exact current origin/main.'
    return
}

$created = $false
try {
    if (-not $PSCmdlet.ShouldProcess($destinationPath, "create worktree '$targetBranch' at '$baseSha'")) {
        return
    }
    Invoke-GitChecked $repositoryPath @(
        'worktree', 'add', '-b', $targetBranch, $destinationPath, $baseSha
    ) | Out-Null
    $created = $true

    Invoke-GitChecked $destinationPath @('lfs', 'pull', 'origin', $baseSha) | Out-Null
    Invoke-GitChecked $destinationPath @('lfs', 'fsck') | Out-Null

    $actualHead = (Invoke-GitChecked $destinationPath @('rev-parse', 'HEAD')).Trim()
    $actualTree = (Invoke-GitChecked $destinationPath @('rev-parse', 'HEAD^{tree}')).Trim()
    $actualBranch = (Invoke-GitChecked $destinationPath @('branch', '--show-current')).Trim()
    $status = Invoke-GitChecked $destinationPath @('status', '--porcelain=v1', '--untracked-files=all')
    if ($actualHead -cne $baseSha -or $actualTree -cne $baseTree -or
        $actualBranch -cne $targetBranch -or -not [string]::IsNullOrWhiteSpace($status)) {
        throw 'New worktree failed exact HEAD/tree/branch/clean verification.'
    }

    $installer = Join-Path $destinationPath 'tools/install_agent_git_hooks.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw "Git hook installer is missing: '$installer'."
    }
    & $installer -Install

    Write-Host 'CREATED'
    Write-Host "head=$actualHead"
    Write-Host "tree=$actualTree"
    Write-Host "branch=$actualBranch"
    Write-Host "worktree=$destinationPath"
}
catch {
    if ($created) {
        $statusProbe = Invoke-GitResult $destinationPath @('status', '--porcelain=v1', '--untracked-files=all')
        if ($statusProbe.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($statusProbe.Output)) {
            Invoke-GitResult $repositoryPath @('worktree', 'remove', '--force', $destinationPath) | Out-Null
            Invoke-GitResult $repositoryPath @('branch', '-D', $targetBranch) | Out-Null
        }
    }
    throw
}
