#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Body = 'Automatycznie opublikowana zmiana agenta.',
    [ValidateSet('main')]
    [string]$BaseBranch = 'main',
    [string]$RepositorySlug,
    [string]$GodotConsolePath,
    [string]$PowerShellCommand = 'pwsh',
    [string[]]$TestTarget = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Assert-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Label = $Name
    )
    try {
        $command = @(Get-Command -Name $Name -CommandType Application,ExternalScript -ErrorAction Stop)[0]
    }
    catch {
        throw "Required external command '$Label' is unavailable: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$command.Path) -and
        [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        throw "Required external command '$Label' cannot be resolved."
    }
}

function Invoke-CommandResult {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $previous = $ErrorActionPreference
    $previousLocation = Get-Location
    $output = @()
    $exitCode = 127
    $ErrorActionPreference = 'Continue'
    try {
        $command = @(Get-Command -Name $FilePath -CommandType Application,ExternalScript -ErrorAction Stop)[0]
        $resolvedCommand = if (-not [string]::IsNullOrWhiteSpace([string]$command.Path)) {
            [string]$command.Path
        }
        else {
            [string]$command.Source
        }
        if ([string]::IsNullOrWhiteSpace($resolvedCommand)) {
            throw "Cannot resolve external command '$FilePath'."
        }
        Set-Location -LiteralPath $WorkingDirectory
        $output = @(& $resolvedCommand @Arguments 2>&1)
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
        Set-Location -LiteralPath $previousLocation
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $result = Invoke-CommandResult $FilePath $Arguments $WorkingDirectory
    if ($result.ExitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed (exit $($result.ExitCode)): $($result.Output)"
    }
    return $result.Output
}

function Convert-OriginUrlToSlug {
    param([Parameter(Mandatory = $true)][string]$OriginUrl)

    $value = $OriginUrl.Trim().TrimEnd('/')
    if ($value.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }
    $owner = $null
    $name = $null
    if ($value -match '^https://github\.com/([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    elseif ($value -match '^git@github\.com:([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    elseif ($value -match '^ssh://git@github\.com/([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($name) -or
        $owner -cnotmatch '^[A-Za-z0-9_.-]+$' -or $name -cnotmatch '^[A-Za-z0-9_.-]+$') {
        throw "origin is not one unambiguous GitHub repository URL: '$OriginUrl'."
    }
    return "$owner/$name"
}

function Get-ClassifierAssessment {
    param(
        [Parameter(Mandatory = $true)][string]$ClassifierPath,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$BaseSha,
        [Parameter(Mandatory = $true)][string]$HeadSha
    )

    if (-not (Test-Path -LiteralPath $ClassifierPath -PathType Leaf)) {
        throw "$Label classifier is missing: '$ClassifierPath'."
    }
    $probe = Invoke-CommandResult python @(
        '-B', $ClassifierPath,
        'validate-diff', '--repo', $RepositoryPath, '--base', $BaseSha, '--head', $HeadSha
    ) $RepositoryPath
    if ($probe.ExitCode -eq 0) {
        try {
            $result = $probe.Output | ConvertFrom-Json
        }
        catch {
            throw "$Label classifier returned exit 0 without valid JSON: $($probe.Output)"
        }
        if ([string]$result.status -cne 'PASS' -or [string]$result.base -cne $BaseSha -or
            [string]$result.head -cne $HeadSha -or [int]$result.protected_path_count -ne 0) {
            throw "$Label classifier returned an invalid PASS binding: $($probe.Output)"
        }
        return 'ordinary'
    }

    $protectedPattern = 'CI\s+PROTECTED\s+PATHS\s+FAILED:\s+Automatic\s+integration\s+cannot\s+change\s+protected\s+control-plane\s+paths:'
    if ($probe.Output -cmatch $protectedPattern) {
        return 'control-plane'
    }
    throw "$Label classifier failed unexpectedly (exit $($probe.ExitCode)): $($probe.Output)"
}

function Read-Pr {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Slug,
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )
    $json = Invoke-Checked gh @(
        'pr', 'view', [string]$Number, '--repo', $Slug,
        '--json', 'number,url,state,headRefName,headRefOid,baseRefName,autoMergeRequest'
    ) $RepositoryPath
    try {
        $pr = $json | ConvertFrom-Json
    }
    catch {
        throw "GitHub returned invalid PR JSON for #${Number}: $json"
    }
    $required = @('number', 'url', 'state', 'headRefName', 'headRefOid', 'baseRefName', 'autoMergeRequest')
    $available = @($pr.PSObject.Properties.Name)
    foreach ($property in $required) {
        if ($available -notcontains $property) {
            throw "GitHub PR JSON is missing '$property' for #$Number."
        }
    }
    return $pr
}

function Assert-PrIdentity {
    param(
        [Parameter(Mandatory = $true)][object]$PullRequest,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$HeadSha,
        [Parameter(Mandatory = $true)][string]$BaseBranch
    )
    if ([string]$PullRequest.state -cne 'OPEN' -or
        [string]$PullRequest.headRefName -cne $Branch -or
        [string]$PullRequest.headRefOid -cne $HeadSha -or
        [string]$PullRequest.baseRefName -cne $BaseBranch) {
        throw 'Published PR does not match the exact open branch/base/HEAD.'
    }
}

$repo = [System.IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
foreach ($requiredCommand in @('git', 'python', 'gh')) {
    Assert-ExternalCommand $requiredCommand
}
Assert-ExternalCommand -Name $PowerShellCommand -Label 'pwsh'
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
$baseRef = "refs/remotes/origin/$BaseBranch"
$base = (Invoke-Checked git @('rev-parse', $baseRef) $repo).Trim()
if ($base -cnotmatch '^[0-9a-f]{40}$') { throw 'Freshly fetched base is not an exact full SHA.' }
if ((Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim() -cne $head -or
    -not [string]::IsNullOrWhiteSpace(
        (Invoke-Checked git @('status', '--porcelain=v1', '--untracked-files=all') $repo)
    )) {
    throw 'HEAD or worktree changed while fetching the base.'
}

$originUrls = @(
    (Invoke-Checked git @('config', '--local', '--get-all', 'remote.origin.url') $repo) -split "`r?`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($originUrls.Count -ne 1) {
    throw "Expected exactly one local remote.origin.url; found $($originUrls.Count)."
}
$derivedSlug = Convert-OriginUrlToSlug $originUrls[0]
$pushUrlProbe = Invoke-CommandResult git @(
    'config', '--local', '--get-all', 'remote.origin.pushurl'
) $repo
if ($pushUrlProbe.ExitCode -eq 0) {
    $pushUrls = @(
        $pushUrlProbe.Output -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($pushUrls.Count -ne 1 -or
        -not [string]::Equals(
            (Convert-OriginUrlToSlug $pushUrls[0]),
            $derivedSlug,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'remote.origin.pushurl does not identify the same single GitHub repository as origin.'
    }
}
elseif ($pushUrlProbe.ExitCode -ne 1 -or -not [string]::IsNullOrWhiteSpace($pushUrlProbe.Output)) {
    throw "Cannot determine remote.origin.pushurl: $($pushUrlProbe.Output)"
}
if (-not [string]::IsNullOrWhiteSpace($RepositorySlug) -and
    -not [string]::Equals($RepositorySlug.Trim(), $derivedSlug, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "RepositorySlug '$RepositorySlug' does not match origin '$derivedSlug'."
}
$slug = $derivedSlug

$tempClassifierDirectory = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("potop-base-classifier-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $tempClassifierDirectory | Out-Null
    $baseClassifier = Join-Path $tempClassifierDirectory 'ci_protected_paths.py'
    $baseClassifierSource = Invoke-Checked git @(
        'show', "$base`:tools/ci_protected_paths.py"
    ) $repo
    [System.IO.File]::WriteAllText(
        $baseClassifier,
        $baseClassifierSource + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    $baseAssessment = Get-ClassifierAssessment `
        -ClassifierPath $baseClassifier `
        -Label 'Exact-base' `
        -RepositoryPath $repo `
        -BaseSha $base `
        -HeadSha $head
    $candidateAssessment = Get-ClassifierAssessment `
        -ClassifierPath (Join-Path $repo 'tools/ci_protected_paths.py') `
        -Label 'Candidate' `
        -RepositoryPath $repo `
        -BaseSha $base `
        -HeadSha $head
    $controlPlane = $baseAssessment -ceq 'control-plane' -or $candidateAssessment -ceq 'control-plane'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempClassifierDirectory)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($controlPlane) {
    Write-Host 'CONTROL-PLANE: PR zostanie opublikowany bez automatycznego enqueue.'
}
$fastCheck = Join-Path $repo 'tools/agent_fast_check.ps1'
if (-not (Test-Path -LiteralPath $fastCheck -PathType Leaf)) {
    throw "Canonical fast-check is missing: '$fastCheck'."
}
$fastCheckParameters = @{
    Repository = $repo
    BaseRef = $base
    PowerShellCommand = $PowerShellCommand
}
if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
    $fastCheckParameters.GodotConsolePath = $GodotConsolePath
}
if ($TestTarget.Count -gt 0) {
    $fastCheckParameters.TestTarget = $TestTarget
}
if ($controlPlane) {
    $fastCheckParameters.AllowControlPlane = $true
}
try {
    & $fastCheck @fastCheckParameters
}
catch {
    throw "Canonical agent_fast_check failed before publication: $($_.Exception.Message)"
}

$postCheckHead = (Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim()
$postCheckBranch = (Invoke-Checked git @('branch', '--show-current') $repo).Trim()
$postCheckStatus = Invoke-Checked git @('status', '--porcelain=v1', '--untracked-files=all') $repo
$postCheckBase = (Invoke-Checked git @('rev-parse', $baseRef) $repo).Trim()
if ($postCheckHead -cne $head -or $postCheckBranch -cne $branch -or
    $postCheckBase -cne $base -or -not [string]::IsNullOrWhiteSpace($postCheckStatus)) {
    throw 'HEAD, branch, base or clean state changed during canonical fast-check.'
}

Invoke-Checked git @(
    'push', '--set-upstream', 'origin',
    "refs/heads/$branch`:refs/heads/$branch"
) $repo | Out-Null
$remoteLine = (Invoke-Checked git @('ls-remote', '--heads', 'origin', "refs/heads/$branch") $repo).Trim()
$remoteFields = @($remoteLine -split '\s+')
if ($remoteFields.Count -ne 2 -or $remoteFields[0] -cne $head -or
    $remoteFields[1] -cne "refs/heads/$branch") {
    throw 'Remote branch does not resolve to the exact published HEAD.'
}
if ((Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim() -cne $head -or
    -not [string]::IsNullOrWhiteSpace(
        (Invoke-Checked git @('status', '--porcelain=v1', '--untracked-files=all') $repo)
    )) {
    throw 'HEAD or clean state changed while publishing the branch.'
}

$listArguments = @(
    'pr', 'list', '--repo', $slug, '--state', 'open', '--base', $BaseBranch,
    '--head', $branch, '--limit', '1000', '--json', 'number'
)
$listJson = Invoke-Checked gh $listArguments $repo
try {
    $parsedOpen = $listJson | ConvertFrom-Json
    $open = @()
    if ($null -ne $parsedOpen) {
        foreach ($item in @($parsedOpen)) {
            if ($null -ne $item) { $open += $item }
        }
    }
}
catch {
    throw "GitHub returned invalid PR list JSON: $listJson"
}
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

$confirmedListJson = Invoke-Checked gh $listArguments $repo
try {
    $parsedConfirmedOpen = $confirmedListJson | ConvertFrom-Json
    $confirmedOpen = @()
    if ($null -ne $parsedConfirmedOpen) {
        foreach ($item in @($parsedConfirmedOpen)) {
            if ($null -ne $item) { $confirmedOpen += $item }
        }
    }
}
catch {
    throw "GitHub returned invalid post-create PR list JSON: $confirmedListJson"
}
if ($confirmedOpen.Count -ne 1) {
    throw "Expected exactly one open PR for '$branch' after create/reuse; found $($confirmedOpen.Count)."
}
$pr = Read-Pr -Number ([int]$confirmedOpen[0].number) -Slug $slug -RepositoryPath $repo
Assert-PrIdentity -PullRequest $pr -Branch $branch -HeadSha $head -BaseBranch $BaseBranch

$mode = 'manual-control-plane'
if ($controlPlane) {
    if ($null -ne $pr.autoMergeRequest) {
        Invoke-Checked gh @(
            'pr', 'merge', [string]$pr.number, '--repo', $slug, '--disable-auto'
        ) $repo | Out-Null
    }
}
else {
    Invoke-Checked gh @(
        'pr', 'merge', [string]$pr.number, '--repo', $slug,
        '--auto', '--squash', '--match-head-commit', $head
    ) $repo | Out-Null
    $mode = 'native-auto-merge'
}

$postOperationPr = Read-Pr -Number ([int]$pr.number) -Slug $slug -RepositoryPath $repo
Assert-PrIdentity -PullRequest $postOperationPr -Branch $branch -HeadSha $head -BaseBranch $BaseBranch
if ($controlPlane) {
    if ($null -ne $postOperationPr.autoMergeRequest) {
        throw 'Control-plane PR still has auto-merge enabled after publication.'
    }
}
else {
    if ($null -eq $postOperationPr.autoMergeRequest) {
        throw 'Ordinary PR does not have native auto-merge enabled.'
    }
    $mergeMethodProperty = $postOperationPr.autoMergeRequest.PSObject.Properties['mergeMethod']
    if ($null -ne $mergeMethodProperty -and [string]$mergeMethodProperty.Value -cne 'SQUASH') {
        throw 'Ordinary PR auto-merge method is not SQUASH.'
    }
}

[pscustomobject]@{
    CommitSha = $head
    PullRequest = [int]$postOperationPr.number
    Url = [string]$postOperationPr.url
    Mode = $mode
}
