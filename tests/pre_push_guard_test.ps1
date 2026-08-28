#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceHook = Join-Path $projectRoot '.githooks/pre-push'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-pre-push-test-" + [guid]::NewGuid().ToString('N'))

function Git-Result {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git.exe -C $Repository @Arguments 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String).Trim() }
}

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = Git-Result $Repository @Arguments
    if ($result.ExitCode -ne 0) { throw "git failed: $($result.Output)" }
    return $result.Output
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $remote = Join-Path $tempRoot 'origin.git'
    $repo = Join-Path $tempRoot 'repo'
    Git $tempRoot init --bare $remote | Out-Null
    Git $tempRoot init -b main $repo | Out-Null
    Git $repo config user.email 'hook-test@example.invalid' | Out-Null
    Git $repo config user.name 'Hook Test' | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo '.githooks') | Out-Null
    Copy-Item -LiteralPath $sourceHook -Destination (Join-Path $repo '.githooks/pre-push')
    Git $repo config core.hooksPath .githooks | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'file.txt') -Value 'one' -Encoding utf8NoBOM
    Git $repo add . | Out-Null
    Git $repo commit -m initial | Out-Null
    Git $repo remote add origin $remote | Out-Null
    Git $repo checkout -b codex/root/feature | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'file.txt') -Value 'two' -Encoding utf8NoBOM
    Git $repo add file.txt | Out-Null
    Git $repo commit -m feature | Out-Null

    $allowed = Git-Result $repo push -u origin codex/root/feature
    if ($allowed.ExitCode -ne 0) { throw "codex/* push failed: $($allowed.Output)" }

    $mainPush = Git-Result $repo push origin HEAD:refs/heads/main
    if ($mainPush.ExitCode -eq 0 -or $mainPush.Output -notmatch 'bezpośredni push') {
        throw 'Direct main push was not rejected.'
    }
    $env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH = '1'
    $mainWithLegacyBypass = Git-Result $repo push origin HEAD:refs/heads/main
    Remove-Item Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH -ErrorAction SilentlyContinue
    if ($mainWithLegacyBypass.ExitCode -eq 0) {
        throw 'Legacy integrator environment variable bypassed main protection.'
    }
    $other = Git-Result $repo push origin HEAD:refs/heads/release
    if ($other.ExitCode -eq 0 -or $other.Output -notmatch 'codex') {
        throw 'Non-codex agent branch was not rejected.'
    }
    $delete = Git-Result $repo push origin :refs/heads/codex/root/feature
    if ($delete.ExitCode -eq 0 -or $delete.Output -notmatch 'kasowanie') {
        throw 'Branch deletion was not rejected.'
    }

    $hookText = Get-Content -LiteralPath $sourceHook -Raw
    if ($hookText -match 'CODEX_INTEGRATOR' -or
        $hookText -notmatch 'cat > "\$updates_file"' -or
        $hookText -notmatch 'git lfs pre-push "\$remote_name" "\$remote_url" < "\$updates_file"') {
        throw 'Hook source contains a main bypass or lost the LFS chain.'
    }
    Write-Host 'PASS pre-push codex-only/no-main-bypass/no-delete/exact-LFS-stream contract'
}
finally {
    if (Test-Path Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH) { Remove-Item Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH }
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
