$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceHook = Join-Path $projectRoot '.githooks/pre-push'
$sourceInstaller = Join-Path $projectRoot 'tools/install_agent_git_hooks.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $systemTemp ("codex-pre-push-guard-test-" + [guid]::NewGuid().ToString('N'))
$repository = Join-Path $testRoot 'repository'
$remote = Join-Path $testRoot 'remote.git'
$linkedWorktree = Join-Path $testRoot 'linked-worktree'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$originalIntegratorBypass = [System.Environment]::GetEnvironmentVariable(
    'CODEX_INTEGRATOR_ALLOW_MAIN_PUSH',
    [System.EnvironmentVariableTarget]::Process
)
Remove-Item Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH -ErrorAction SilentlyContinue

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)

    [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
}

function Invoke-NativeResult {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
    }
}

function Invoke-GitResult {
    param(
        [string]$Repo,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    return Invoke-NativeResult -FilePath 'git' -Arguments (@('-C', $Repo) + $Arguments)
}

function Invoke-Git {
    param(
        [string]$Repo,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $result = Invoke-GitResult $Repo @Arguments
    if ($result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $($result.ExitCode)): $($result.Output)"
    }
    return $result.Output
}

function Assert-Success {
    param($Result, [string]$Label)

    if ($Result.ExitCode -ne 0) {
        throw "$Label should pass, but failed (exit $($Result.ExitCode)): $($Result.Output)"
    }
}

function Assert-Rejected {
    param($Result, [string]$Label)

    if ($Result.ExitCode -eq 0) {
        throw "$Label should be rejected, but passed: $($Result.Output)"
    }
    if ($Result.Output -notmatch 'PRE-PUSH REJECTED') {
        throw "$Label failed without the pre-push policy marker: $($Result.Output)"
    }
}

function Invoke-Installer {
    param([string]$Installer, [string[]]$Arguments = @())

    $windowsPowerShell = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell 5.1 executable was not found at $windowsPowerShell"
    }
    return Invoke-NativeResult -FilePath $windowsPowerShell -Arguments (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Installer) + $Arguments
    )
}

try {
    if (-not (Test-Path -LiteralPath $sourceHook -PathType Leaf)) {
        throw "Source hook is missing: $sourceHook"
    }
    if (-not (Test-Path -LiteralPath $sourceInstaller -PathType Leaf)) {
        throw "Source installer is missing: $sourceInstaller"
    }

    New-Item -ItemType Directory -Path $repository -Force | Out-Null
    & git init --bare -q $remote
    if ($LASTEXITCODE -ne 0) { throw 'git init --bare failed' }
    & git init -q $repository
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }

    Invoke-Git $repository symbolic-ref HEAD refs/heads/main | Out-Null
    Invoke-Git $repository config user.email 'pre-push-test@example.invalid' | Out-Null
    Invoke-Git $repository config user.name 'Pre Push Guard Test' | Out-Null
    Invoke-Git $repository config core.autocrlf false | Out-Null
    Invoke-Git $repository remote add origin $remote | Out-Null

    $hookDirectory = Join-Path $repository '.githooks'
    $toolDirectory = Join-Path $repository 'tools'
    New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceHook -Destination (Join-Path $hookDirectory 'pre-push')
    Copy-Item -LiteralPath $sourceInstaller -Destination (Join-Path $toolDirectory 'install_agent_git_hooks.ps1')
    Write-Utf8NoBom -Path (Join-Path $repository 'base.txt') -Value "base`n"
    Invoke-Git $repository add .githooks/pre-push tools/install_agent_git_hooks.ps1 base.txt | Out-Null
    Invoke-Git $repository commit -q -m 'test fixture' | Out-Null

    $installer = Join-Path $repository 'tools/install_agent_git_hooks.ps1'
    $plan = Invoke-Installer -Installer $installer
    Assert-Success $plan 'plan-only installer'
    if ($plan.Output -notmatch 'PLAN ONLY' -or $plan.Output -notmatch 'no Git configuration was changed') {
        throw "Plan-only output is incomplete: $($plan.Output)"
    }
    $unsetConfig = Invoke-GitResult $repository config --local --get core.hooksPath
    if ($unsetConfig.ExitCode -ne 1) {
        throw "Plan-only mode unexpectedly changed core.hooksPath: $($unsetConfig.Output)"
    }

    $install = Invoke-Installer -Installer $installer -Arguments @('-Install')
    Assert-Success $install 'initial hook installation'
    if ($install.Output -notmatch 'INSTALLED') {
        throw "Initial install did not report INSTALLED: $($install.Output)"
    }
    if ((Invoke-Git $repository config --local --get core.hooksPath) -ne '.githooks') {
        throw 'Initial install did not set repo-local core.hooksPath=.githooks.'
    }

    $idempotent = Invoke-Installer -Installer $installer -Arguments @('-Install')
    Assert-Success $idempotent 'idempotent hook installation'
    if ($idempotent.Output -notmatch 'ALREADY CONFIGURED') {
        throw "Second install was not idempotent: $($idempotent.Output)"
    }

    Invoke-Git $repository branch hook-config-check | Out-Null
    Invoke-Git $repository worktree add -q $linkedWorktree hook-config-check | Out-Null
    if ((Invoke-Git $linkedWorktree config --local --get core.hooksPath) -ne '.githooks') {
        throw 'Linked worktree did not inherit the shared repo-local core.hooksPath.'
    }
    $linkedInstaller = Join-Path $linkedWorktree 'tools/install_agent_git_hooks.ps1'
    $linkedIdempotent = Invoke-Installer -Installer $linkedInstaller -Arguments @('-Install')
    Assert-Success $linkedIdempotent 'linked-worktree idempotent installation'
    if ($linkedIdempotent.Output -notmatch 'ALREADY CONFIGURED') {
        throw "Linked worktree did not see shared configuration: $($linkedIdempotent.Output)"
    }

    Invoke-Git $repository config --local core.hooksPath custom-hooks | Out-Null
    $foreignRejected = Invoke-Installer -Installer $installer -Arguments @('-Install')
    if ($foreignRejected.ExitCode -eq 0 -or $foreignRejected.Output -notmatch 'Refusing to overwrite foreign') {
        throw "Foreign core.hooksPath was not protected: $($foreignRejected.Output)"
    }
    if ((Invoke-Git $repository config --local --get core.hooksPath) -ne 'custom-hooks') {
        throw 'Rejected install still overwrote the foreign core.hooksPath.'
    }
    $forcedInstall = Invoke-Installer -Installer $installer -Arguments @('-Install', '-Force')
    Assert-Success $forcedInstall 'forced replacement of reviewed foreign hook path'
    if ((Invoke-Git $repository config --local --get core.hooksPath) -ne '.githooks') {
        throw 'Forced install did not restore repo-local core.hooksPath=.githooks.'
    }

    Invoke-Git $repository checkout -q -b codex/root/pre-push-test | Out-Null
    Write-Utf8NoBom -Path (Join-Path $repository 'branch.txt') -Value "first`n"
    Invoke-Git $repository add branch.txt | Out-Null
    Invoke-Git $repository commit -q -m 'codex first' | Out-Null
    $firstPush = Invoke-GitResult $repository push origin 'HEAD:refs/heads/codex/root/pre-push-test'
    Assert-Success $firstPush 'first codex/* push'

    Write-Utf8NoBom -Path (Join-Path $repository 'branch.txt') -Value "second`n"
    Invoke-Git $repository add branch.txt | Out-Null
    Invoke-Git $repository commit -q -m 'codex fast forward' | Out-Null
    $fastForwardHead = Invoke-Git $repository rev-parse HEAD
    $fastForwardPush = Invoke-GitResult $repository push origin 'HEAD:refs/heads/codex/root/pre-push-test'
    Assert-Success $fastForwardPush 'existing codex/* fast-forward push'

    $tree = Invoke-Git $repository rev-parse 'HEAD^{tree}'
    $divergentCommit = Invoke-Git $repository commit-tree $tree -m 'divergent root'
    $nonFastForward = Invoke-GitResult $repository push --force origin ("{0}:refs/heads/codex/root/pre-push-test" -f $divergentCommit)
    Assert-Rejected $nonFastForward 'non-fast-forward codex/* force push'
    $remoteCodexHead = Invoke-Git $remote rev-parse refs/heads/codex/root/pre-push-test
    if ($remoteCodexHead -ne $fastForwardHead) {
        throw 'Rejected codex/* force push changed the bare remote.'
    }

    $directMain = Invoke-GitResult $repository push origin 'refs/heads/main:refs/heads/main'
    Assert-Rejected $directMain 'direct main push'
    $directMaster = Invoke-GitResult $repository push origin 'refs/heads/main:refs/heads/master'
    Assert-Rejected $directMaster 'direct master push'
    $otherBranch = Invoke-GitResult $repository push origin 'HEAD:refs/heads/feature/forbidden'
    Assert-Rejected $otherBranch 'other branch push'
    Invoke-Git $repository tag pre-push-guard-test | Out-Null
    $tagPush = Invoke-GitResult $repository push origin refs/tags/pre-push-guard-test
    Assert-Rejected $tagPush 'tag push'

    try {
        $env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH = '1'
        $integratorMain = Invoke-GitResult $repository push origin 'refs/heads/main:refs/heads/main'
    }
    finally {
        Remove-Item Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH -ErrorAction SilentlyContinue
    }
    Assert-Success $integratorMain 'integrator main push'
    if ($integratorMain.Output -notmatch 'INTEGRATOR BYPASS' -or
        $integratorMain.Output -notmatch 'zweryfikowanego run receiptu') {
        throw "Integrator bypass did not warn about the separate verified run receipt: $($integratorMain.Output)"
    }
    if ((Invoke-Git $remote rev-parse refs/heads/main) -ne (Invoke-Git $repository rev-parse refs/heads/main)) {
        throw 'Integrator main push did not publish the expected main ref.'
    }

    $deleteMain = Invoke-GitResult $repository push origin ':refs/heads/main'
    Assert-Rejected $deleteMain 'direct main deletion'
    $deleteCodex = Invoke-GitResult $repository push origin ':refs/heads/codex/root/pre-push-test'
    Assert-Rejected $deleteCodex 'codex/* deletion'

    Write-Host 'PASS pre-push codex-only/fast-forward/integrator-bypass/installer/linked-worktree contract'
}
finally {
    if ($null -eq $originalIntegratorBypass) {
        Remove-Item Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH -ErrorAction SilentlyContinue
    }
    else {
        $env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH = $originalIntegratorBypass
    }

    if (Test-Path -LiteralPath (Join-Path $repository '.git')) {
        if (Test-Path -LiteralPath $linkedWorktree) {
            $removeResult = & git -C $repository worktree remove --force $linkedWorktree 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Final test cleanup could not unregister $linkedWorktree`: $removeResult"
            }
        }
        & git -C $repository worktree prune 2>&1 | Out-Null
    }

    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith(
        $systemTemp + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -and [System.IO.Path]::GetFileName($resolvedTestRoot).StartsWith(
        'codex-pre-push-guard-test-'
    )) {
        if (Test-Path -LiteralPath $resolvedTestRoot) {
            Get-ChildItem -LiteralPath $resolvedTestRoot -Force -Recurse |
                ForEach-Object { $_.Attributes = [System.IO.FileAttributes]::Normal }
            Remove-Item -LiteralPath $resolvedTestRoot -Force -Recurse
        }
    }
}
