#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-GitResult {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $script:Repo @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Invoke-GitChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $result = Invoke-GitResult $Arguments
    if ($result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($result.Output)"
    }
    return $result.Output
}

$script:Repo = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
$top = [System.IO.Path]::GetFullPath((Invoke-GitChecked @('rev-parse', '--show-toplevel')).Trim()).TrimEnd('\', '/')
if (-not [string]::Equals($script:Repo, $top, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository must be the Git top level: '$top'."
}
$branch = (Invoke-GitChecked @('branch', '--show-current')).Trim()
if ($branch -cne 'main') {
    throw "Local play checkout must be on main; current branch is '$branch'."
}
$beforeStatus = Invoke-GitChecked @('status', '--porcelain=v1', '--untracked-files=all')
if (-not [string]::IsNullOrWhiteSpace($beforeStatus)) {
    throw "Local main is dirty; no files were changed or removed:`n$beforeStatus"
}

Invoke-GitChecked @(
    'fetch', '--no-tags', 'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null
$targetSha = (Invoke-GitChecked @('rev-parse', 'refs/remotes/origin/main')).Trim()
if ($targetSha -cnotmatch '^[0-9a-f]{40}$') { throw 'origin/main did not resolve to an exact SHA.' }
$currentSha = (Invoke-GitChecked @('rev-parse', 'HEAD')).Trim()
$ancestor = Invoke-GitResult @('merge-base', '--is-ancestor', $currentSha, $targetSha)
if ($ancestor.ExitCode -ne 0) {
    throw "Local main cannot fast-forward to exact origin/main $targetSha."
}

Invoke-GitChecked @('merge', '--ff-only', $targetSha) | Out-Null
Invoke-GitChecked @('lfs', 'pull', 'origin', $targetSha) | Out-Null

$actualSha = (Invoke-GitChecked @('rev-parse', 'HEAD')).Trim()
$afterStatus = Invoke-GitChecked @('status', '--porcelain=v1', '--untracked-files=all')
if ($actualSha -cne $targetSha -or -not [string]::IsNullOrWhiteSpace($afterStatus)) {
    throw 'Post-sync exact SHA/clean verification failed.'
}
Write-Host "SYNC PASS main=$actualSha lfs=hydrated"
