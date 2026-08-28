#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory = $true)][string]$ManagedRoot,
    [string]$RepositorySlug,
    [string]$GhCommand = 'gh',
    [ValidateRange(0, 10080)][int]$MinimumMergedAgeMinutes = 10,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-CommandResult {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $previous = $ErrorActionPreference
    $output = @()
    $ErrorActionPreference = 'Continue'
    try {
        $command = @(Get-Command $FilePath -CommandType Application,ExternalScript -ErrorAction Stop)[0]
        $executable = if ($command.Path) { $command.Path } else { $command.Source }
        Push-Location -LiteralPath $WorkingDirectory
        try {
            $output = @(& $executable @Arguments 2>&1)
            if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
            elseif ($?) { $exitCode = 0 }
            else { $exitCode = 1 }
        }
        finally { Pop-Location }
    }
    catch { $output = @($output) + @($_.Exception.Message); $exitCode = 127 }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = [int]$exitCode; Output = ($output | Out-String).Trim() }
}

function Invoke-Checked {
    param([string]$FilePath,[string[]]$Arguments,[string]$WorkingDirectory)
    $result = Invoke-CommandResult $FilePath $Arguments $WorkingDirectory
    if ($result.ExitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed ($($result.ExitCode)): $($result.Output)"
    }
    return $result.Output
}

function Normalize-Path {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Convert-OriginUrlToSlug {
    param([Parameter(Mandatory = $true)][string]$OriginUrl)
    $value = $OriginUrl.Trim().TrimEnd('/')
    if ($value.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }
    if ($value -match '^https://github\.com/([^/]+)/([^/]+)$' -or
        $value -match '^git@github\.com:([^/]+)/([^/]+)$' -or
        $value -match '^ssh://git@github\.com/([^/]+)/([^/]+)$') {
        return "$($Matches[1])/$($Matches[2])"
    }
    throw "origin is not one supported GitHub repository URL: '$OriginUrl'."
}

function Assert-NoReparseBoundary {
    param([Parameter(Mandatory = $true)][string]$Root,[Parameter(Mandatory = $true)][string]$Child)
    $rootPath = Normalize-Path $Root
    $childPath = Normalize-Path $Child
    $prefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $childPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the managed root: '$childPath'."
    }
    $cursor = $rootPath
    $rootItem = Get-Item -LiteralPath $cursor -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Managed root is a reparse point: '$rootPath'."
    }
    $relative = $childPath.Substring($prefix.Length)
    foreach ($part in $relative.Split([System.IO.Path]::DirectorySeparatorChar)) {
        $cursor = Join-Path $cursor $part
        if (-not (Test-Path -LiteralPath $cursor)) { continue }
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Managed worktree boundary contains a reparse point: '$cursor'."
        }
    }
}

$repo = Normalize-Path $Repository
$managed = Normalize-Path $ManagedRoot
if (-not (Test-Path -LiteralPath $managed -PathType Container)) {
    throw "Managed worktree root does not exist: '$managed'."
}
$repoTop = Normalize-Path (Invoke-Checked git @('-C', $repo, 'rev-parse', '--show-toplevel') $repo)
$slug = if ([string]::IsNullOrWhiteSpace($RepositorySlug)) {
    Convert-OriginUrlToSlug (Invoke-Checked git @('-C', $repoTop, 'remote', 'get-url', 'origin') $repoTop)
}
else { $RepositorySlug.Trim() }
if ($slug -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Invalid GitHub repository slug: '$slug'."
}

$raw = Invoke-Checked git @('-C', $repoTop, 'worktree', 'list', '--porcelain') $repoTop
$entries = @()
$current = $null
foreach ($line in @($raw -split "`r?`n") + @('')) {
    if ([string]::IsNullOrEmpty($line)) {
        if ($null -ne $current) { $entries += [pscustomobject]$current; $current = $null }
        continue
    }
    if ($line.StartsWith('worktree ')) {
        $current = [ordered]@{ Path = $line.Substring(9); Branch = ''; Detached = $false }
    }
    elseif ($null -ne $current -and $line.StartsWith('branch refs/heads/')) {
        $current.Branch = $line.Substring(18)
    }
    elseif ($null -ne $current -and $line -ceq 'detached') { $current.Detached = $true }
}

$json = Invoke-Checked $GhCommand @(
    'pr', 'list', '--repo', $slug, '--state', 'merged', '--limit', '1000',
    '--json', 'number,state,mergedAt,headRefName,headRefOid,baseRefName,url'
) $repoTop
try {
    $parsedPulls = $json | ConvertFrom-Json
    $mergedPulls = @()
    foreach ($parsedPull in $parsedPulls) {
        if ($null -ne $parsedPull) { $mergedPulls += $parsedPull }
    }
}
catch { throw "gh pr list returned invalid merged-PR JSON: $json" }

$removed = 0
$kept = 0
$now = [DateTimeOffset]::UtcNow
foreach ($entry in $entries) {
    $path = Normalize-Path ([string]$entry.Path)
    $branch = [string]$entry.Branch
    $managedPrefix = $managed + [System.IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($managedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($entry.Detached -or $branch -cnotmatch '^codex/.+') {
        Write-Output "KEEP non-task: $path"
        $kept++
        continue
    }
    try { Assert-NoReparseBoundary -Root $managed -Child $path }
    catch { Write-Warning $_; $kept++; continue }
    $statusProbe = Invoke-CommandResult git @('-C', $path, 'status', '--porcelain=v1', '--untracked-files=all') $repoTop
    if ($statusProbe.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($statusProbe.Output)) {
        Write-Output "KEEP dirty/unavailable: $branch ($path)"
        $kept++
        continue
    }
    $head = (Invoke-Checked git @('-C', $path, 'rev-parse', 'HEAD') $repoTop).Trim()
    $match = @($mergedPulls | Where-Object {
        $properties = $_.PSObject.Properties
        if ($null -eq $properties['state'] -or $null -eq $properties['headRefName'] -or
            $null -eq $properties['headRefOid'] -or $null -eq $properties['baseRefName'] -or
            $null -eq $properties['mergedAt']) {
            $false
        }
        else {
            $_.state -ceq 'MERGED' -and $_.headRefName -ceq $branch -and
            $_.headRefOid -ceq $head -and $_.baseRefName -ceq 'main' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.mergedAt)
        }
    }) | Select-Object -First 1
    if ($null -eq $match) {
        Write-Output "KEEP no exact merged PR: $branch ($head)"
        $kept++
        continue
    }
    $mergedAt = [DateTimeOffset]::Parse(
        [string]$match.mergedAt,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind
    )
    if (($now - $mergedAt).TotalMinutes -lt $MinimumMergedAgeMinutes) {
        Write-Output "KEEP protection window: $branch (PR #$($match.number))"
        $kept++
        continue
    }

    if (-not $Apply) {
        Write-Output "WOULD REMOVE exact merged clean worktree: $branch ($path)"
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($path, "remove clean merged worktree for PR #$($match.number)")) {
        continue
    }
    Invoke-Checked git @('-C', $repoTop, 'worktree', 'remove', '--', $path) $repoTop | Out-Null
    $delete = Invoke-CommandResult git @(
        '-C', $repoTop, 'update-ref', '-d', "refs/heads/$branch", $head
    ) $repoTop
    if ($delete.ExitCode -ne 0) {
        Write-Warning "Worktree was removed, but the changed local branch was retained: $($delete.Output)"
    }
    Write-Output "REMOVED exact merged clean worktree: $branch (PR #$($match.number))"
    $removed++
}

Write-Output "CLEANUP COMPLETE removed=$removed kept=$kept apply=$($Apply.IsPresent)"
