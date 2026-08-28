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

function Get-EffectiveOriginSlug {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [string]$ExplicitSlug
    )

    $fetchUrls = @(
        (Invoke-Checked git @('remote', 'get-url', '--all', 'origin') $RepositoryPath) -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $pushUrls = @(
        (Invoke-Checked git @('remote', 'get-url', '--push', '--all', 'origin') $RepositoryPath) -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($fetchUrls.Count -ne 1) {
        throw "Expected exactly one effective origin fetch URL; found $($fetchUrls.Count)."
    }
    if ($pushUrls.Count -ne 1) {
        throw "Expected exactly one effective origin push URL; found $($pushUrls.Count)."
    }

    $fetchSlug = Convert-OriginUrlToSlug $fetchUrls[0]
    $pushSlug = Convert-OriginUrlToSlug $pushUrls[0]
    if (-not [string]::Equals($fetchSlug, $pushSlug, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Effective origin fetch '$fetchSlug' and push '$pushSlug' target different repositories."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExplicitSlug) -and
        -not [string]::Equals($ExplicitSlug.Trim(), $fetchSlug, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "RepositorySlug '$ExplicitSlug' does not match effective origin '$fetchSlug'."
    }
    return $fetchSlug
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
        '--json', 'number,url,state,headRefName,headRefOid,baseRefName,autoMergeRequest,isCrossRepository,headRepository,headRepositoryOwner'
    ) $RepositoryPath
    try {
        $pr = $json | ConvertFrom-Json
    }
    catch {
        throw "GitHub returned invalid PR JSON for #${Number}: $json"
    }
    $required = @(
        'number', 'url', 'state', 'headRefName', 'headRefOid', 'baseRefName',
        'autoMergeRequest', 'isCrossRepository', 'headRepository', 'headRepositoryOwner'
    )
    $available = @($pr.PSObject.Properties.Name)
    foreach ($property in $required) {
        if ($available -notcontains $property) {
            throw "GitHub PR JSON is missing '$property' for #$Number."
        }
    }
    return $pr
}

function Read-NativeMergeQueueSnapshot {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Slug,
        [Parameter(Mandatory = $true)][string]$BaseBranch,
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )

    $slugParts = @($Slug -split '/', 2)
    if ($slugParts.Count -ne 2) {
        throw "Repository slug is not one owner/name pair: '$Slug'."
    }
    $query = @'
query($owner:String!,$name:String!,$number:Int!,$base:String!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      state
      headRefName
      headRefOid
      baseRefName
      autoMergeRequest{enabledAt}
      mergeQueueEntry{mergeQueue{id}}
    }
    mergeQueue(branch:$base){id configuration{mergeMethod}}
  }
}
'@
    $json = Invoke-Checked gh @(
        'api', 'graphql',
        '-F', "owner=$($slugParts[0])",
        '-F', "name=$($slugParts[1])",
        '-F', "number=$Number",
        '-F', "base=$BaseBranch",
        '-f', "query=$query"
    ) $RepositoryPath
    try {
        $payload = $json | ConvertFrom-Json
    }
    catch {
        throw "GitHub returned invalid merge queue JSON for #${Number}: $json"
    }
    if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['data'] -or
        $null -eq $payload.data -or $null -eq $payload.data.PSObject.Properties['repository'] -or
        $null -eq $payload.data.repository) {
        throw "GitHub did not return repository merge queue data for #$Number."
    }
    $repository = $payload.data.repository
    foreach ($property in @('pullRequest', 'mergeQueue')) {
        if ($null -eq $repository.PSObject.Properties[$property]) {
            throw "GitHub merge queue JSON is missing '$property' for #$Number."
        }
    }
    if ($null -eq $repository.pullRequest) {
        throw "GitHub did not return PR #$Number while checking the native merge queue."
    }
    return $repository
}

function Assert-NativeSquashQueue {
    param(
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$HeadSha,
        [Parameter(Mandatory = $true)][string]$BaseBranch,
        [switch]$RequireAccepted
    )

    $pr = $Snapshot.pullRequest
    if ([string]$pr.state -cne 'OPEN' -or
        [string]$pr.headRefName -cne $Branch -or
        [string]$pr.headRefOid -cne $HeadSha -or
        [string]$pr.baseRefName -cne $BaseBranch) {
        throw 'Native merge queue snapshot does not match the exact open branch/base/HEAD.'
    }
    if ($null -eq $Snapshot.mergeQueue -or
        $null -eq $Snapshot.mergeQueue.PSObject.Properties['id'] -or
        [string]::IsNullOrWhiteSpace([string]$Snapshot.mergeQueue.id) -or
        $null -eq $Snapshot.mergeQueue.PSObject.Properties['configuration'] -or
        $null -eq $Snapshot.mergeQueue.configuration -or
        $null -eq $Snapshot.mergeQueue.configuration.PSObject.Properties['mergeMethod'] -or
        [string]$Snapshot.mergeQueue.configuration.mergeMethod -cne 'SQUASH') {
        throw "Base branch '$BaseBranch' does not have an exact native SQUASH merge queue."
    }

    $entry = $pr.mergeQueueEntry
    if ($null -ne $entry) {
        if ($null -eq $entry.PSObject.Properties['mergeQueue'] -or
            $null -eq $entry.mergeQueue -or
            $null -eq $entry.mergeQueue.PSObject.Properties['id'] -or
            [string]$entry.mergeQueue.id -cne [string]$Snapshot.mergeQueue.id) {
            throw "PR merge queue entry does not belong to the exact '$BaseBranch' queue."
        }
    }
    if ($RequireAccepted) {
        $hasAutoRequest = $null -ne $pr.autoMergeRequest
        $hasQueueEntry = $null -ne $entry
        if (-not $hasAutoRequest -and -not $hasQueueEntry) {
            throw 'GitHub did not return an accepted native state: auto-merge request or merge queue entry.'
        }
    }
}

function Assert-PrIdentity {
    param(
        [Parameter(Mandatory = $true)][object]$PullRequest,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$HeadSha,
        [Parameter(Mandatory = $true)][string]$BaseBranch,
        [Parameter(Mandatory = $true)][string]$RepositorySlug
    )
    if ([string]$PullRequest.state -cne 'OPEN' -or
        [string]$PullRequest.headRefName -cne $Branch -or
        [string]$PullRequest.headRefOid -cne $HeadSha -or
        [string]$PullRequest.baseRefName -cne $BaseBranch) {
        throw 'Published PR does not match the exact open branch/base/HEAD.'
    }

    $crossRepositoryProperty = $PullRequest.PSObject.Properties['isCrossRepository']
    if ($null -eq $crossRepositoryProperty -or $crossRepositoryProperty.Value -isnot [bool]) {
        throw 'Published PR does not provide an unambiguous isCrossRepository binding.'
    }
    if ([bool]$crossRepositoryProperty.Value) {
        throw 'Published PR head belongs to a different repository.'
    }
    if ($null -eq $PullRequest.headRepository -or $null -eq $PullRequest.headRepositoryOwner) {
        throw 'Published PR does not provide head repository identity.'
    }
    $nameProperty = $PullRequest.headRepository.PSObject.Properties['name']
    $nameWithOwnerProperty = $PullRequest.headRepository.PSObject.Properties['nameWithOwner']
    $ownerProperty = $PullRequest.headRepositoryOwner.PSObject.Properties['login']
    if ($null -eq $nameProperty -or $null -eq $nameWithOwnerProperty -or $null -eq $ownerProperty -or
        [string]::IsNullOrWhiteSpace([string]$nameProperty.Value) -or
        [string]::IsNullOrWhiteSpace([string]$nameWithOwnerProperty.Value) -or
        [string]::IsNullOrWhiteSpace([string]$ownerProperty.Value)) {
        throw 'Published PR head repository owner/name binding is incomplete.'
    }
    $headRepositorySlug = "$([string]$ownerProperty.Value)/$([string]$nameProperty.Value)"
    if (-not [string]::Equals($headRepositorySlug, [string]$nameWithOwnerProperty.Value, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($headRepositorySlug, $RepositorySlug, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Published PR head repository '$headRepositorySlug' does not match '$RepositorySlug'."
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

# Resolve identity through Git before the first network operation. This includes
# url.*.insteadOf and pushInsteadOf rewrites, unlike raw remote.origin.url.
$slug = Get-EffectiveOriginSlug -RepositoryPath $repo -ExplicitSlug $RepositorySlug

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
    'push', 'origin',
    "${head}:refs/heads/$branch"
) $repo | Out-Null
$remoteLine = (Invoke-Checked git @('ls-remote', '--heads', 'origin', "refs/heads/$branch") $repo).Trim()
$remoteFields = @($remoteLine -split '\s+')
if ($remoteFields.Count -ne 2 -or $remoteFields[0] -cne $head -or
    $remoteFields[1] -cne "refs/heads/$branch") {
    throw 'Remote branch does not resolve to the exact published HEAD.'
}
$postPushBranchRef = (Invoke-Checked git @('rev-parse', "refs/heads/$branch") $repo).Trim()
if ((Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim() -cne $head -or
    (Invoke-Checked git @('branch', '--show-current') $repo).Trim() -cne $branch -or
    $postPushBranchRef -cne $head -or
    -not [string]::IsNullOrWhiteSpace(
        (Invoke-Checked git @('status', '--porcelain=v1', '--untracked-files=all') $repo)
    )) {
    throw 'HEAD, branch ref or clean state changed while publishing the exact commit.'
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
    $existingPr = Read-Pr -Number ([int]$open[0].number) -Slug $slug -RepositoryPath $repo
    Assert-PrIdentity `
        -PullRequest $existingPr `
        -Branch $branch `
        -HeadSha $head `
        -BaseBranch $BaseBranch `
        -RepositorySlug $slug
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
Assert-PrIdentity `
    -PullRequest $pr `
    -Branch $branch `
    -HeadSha $head `
    -BaseBranch $BaseBranch `
    -RepositorySlug $slug

$mode = 'manual-control-plane'
if ($controlPlane) {
    if ($null -ne $pr.autoMergeRequest) {
        Invoke-Checked gh @(
            'pr', 'merge', [string]$pr.number, '--repo', $slug, '--disable-auto'
        ) $repo | Out-Null
    }
}
else {
    $preQueueSnapshot = Read-NativeMergeQueueSnapshot `
        -Number ([int]$pr.number) `
        -Slug $slug `
        -BaseBranch $BaseBranch `
        -RepositoryPath $repo
    Assert-NativeSquashQueue `
        -Snapshot $preQueueSnapshot `
        -Branch $branch `
        -HeadSha $head `
        -BaseBranch $BaseBranch
    Invoke-Checked gh @(
        'pr', 'merge', [string]$pr.number, '--repo', $slug,
        '--auto', '--squash', '--match-head-commit', $head
    ) $repo | Out-Null
    $mode = 'native-auto-merge'
}

$postOperationPr = Read-Pr -Number ([int]$pr.number) -Slug $slug -RepositoryPath $repo
Assert-PrIdentity `
    -PullRequest $postOperationPr `
    -Branch $branch `
    -HeadSha $head `
    -BaseBranch $BaseBranch `
    -RepositorySlug $slug
if ($controlPlane) {
    if ($null -ne $postOperationPr.autoMergeRequest) {
        throw 'Control-plane PR still has auto-merge enabled after publication.'
    }
}
else {
    $postQueueSnapshot = Read-NativeMergeQueueSnapshot `
        -Number ([int]$postOperationPr.number) `
        -Slug $slug `
        -BaseBranch $BaseBranch `
        -RepositoryPath $repo
    Assert-NativeSquashQueue `
        -Snapshot $postQueueSnapshot `
        -Branch $branch `
        -HeadSha $head `
        -BaseBranch $BaseBranch `
        -RequireAccepted
}

$finalRemoteLine = (Invoke-Checked git @('ls-remote', '--heads', 'origin', "refs/heads/$branch") $repo).Trim()
$finalRemoteFields = @($finalRemoteLine -split '\s+')
if ($finalRemoteFields.Count -ne 2 -or $finalRemoteFields[0] -cne $head -or
    $finalRemoteFields[1] -cne "refs/heads/$branch" -or
    (Invoke-Checked git @('rev-parse', 'HEAD') $repo).Trim() -cne $head -or
    (Invoke-Checked git @('rev-parse', "refs/heads/$branch") $repo).Trim() -cne $head -or
    (Invoke-Checked git @('branch', '--show-current') $repo).Trim() -cne $branch -or
    -not [string]::IsNullOrWhiteSpace(
        (Invoke-Checked git @('status', '--porcelain=v1', '--untracked-files=all') $repo)
    )) {
    throw 'Repository state drifted after PR publication.'
}

[pscustomobject]@{
    CommitSha = $head
    PullRequest = [int]$postOperationPr.number
    Url = [string]$postOperationPr.url
    Mode = $mode
}
