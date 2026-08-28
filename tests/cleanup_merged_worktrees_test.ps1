#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/cleanup_merged_worktrees.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-cleanup-worktrees-" + [guid]::NewGuid().ToString('N'))

function Git {
    param([string]$Repository,[Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& git.exe -C $Repository @Arguments 2>&1); $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "git failed: $(($output | Out-String).Trim())" }
    return ($output | Out-String).Trim()
}

try {
    $repo = Join-Path $tempRoot 'repo'
    $managed = Join-Path $tempRoot 'managed'
    $bin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Path $repo,$managed,$bin -Force | Out-Null
    Git $repo init -b main | Out-Null
    Git $repo config user.name 'Cleanup Test' | Out-Null
    Git $repo config user.email 'cleanup@example.invalid' | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'base' -Encoding UTF8
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null

    $heads = @{}
    foreach ($name in @('merged','dirty','open','mismatch')) {
        $path = Join-Path $managed $name
        $branch = "codex/root/$name"
        Git $repo worktree add -b $branch $path main | Out-Null
        Set-Content -LiteralPath (Join-Path $path "$name.txt") -Value $name -Encoding UTF8
        Git $path add . | Out-Null
        Git $path commit -m $name | Out-Null
        $heads[$name] = (Git $path rev-parse HEAD).Trim()
    }
    Set-Content -LiteralPath (Join-Path $managed 'dirty/untracked.txt') -Value dirty -Encoding UTF8

    $map = [ordered]@{
        'codex/root/merged' = @([ordered]@{
            number = 10; state = 'MERGED'; mergedAt = '2020-01-01T00:00:00Z'
            headRefName = 'codex/root/merged'; headRefOid = $heads.merged
            baseRefName = 'main'; url = 'https://example.invalid/pr/10'
        })
        'codex/root/dirty' = @([ordered]@{
            number = 11; state = 'MERGED'; mergedAt = '2020-01-01T00:00:00Z'
            headRefName = 'codex/root/dirty'; headRefOid = $heads.dirty
            baseRefName = 'main'; url = 'https://example.invalid/pr/11'
        })
        'codex/root/mismatch' = @([ordered]@{
            number = 12; state = 'MERGED'; mergedAt = '2020-01-01T00:00:00Z'
            headRefName = 'codex/root/mismatch'; headRefOid = ('f' * 40)
            baseRefName = 'main'; url = 'https://example.invalid/pr/12'
        })
    }
    $mapPath = Join-Path $tempRoot 'pr-map.json'
    $map | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $mapPath -Encoding UTF8
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$headIndex = [Array]::IndexOf($Rest, '--head')
$branches = if ($headIndex -ge 0) { @($Rest[$headIndex + 1]) } else {
    @('codex/root/merged','codex/root/dirty','codex/root/mismatch')
}
$records = @()
foreach ($branch in $branches) {
    $head = switch ($branch) {
        'codex/root/merged' { $env:MOCK_MERGED_HEAD }
        'codex/root/dirty' { $env:MOCK_DIRTY_HEAD }
        'codex/root/mismatch' { 'ffffffffffffffffffffffffffffffffffffffff' }
        default { '' }
    }
    if ([string]::IsNullOrWhiteSpace($head)) { continue }
    $number = if ($branch -eq 'codex/root/merged') { 10 } elseif ($branch -eq 'codex/root/dirty') { 11 } else { 12 }
    $records += [pscustomobject]@{
        number=$number; state='MERGED'; mergedAt='2020-01-01T00:00:00Z'
        headRefName=$branch; headRefOid=$head; baseRefName='main'
        url="https://example.invalid/pr/$number"
    }
}
Write-Output (ConvertTo-Json -InputObject $records -Depth 4 -Compress)
'@ | Set-Content -LiteralPath (Join-Path $bin 'gh.ps1') -Encoding UTF8

    $oldPath = $env:PATH
    $env:PATH = "$bin$([System.IO.Path]::PathSeparator)$oldPath"
    $env:MOCK_PR_MAP = $mapPath
    $env:MOCK_MERGED_HEAD = $heads.merged
    $env:MOCK_DIRTY_HEAD = $heads.dirty
    try {
        $mockProbe = @(& (Join-Path $bin 'gh.ps1') pr list --head codex/root/merged 2>&1)
        $mockParsed = $mockProbe | Out-String | ConvertFrom-Json
        if ([string]$mockParsed.headRefOid -cne [string]$heads.merged) {
            throw "Mock PR binding is invalid: $($mockProbe | Out-String)"
        }
        $plan = @(& $tool -Repository $repo -ManagedRoot $managed -RepositorySlug 'test/repo' -GhCommand (Join-Path $bin 'gh.ps1') -MinimumMergedAgeMinutes 0 2>&1)
        if ($LASTEXITCODE -ne 0 -or ($plan | Out-String) -notmatch 'WOULD REMOVE.*codex/root/merged') {
            throw "Cleanup plan did not identify the exact merged worktree: $($plan | Out-String)"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $managed 'merged'))) {
            throw 'Plan-only cleanup removed a worktree.'
        }

        $apply = @(& $tool -Repository $repo -ManagedRoot $managed -RepositorySlug 'test/repo' -GhCommand (Join-Path $bin 'gh.ps1') -MinimumMergedAgeMinutes 0 -Apply 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Cleanup apply failed: $($apply | Out-String)" }
    }
    finally {
        $env:PATH = $oldPath
        Remove-Item Env:MOCK_PR_MAP,Env:MOCK_MERGED_HEAD,Env:MOCK_DIRTY_HEAD -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath (Join-Path $managed 'merged')) {
        throw 'Exact merged clean worktree was not removed.'
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $mergedRef = @(& git.exe -C $repo show-ref --verify --quiet refs/heads/codex/root/merged 2>&1)
        $mergedRefExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($mergedRefExit -eq 0) { throw 'Exact merged local branch was not deleted with CAS.' }
    foreach ($name in @('dirty','open','mismatch')) {
        if (-not (Test-Path -LiteralPath (Join-Path $managed $name))) {
            throw "Cleanup removed protected worktree '$name'."
        }
    }

    $source = Get-Content -LiteralPath $tool -Raw
    foreach ($forbidden in @('reset --hard','worktree remove --force','branch -D','push origin --delete')) {
        if ($source -match [regex]::Escape($forbidden)) {
            throw "Cleanup contains destructive shortcut '$forbidden'."
        }
    }
    foreach ($required in @('headRefOid','MinimumMergedAgeMinutes','ReparsePoint',"'update-ref', '-d'")) {
        if (-not $source.Contains($required)) { throw "Cleanup guard is missing: $required" }
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'PASS exact-merged clean-only local worktree cleanup contract'
