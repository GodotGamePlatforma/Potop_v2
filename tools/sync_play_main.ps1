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
        $output = @(& $resolvedCommand -C $script:Repo @Arguments 2>&1)
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

function Get-LfsListing {
    param([string]$Revision)

    $arguments = @(
        '-c', 'lfs.fetchinclude=',
        '-c', 'lfs.fetchexclude=',
        'lfs', 'ls-files', '--json'
    )
    if (-not [string]::IsNullOrWhiteSpace($Revision)) {
        $arguments += $Revision
    }
    $json = Invoke-GitChecked $arguments
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
    param([Parameter(Mandatory = $true)][string]$Revision)

    $listing = Get-LfsListing $Revision
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
    $listing = Get-LfsListing
    $pointerHeader = [System.Text.Encoding]::ASCII.GetBytes('version https://git-lfs.github.com/spec/v1')
    $rootPrefix = $script:Repo.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
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
                $script:Repo,
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
Assert-LfsWorktreeHydrated

Invoke-GitChecked @(
    'fetch', '--no-tags', 'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null
$targetSha = (Invoke-GitChecked @('rev-parse', 'refs/remotes/origin/main')).Trim()
if ($targetSha -cnotmatch '^[0-9a-f]{40}$') { throw 'origin/main did not resolve to an exact SHA.' }
$currentSha = (Invoke-GitChecked @('rev-parse', 'HEAD')).Trim()
if ($currentSha -cnotmatch '^[0-9a-f]{40}$') { throw 'Local main did not resolve to an exact SHA.' }
Assert-LfsObjectsDownloaded $currentSha
Invoke-GitChecked @(
    '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
    'lfs', 'fsck', $currentSha
) | Out-Null
$ancestor = Invoke-GitResult @('merge-base', '--is-ancestor', $currentSha, $targetSha)
if ($ancestor.ExitCode -ne 0) {
    throw "Local main cannot fast-forward to exact origin/main $targetSha."
}

Invoke-GitChecked @(
    '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
    'lfs', 'fetch', 'origin', $targetSha
) | Out-Null
Assert-LfsObjectsDownloaded $targetSha
Invoke-GitChecked @(
    '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
    'lfs', 'fsck', $targetSha
) | Out-Null

$mergeAttempted = $false
try {
    $mergeAttempted = $true
    Invoke-GitChecked @('merge', '--ff-only', $targetSha) | Out-Null
    Invoke-GitChecked @(
        '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
        'lfs', 'checkout'
    ) | Out-Null
    Invoke-GitChecked @(
        '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
        'lfs', 'fsck', $targetSha
    ) | Out-Null
    Assert-LfsWorktreeHydrated

    $actualSha = (Invoke-GitChecked @('rev-parse', 'HEAD')).Trim()
    $afterStatus = Invoke-GitChecked @('status', '--porcelain=v1', '--untracked-files=all')
    if ($actualSha -cne $targetSha -or -not [string]::IsNullOrWhiteSpace($afterStatus)) {
        throw 'Post-sync exact SHA/clean verification failed.'
    }
}
catch {
    $syncFailure = $_
    if ($mergeAttempted -and $currentSha -cne $targetSha) {
        $observedHead = Invoke-GitResult @('rev-parse', 'HEAD')
        if ($observedHead.ExitCode -ne 0) {
            throw "Sync failed and original main could not be restored because HEAD is unreadable: $($syncFailure.Exception.Message)"
        }
        $observedSha = $observedHead.Output.Trim()
        if ($observedSha -cne $currentSha -and $observedSha -cne $targetSha) {
            throw "Sync failed and main moved to unexpected $observedSha; refusing to overwrite it. Original error: $($syncFailure.Exception.Message)"
        }
        $restore = Invoke-GitResult @(
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'restore', "--source=$currentSha", '--staged', '--worktree', '--', '.'
        )
        if ($restore.ExitCode -ne 0) {
            throw "Sync failed and tracked files could not be restored: $($restore.Output). Original error: $($syncFailure.Exception.Message)"
        }
        if ($observedSha -ceq $targetSha) {
            $restoreRef = Invoke-GitResult @('update-ref', 'refs/heads/main', $currentSha, $targetSha)
            if ($restoreRef.ExitCode -ne 0) {
                throw "Sync failed and exact main ref rollback failed: $($restoreRef.Output). Original error: $($syncFailure.Exception.Message)"
            }
        }
        $restoredStatus = Invoke-GitResult @('status', '--porcelain=v1', '--untracked-files=all')
        $restoredHead = Invoke-GitResult @('rev-parse', 'HEAD')
        if ($restoredStatus.ExitCode -ne 0 -or $restoredHead.ExitCode -ne 0 -or
            $restoredHead.Output.Trim() -cne $currentSha -or
            -not [string]::IsNullOrWhiteSpace($restoredStatus.Output)) {
            throw "Sync failed and exact original main state was not restored. Original error: $($syncFailure.Exception.Message)"
        }
    }
    throw $syncFailure
}
Write-Host "SYNC PASS main=$actualSha lfs=hydrated"
