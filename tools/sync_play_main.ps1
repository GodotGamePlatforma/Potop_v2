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

$script:Repo = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')

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

function Invoke-LfsCheckoutChecked {
    $hadSkipSmudge = Test-Path -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE'
    $previousSkipSmudge = [string]$env:GIT_LFS_SKIP_SMUDGE
    try {
        Remove-Item -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE' -ErrorAction SilentlyContinue
        Invoke-GitChecked @(
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'checkout'
        ) | Out-Null
    }
    finally {
        if ($hadSkipSmudge) {
            $env:GIT_LFS_SKIP_SMUDGE = $previousSkipSmudge
        }
        else {
            Remove-Item -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE' -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-PythonPath {
    foreach ($name in @('python.exe', 'python')) {
        $command = @(
            Get-Command -Name $name -CommandType Application,ExternalScript -ErrorAction SilentlyContinue
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
    throw 'Required external command python was not found.'
}

function Get-CanonicalPublicationLockPath {
    $pythonPath = Resolve-PythonPath
    $contractTool = Join-Path $PSScriptRoot 'workbench_contract.py'
    if (-not (Test-Path -LiteralPath $contractTool -PathType Leaf)) {
        throw "Canonical lock helper is missing: '$contractTool'."
    }
    $previous = $ErrorActionPreference
    $output = @()
    $exitCode = 127
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(
            & $pythonPath -B $contractTool --repo $script:Repo `
                lock-path --name integration-publish 2>&1
        )
        $exitCode = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    }
    catch {
        $output = @($output) + @($_.Exception.Message)
        $exitCode = 127
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($exitCode -ne 0) {
        throw "Canonical integration-publish lock path resolution failed: $(($output | Out-String).Trim())"
    }
    $lockPath = (($output | Out-String).Trim())
    if ([string]::IsNullOrWhiteSpace($lockPath) -or
        -not [System.IO.Path]::IsPathRooted($lockPath)) {
        throw "Canonical integration-publish lock path is invalid: '$lockPath'."
    }
    return [System.IO.Path]::GetFullPath($lockPath)
}

function Enter-IntegrationPublishLock {
    $lockPath = Get-CanonicalPublicationLockPath
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($lockPath)
    ) | Out-Null
    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::ReadWrite
        )
        if ($stream.Length -eq 0) {
            $stream.WriteByte(0)
            $stream.Flush()
        }
        $stream.Position = 0
        $stream.Lock(0, 1)
        $thread = if ([string]::IsNullOrWhiteSpace([string]$env:CODEX_THREAD_ID)) {
            'external'
        }
        else {
            [string]$env:CODEX_THREAD_ID
        }
        $owner = [ordered]@{ thread = $thread; pid = $PID } | ConvertTo-Json -Compress
        $ownerBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($owner)
        $stream.SetLength(1)
        $stream.Position = 1
        $stream.Write($ownerBytes, 0, $ownerBytes.Length)
        $stream.Flush()
        return $stream
    }
    catch {
        if ($null -ne $stream) { $stream.Dispose() }
        throw "Workspace lock 'integration-publish' is already active or unavailable for exact repository '$script:Repo': $($_.Exception.Message)"
    }
}

function Exit-IntegrationPublishLock {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    try {
        $Stream.Unlock(0, 1)
    }
    finally {
        $Stream.Dispose()
    }
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

function Get-MainState {
    $symbolic = Invoke-GitResult @('symbolic-ref', '--quiet', 'HEAD')
    $branch = Invoke-GitResult @('branch', '--show-current')
    $head = Invoke-GitResult @('rev-parse', 'HEAD')
    $main = Invoke-GitResult @('rev-parse', 'refs/heads/main')
    $status = Invoke-GitResult @('status', '--porcelain=v1', '--untracked-files=all')
    return [pscustomobject]@{
        SymbolicExit = $symbolic.ExitCode
        Symbolic = $symbolic.Output.Trim()
        BranchExit = $branch.ExitCode
        Branch = $branch.Output.Trim()
        HeadExit = $head.ExitCode
        Head = $head.Output.Trim()
        MainExit = $main.ExitCode
        Main = $main.Output.Trim()
        StatusExit = $status.ExitCode
        Status = $status.Output
    }
}

function Assert-ExactCleanMainState {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedSha,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $state = Get-MainState
    if ($state.SymbolicExit -ne 0 -or $state.Symbolic -cne 'refs/heads/main' -or
        $state.BranchExit -ne 0 -or $state.Branch -cne 'main' -or
        $state.HeadExit -ne 0 -or $state.Head -cne $ExpectedSha -or
        $state.MainExit -ne 0 -or $state.Main -cne $ExpectedSha -or
        $state.StatusExit -ne 0 -or -not [string]::IsNullOrWhiteSpace($state.Status)) {
        throw "$Label exact clean main fence failed: symbolic='$($state.Symbolic)' branch='$($state.Branch)' HEAD='$($state.Head)' main='$($state.Main)' status='$($state.Status)'."
    }
}

function Assert-ExactRemoteTarget {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedSha,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $remote = Invoke-GitResult @('rev-parse', 'refs/remotes/origin/main')
    if ($remote.ExitCode -ne 0 -or $remote.Output.Trim() -cne $ExpectedSha) {
        throw "$Label exact origin/main fence failed: '$($remote.Output.Trim())'."
    }
}

$publishLock = Enter-IntegrationPublishLock
try {
$top = [System.IO.Path]::GetFullPath((Invoke-GitChecked @('rev-parse', '--show-toplevel')).Trim()).TrimEnd('\', '/')
if (-not [string]::Equals($script:Repo, $top, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository must be the Git top level: '$top'."
}
$initialState = Get-MainState
if ($initialState.SymbolicExit -ne 0 -or $initialState.Symbolic -cne 'refs/heads/main' -or
    $initialState.BranchExit -ne 0 -or $initialState.Branch -cne 'main') {
    throw "Local play checkout must be on main; current branch is '$($initialState.Branch)'."
}
if ($initialState.StatusExit -ne 0 -or -not [string]::IsNullOrWhiteSpace($initialState.Status)) {
    throw "Local main is dirty; no files were changed or removed:`n$($initialState.Status)"
}
$currentSha = (Invoke-GitChecked @('rev-parse', 'HEAD')).Trim()
if ($currentSha -cnotmatch '^[0-9a-f]{40}$') { throw 'Local main did not resolve to an exact SHA.' }
Assert-ExactCleanMainState -ExpectedSha $currentSha -Label 'Initial'

# Repair the exact current main first. Command-scoped empty include/exclude values
# override local/system lfs.fetch* filters without changing their configuration.
Invoke-GitChecked @(
    '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
    'lfs', 'fetch', 'origin', $currentSha
) | Out-Null
Assert-LfsObjectsDownloaded $currentSha
Invoke-GitChecked @(
    '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
    'lfs', 'fsck', $currentSha
) | Out-Null
Invoke-LfsCheckoutChecked
Assert-LfsWorktreeHydrated
Assert-ExactCleanMainState -ExpectedSha $currentSha -Label 'Current LFS self-heal'

Invoke-GitChecked @(
    'fetch', '--no-tags', 'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null
$targetSha = (Invoke-GitChecked @('rev-parse', 'refs/remotes/origin/main')).Trim()
if ($targetSha -cnotmatch '^[0-9a-f]{40}$') { throw 'origin/main did not resolve to an exact SHA.' }
Assert-ExactCleanMainState -ExpectedSha $currentSha -Label 'Post-fetch'
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
Assert-ExactRemoteTarget -ExpectedSha $targetSha -Label 'Pre-merge'
Assert-ExactCleanMainState -ExpectedSha $currentSha -Label 'Pre-merge'

$mergeAttempted = $false
try {
    $mergeAttempted = $true
    Invoke-GitChecked @('merge', '--ff-only', $targetSha) | Out-Null
    Invoke-LfsCheckoutChecked
    Invoke-GitChecked @(
        '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
        'lfs', 'fsck', $targetSha
    ) | Out-Null
    Assert-LfsWorktreeHydrated
    Assert-ExactRemoteTarget -ExpectedSha $targetSha -Label 'Success'
    Assert-ExactCleanMainState -ExpectedSha $targetSha -Label 'Success'
    $actualSha = $targetSha
}
catch {
    $syncFailure = $_
    if ($mergeAttempted -and $currentSha -cne $targetSha) {
        $rollbackState = Get-MainState
        $exactMainBinding = (
            $rollbackState.SymbolicExit -eq 0 -and $rollbackState.Symbolic -ceq 'refs/heads/main' -and
            $rollbackState.BranchExit -eq 0 -and $rollbackState.Branch -ceq 'main' -and
            $rollbackState.HeadExit -eq 0 -and $rollbackState.MainExit -eq 0
        )
        if (-not $exactMainBinding -or $rollbackState.StatusExit -ne 0 -or
            -not [string]::IsNullOrWhiteSpace($rollbackState.Status)) {
            throw "Sync failed; rollback refused without overwriting ambiguous state: symbolic='$($rollbackState.Symbolic)' branch='$($rollbackState.Branch)' HEAD='$($rollbackState.Head)' main='$($rollbackState.Main)' status='$($rollbackState.Status)'. Original error: $($syncFailure.Exception.Message)"
        }
        if ($rollbackState.Head -ceq $currentSha -and $rollbackState.Main -ceq $currentSha) {
            throw $syncFailure
        }
        if ($rollbackState.Head -cne $targetSha -or $rollbackState.Main -cne $targetSha) {
            throw "Sync failed; rollback refused because main is not the expected target generation ${targetSha}: HEAD='$($rollbackState.Head)' main='$($rollbackState.Main)'. Original error: $($syncFailure.Exception.Message)"
        }
        $remoteTarget = Invoke-GitResult @('rev-parse', 'refs/remotes/origin/main')
        if ($remoteTarget.ExitCode -ne 0 -or $remoteTarget.Output.Trim() -cne $targetSha) {
            throw "Sync failed; rollback refused because the fetched target generation drifted. Original error: $($syncFailure.Exception.Message)"
        }

        # Take a second complete fence immediately before the only overwrite.
        $preRestoreState = Get-MainState
        if ($preRestoreState.SymbolicExit -ne 0 -or $preRestoreState.Symbolic -cne 'refs/heads/main' -or
            $preRestoreState.BranchExit -ne 0 -or $preRestoreState.Branch -cne 'main' -or
            $preRestoreState.HeadExit -ne 0 -or $preRestoreState.Head -cne $targetSha -or
            $preRestoreState.MainExit -ne 0 -or $preRestoreState.Main -cne $targetSha -or
            $preRestoreState.StatusExit -ne 0 -or
            -not [string]::IsNullOrWhiteSpace($preRestoreState.Status)) {
            throw "Sync failed; final rollback fence rejected state drift without overwriting it. Original error: $($syncFailure.Exception.Message)"
        }
        $restore = Invoke-GitResult @(
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'restore', "--source=$currentSha", '--staged', '--worktree', '--', '.'
        )
        if ($restore.ExitCode -ne 0) {
            throw "Sync failed and tracked files could not be restored: $($restore.Output). Original error: $($syncFailure.Exception.Message)"
        }
        $restoreRef = Invoke-GitResult @('update-ref', 'refs/heads/main', $currentSha, $targetSha)
        if ($restoreRef.ExitCode -ne 0) {
            throw "Sync failed and exact main ref rollback failed: $($restoreRef.Output). Original error: $($syncFailure.Exception.Message)"
        }
        Invoke-LfsCheckoutChecked
        Assert-LfsObjectsDownloaded $currentSha
        Invoke-GitChecked @(
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'fsck', $currentSha
        ) | Out-Null
        Assert-LfsWorktreeHydrated
        Assert-ExactCleanMainState -ExpectedSha $currentSha -Label 'Rollback result'
    }
    throw $syncFailure
}
Write-Host "SYNC PASS main=$actualSha lfs=hydrated"
}
finally {
    Exit-IntegrationPublishLock $publishLock
}
