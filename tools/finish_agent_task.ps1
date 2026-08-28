#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$CommitMessage = $Title,
    [string]$Body = 'Automatycznie opublikowana zmiana agenta.',
    [string]$RepositorySlug,
    [string]$GodotConsolePath,
    [string]$PowerShellCommand = 'pwsh',
    [string[]]$TestTarget = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-GitChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $command = @(Get-Command git -CommandType Application,ExternalScript -ErrorAction Stop)[0]
    $executable = if ($command.Path) { $command.Path } else { $command.Source }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $executable -C $Repository @Arguments 2>&1); $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $(($output | Out-String).Trim())"
    }
    return ($output | Out-String).Trim()
}

$repoTop = [System.IO.Path]::GetFullPath(
    (Invoke-GitChecked @('rev-parse', '--show-toplevel'))
).TrimEnd('\', '/')
$branch = (Invoke-GitChecked @('branch', '--show-current')).Trim()
if ($branch -cnotmatch '^codex/.+') {
    throw "Task publication requires a codex/* branch; current branch is '$branch'."
}

$status = Invoke-GitChecked @('status', '--porcelain=v1', '--untracked-files=all')
if (-not [string]::IsNullOrWhiteSpace($status)) {
    Invoke-GitChecked @('add', '--all') | Out-Null
    $gitCommand = @(Get-Command git -CommandType Application,ExternalScript -ErrorAction Stop)[0]
    $gitExecutable = if ($gitCommand.Path) { $gitCommand.Path } else { $gitCommand.Source }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $check = @(& $gitExecutable -C $repoTop diff --cached --check 2>&1); $checkExit = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($checkExit -ne 0) {
        throw "git diff --cached --check failed: $(($check | Out-String).Trim())"
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $staged = @(& $gitExecutable -C $repoTop diff --cached --quiet --exit-code 2>&1); $stagedExit = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($stagedExit -eq 0) {
        throw 'The worktree reported changes, but staging produced no commit payload.'
    }
    if ($stagedExit -ne 1) {
        throw "Could not verify staged changes: $(($staged | Out-String).Trim())"
    }
    Invoke-GitChecked @('commit', '-m', $CommitMessage) | Out-Null
    Write-Host "COMMITTED: $((Invoke-GitChecked @('rev-parse', 'HEAD')).Trim())"
}

$publisher = Join-Path $repoTop 'tools/publish_agent_pr.ps1'
if (-not (Test-Path -LiteralPath $publisher -PathType Leaf)) {
    throw "PR publisher is missing: '$publisher'."
}
$publishArguments = @{
    Repository = $repoTop
    Title = $Title
    Body = $Body
    PowerShellCommand = $PowerShellCommand
    TestTarget = $TestTarget
}
if (-not [string]::IsNullOrWhiteSpace($RepositorySlug)) {
    $publishArguments.RepositorySlug = $RepositorySlug
}
if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
    $publishArguments.GodotConsolePath = $GodotConsolePath
}
& $publisher @publishArguments
