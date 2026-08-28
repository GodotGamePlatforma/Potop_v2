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
    $output = @()
    $exitCode = 127
    $ErrorActionPreference = 'Continue'
    try {
        $command = @(Get-Command -Name git -CommandType Application,ExternalScript -ErrorAction Stop)[0]
        $resolvedCommand = if (-not [string]::IsNullOrWhiteSpace([string]$command.Path)) {
            [string]$command.Path
        }
        else {
            [string]$command.Source
        }
        if ([string]::IsNullOrWhiteSpace($resolvedCommand)) {
            throw 'Cannot resolve external command git.'
        }
        $output = @(& $resolvedCommand -C $WorkingRepository @Arguments 2>&1)
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

function Get-LfsListing {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingRepository,
        [string]$Revision
    )

    $arguments = @(
        '-c', 'lfs.fetchinclude=',
        '-c', 'lfs.fetchexclude=',
        'lfs', 'ls-files', '--json'
    )
    if (-not [string]::IsNullOrWhiteSpace($Revision)) {
        $arguments += $Revision
    }
    $json = Invoke-GitChecked $WorkingRepository $arguments
    try {
        $listing = $json | ConvertFrom-Json
    }
    catch {
        throw "git lfs ls-files returned invalid JSON: $json"
    }
    if ($null -eq $listing -or @($listing.PSObject.Properties.Name) -notcontains 'files') {
        throw 'git lfs ls-files JSON is missing the files collection.'
    }
    return $listing
}

function Assert-LfsObjectsDownloaded {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingRepository,
        [Parameter(Mandatory = $true)][string]$Revision
    )

    $listing = Get-LfsListing -WorkingRepository $WorkingRepository -Revision $Revision
    foreach ($entry in @($listing.files)) {
        if ($null -eq $entry) { continue }
        $nameProperty = $entry.PSObject.Properties['name']
        $downloadedProperty = $entry.PSObject.Properties['downloaded']
        $name = if ($null -eq $nameProperty) { '' } else { [string]$nameProperty.Value }
        if ([string]::IsNullOrWhiteSpace($name) -or
            $null -eq $downloadedProperty -or $downloadedProperty.Value -isnot [bool] -or
            -not [bool]$downloadedProperty.Value) {
            throw "Git LFS object is not downloaded for exact revision ${Revision}: '$name'."
        }
    }
}

function Assert-LfsWorktreeHydrated {
    param([Parameter(Mandatory = $true)][string]$WorkingRepository)

    $listing = Get-LfsListing -WorkingRepository $WorkingRepository
    $pointerHeader = [System.Text.Encoding]::ASCII.GetBytes('version https://git-lfs.github.com/spec/v1')
    $rootPrefix = $WorkingRepository.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($entry in @($listing.files)) {
        if ($null -eq $entry) { continue }
        $nameProperty = $entry.PSObject.Properties['name']
        $checkoutProperty = $entry.PSObject.Properties['checkout']
        $relative = if ($null -eq $nameProperty) { '' } else { [string]$nameProperty.Value }
        if ([string]::IsNullOrWhiteSpace($relative) -or [System.IO.Path]::IsPathRooted($relative) -or
            $null -eq $checkoutProperty -or $checkoutProperty.Value -isnot [bool] -or
            -not [bool]$checkoutProperty.Value) {
            throw "Git LFS worktree entry is not checked out: '$relative'."
        }
        $candidate = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine(
                $WorkingRepository,
                $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            )
        )
        if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Git LFS worktree file is missing or outside the repository: '$relative'."
        }
        $stream = [System.IO.File]::OpenRead($candidate)
        try {
            $prefix = New-Object byte[] $pointerHeader.Length
            $read = $stream.Read($prefix, 0, $prefix.Length)
        }
        finally {
            $stream.Dispose()
        }
        $isPointer = $read -eq $pointerHeader.Length
        if ($isPointer) {
            for ($index = 0; $index -lt $pointerHeader.Length; $index++) {
                if ($prefix[$index] -ne $pointerHeader[$index]) {
                    $isPointer = $false
                    break
                }
            }
        }
        if ($isPointer) {
            throw "Tracked Git LFS pointer remains unhydrated: '$relative'."
        }
    }
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
$remoteBranch = Invoke-GitResult $repositoryPath @(
    'ls-remote', '--exit-code', '--heads', 'origin', "refs/heads/$targetBranch"
)
if ($remoteBranch.ExitCode -eq 0) {
    throw "Remote branch already exists: '$targetBranch'."
}
if ($remoteBranch.ExitCode -ne 2) {
    throw "Could not determine whether remote branch '$targetBranch' exists: $($remoteBranch.Output)"
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

    Invoke-GitChecked $destinationPath @(
        '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
        'lfs', 'fetch', 'origin', $baseSha
    ) | Out-Null
    Assert-LfsObjectsDownloaded -WorkingRepository $destinationPath -Revision $baseSha
    Invoke-GitChecked $destinationPath @(
        '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
        'lfs', 'checkout'
    ) | Out-Null
    Invoke-GitChecked $destinationPath @(
        '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
        'lfs', 'fsck', $baseSha
    ) | Out-Null
    Assert-LfsWorktreeHydrated -WorkingRepository $destinationPath

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
            $removed = Invoke-GitResult $repositoryPath @('worktree', 'remove', '--force', $destinationPath)
            if ($removed.ExitCode -eq 0) {
                $deleted = Invoke-GitResult $repositoryPath @(
                    'update-ref', '-d', "refs/heads/$targetBranch", $baseSha
                )
                if ($deleted.ExitCode -ne 0) {
                    Write-Warning "Cleanup preserved changed branch '$targetBranch': $($deleted.Output)"
                }
            }
        }
    }
    throw
}
