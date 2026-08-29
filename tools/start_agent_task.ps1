#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9._-]*$')]
    [ValidateLength(1, 48)]
    [string]$TaskSlug,

    [ValidatePattern('^(root|base|map|diver|integration|structure-[a-z][a-z0-9_-]*)$')]
    [string]$OwnerSegment = 'root',

    [string]$WorktreeRoot,
    [switch]$SkipCleanup,
    [switch]$PlanOnly
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
$commonDirectory = [System.IO.Path]::GetFullPath(
    (Invoke-GitChecked @('rev-parse', '--path-format=absolute', '--git-common-dir'))
).TrimEnd('\', '/')
$primaryRoot = Split-Path -Parent $commonDirectory
$managedRoot = if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
    Join-Path (Split-Path -Parent $primaryRoot) 'agent-worktrees'
}
else {
    [System.IO.Path]::GetFullPath($WorktreeRoot).TrimEnd('\', '/')
}

if (-not $SkipCleanup -and -not $PlanOnly) {
    $cleanup = Join-Path $PSScriptRoot 'cleanup_merged_worktrees.ps1'
    if ((Test-Path -LiteralPath $cleanup -PathType Leaf) -and
        (Test-Path -LiteralPath $managedRoot -PathType Container)) {
        try {
            & $cleanup -Repository $repoTop -ManagedRoot $managedRoot -Apply
        }
        catch {
            Write-Warning "Cleanup was skipped after a safe failure: $($_.Exception.Message)"
        }
    }
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$nonce = [guid]::NewGuid().ToString('N').Substring(0, 8)
$uniqueSlug = "$TaskSlug-$stamp-$nonce"
$branch = "codex/$OwnerSegment/$uniqueSlug"
$destination = Join-Path $managedRoot "$OwnerSegment-$uniqueSlug"
$setup = Join-Path $PSScriptRoot 'setup_agent_worktree.ps1'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
    throw "Worktree setup helper is missing: '$setup'."
}

$arguments = @{
    Repository = $repoTop
    TaskSlug = $uniqueSlug
    OwnerSegment = $OwnerSegment
    Destination = $destination
    Branch = $branch
}
if (-not $PlanOnly) { $arguments.Create = $true }
& $setup @arguments

if (-not $PlanOnly) {
    Write-Host ''
    Write-Host 'AGENT TASK READY'
    Write-Host "Set-Location -LiteralPath '$destination'"
}
