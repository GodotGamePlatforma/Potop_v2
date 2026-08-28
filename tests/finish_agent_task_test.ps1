#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceTool = Join-Path $projectRoot 'tools/finish_agent_task.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-finish-task-" + [guid]::NewGuid().ToString('N'))

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& git.exe -C $Repository @Arguments 2>&1); $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "git failed: $(($output | Out-String).Trim())" }
    return ($output | Out-String).Trim()
}

try {
    $repo = Join-Path $tempRoot 'repo'
    $tools = Join-Path $repo 'tools'
    New-Item -ItemType Directory -Path $tools -Force | Out-Null
    Git $tempRoot init -b main $repo | Out-Null
    Git $repo config user.name 'Finish Task Test' | Out-Null
    Git $repo config user.email 'finish-task@example.invalid' | Out-Null
    Copy-Item -LiteralPath $sourceTool -Destination (Join-Path $tools 'finish_agent_task.ps1')
    Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'base' -Encoding UTF8
    Git $repo add . | Out-Null
    Git $repo commit -m base | Out-Null
    Git $repo checkout -b codex/root/test | Out-Null

    $publishLog = Join-Path $repo 'publish.log'
    @'
#requires -Version 5.1
param([string]$Repository,[string]$Title,[string]$Body,[string]$PowerShellCommand,[string[]]$TestTarget,[string]$RepositorySlug,[string]$GodotConsolePath)
if (-not [string]::IsNullOrWhiteSpace((git.exe -C $Repository status --porcelain=v1 --untracked-files=all))) {
    throw 'Publisher received a dirty worktree.'
}
Set-Content -LiteralPath (Join-Path $Repository 'publish.log') -Value "title=$Title targets=$($TestTarget -join ',')"
'@ | Set-Content -LiteralPath (Join-Path $tools 'publish_agent_pr.ps1') -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $repo 'feature.txt') -Value 'feature' -Encoding UTF8
    & (Join-Path $tools 'finish_agent_task.ps1') `
        -Repository $repo `
        -Title 'Simple feature' `
        -CommitMessage 'test: simple feature' `
        -TestTarget 'tests/smoke_test.gd'
    if ((Git $repo log -1 --pretty=%s).Trim() -cne 'test: simple feature') {
        throw 'The one-command publisher did not create the requested commit.'
    }
    $log = Get-Content -LiteralPath $publishLog -Raw
    if ($log -notmatch 'title=Simple feature' -or $log -notmatch 'tests/smoke_test.gd') {
        throw "The committed task was not delegated to the exact PR publisher: $log"
    }

    Remove-Item -LiteralPath $publishLog
    & (Join-Path $tools 'finish_agent_task.ps1') -Repository $repo -Title 'Publish existing commit'
    if (-not (Test-Path -LiteralPath $publishLog -PathType Leaf)) {
        throw 'A clean precommitted task was not delegated to the PR publisher.'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'PASS one-command commit and exact PR publication contract'
