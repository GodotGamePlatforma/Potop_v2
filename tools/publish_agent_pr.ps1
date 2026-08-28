#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Body = 'Automatycznie opublikowana zmiana agenta.',
    [ValidateSet('main')]
    [string]$BaseBranch = 'main',
    [string]$RepositorySlug
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-CommandResult {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $previous = $ErrorActionPreference
    $previousLocation = Get-Location
    $ErrorActionPreference = 'Continue'
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location -LiteralPath $previousLocation
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $result = Invoke-CommandResult $FilePath $Arguments $WorkingDirectory
    if ($result.ExitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed: $($result.Output)"
    }
    return $result.Output
}

$repo = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
$top = [System.IO.Path]::GetFullPath(
    (Invoke-Checked git @('rev-parse', '--show-toplevel') $repo).Trim()
).TrimEnd('\', '/')
if (-not [string]::Equals($repo, $top, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository must be the Git top level: '$top'."
}
$branch = (Invoke-Checked git @('branch', '--show-current') $repo).Trim()
if ($branch -cnotmatch '^codex/.+') {
    throw "publish-pr requires a codex/* branch; current branch is '$branch'."
}
$status = Invoke-Checked git @('status', '--porcelain=v1', '--untracked-files=all') $repo
if (-not [string]::IsNullOrWhiteSpace($status)) {
    throw "publish-pr requires a clean worktree. Commit or remove these changes first:`n$status"
}
$head = (Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim()
if ($head -cnotmatch '^[0-9a-f]{40}$') { throw 'HEAD is not an exact full SHA.' }

Invoke-Checked git @(
    'fetch', '--no-tags', 'origin',
    "+refs/heads/$BaseBranch`:refs/remotes/origin/$BaseBranch"
) $repo | Out-Null
$base = (Invoke-Checked git @('rev-parse', "refs/remotes/origin/$BaseBranch") $repo).Trim()

$protectedProbe = Invoke-CommandResult python @(
    '-B', (Join-Path $repo 'tools/ci_protected_paths.py'),
    'validate-diff', '--repo', $repo, '--base', $base, '--head', $head
) $repo
$controlPlane = $protectedProbe.ExitCode -ne 0
if ($controlPlane) {
    Write-Host 'CONTROL-PLANE: PR zostanie opublikowany bez automatycznego enqueue.'
    if (-not [string]::IsNullOrWhiteSpace($protectedProbe.Output)) { Write-Host $protectedProbe.Output }
}

Invoke-Checked git @(
    'push', '--set-upstream', 'origin',
    "refs/heads/$branch`:refs/heads/$branch"
) $repo | Out-Null
$pushedHead = (Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim()
if ($pushedHead -cne $head) { throw 'HEAD changed while publishing.' }

$slug = if ([string]::IsNullOrWhiteSpace($RepositorySlug)) {
    (Invoke-Checked gh @('repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner') $repo).Trim()
}
else {
    $RepositorySlug.Trim()
}
if ($slug -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Invalid GitHub repository slug: '$slug'."
}

$listJson = Invoke-Checked gh @(
    'pr', 'list', '--repo', $slug, '--state', 'open', '--base', $BaseBranch,
    '--head', $branch, '--limit', '100', '--json', 'number,url'
) $repo
$open = @($listJson | ConvertFrom-Json)
if ($open.Count -gt 1) {
    throw "Expected at most one open PR for '$branch'; found $($open.Count)."
}
if ($open.Count -eq 0) {
    Invoke-Checked gh @(
        'pr', 'create', '--repo', $slug, '--base', $BaseBranch, '--head', $branch,
        '--title', $Title, '--body', $Body
    ) $repo | Out-Null
}
else {
    Invoke-Checked gh @(
        'pr', 'edit', [string]$open[0].number, '--repo', $slug,
        '--title', $Title, '--body', $Body
    ) $repo | Out-Null
}

$viewJson = Invoke-Checked gh @(
    'pr', 'view', $branch, '--repo', $slug,
    '--json', 'number,url,state,headRefName,headRefOid,baseRefName'
) $repo
$pr = $viewJson | ConvertFrom-Json
if ([string]$pr.state -cne 'OPEN' -or [string]$pr.headRefName -cne $branch -or
    [string]$pr.headRefOid -cne $head -or [string]$pr.baseRefName -cne $BaseBranch) {
    throw 'Published PR does not match the exact open branch/base/HEAD.'
}

$mode = 'manual-control-plane'
if (-not $controlPlane) {
    Invoke-Checked gh @(
        'pr', 'merge', [string]$pr.number, '--repo', $slug, '--auto', '--squash'
    ) $repo | Out-Null
    $mode = 'native-auto-merge'
}

[pscustomobject]@{
    CommitSha = $head
    PullRequest = [int]$pr.number
    Url = [string]$pr.url
    Mode = $mode
}
