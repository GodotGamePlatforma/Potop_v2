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
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git.exe -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Git {
    param([string]$Repository, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = Git-Result $Repository @Arguments
    if ($result.ExitCode -ne 0) { throw "git failed: $($result.Output)" }
    return $result.Output
}

function Invoke-Hook {
    param(
        [string]$Repository,
        [byte[]]$InputBytes,
        [string]$HookPath,
        [string]$GitWrapper,
        [string]$WrapperScript,
        [string]$RealGit,
        [string]$CapturePath
    )
    $gitRoot = Split-Path -Parent (Split-Path -Parent $RealGit)
    $sh = Join-Path $gitRoot 'bin/sh.exe'
    if (-not (Test-Path -LiteralPath $sh -PathType Leaf)) {
        $sh = Join-Path $gitRoot 'usr/bin/sh.exe'
    }
    if (-not (Test-Path -LiteralPath $sh -PathType Leaf)) {
        throw "Cannot locate Git for Windows sh.exe next to '$RealGit'."
    }
    $inputPath = $CapturePath + '.input'
    [System.IO.File]::WriteAllBytes($inputPath, $InputBytes)
    $hookForShell = $HookPath.Replace('\', '/')
    $inputForShell = $inputPath.Replace('\', '/')
    $wrapperDirectory = (Split-Path -Parent $GitWrapper).Replace('\', '/')
    if ($wrapperDirectory -match '^([A-Za-z]):/(.*)$') {
        $wrapperDirectory = '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2]
    }
    $shellCommand = "PATH='$wrapperDirectory':`$PATH; export PATH; '$hookForShell' origin https://example.invalid/repo.git < '$inputForShell'"
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $sh
    $start.Arguments = "-c `"$shellCommand`""
    $start.WorkingDirectory = $Repository
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['GIT_WRAPPER_PY'] = $WrapperScript
    $start.EnvironmentVariables['GIT_WRAPPER_REAL'] = $RealGit
    $start.EnvironmentVariables['GIT_WRAPPER_CAPTURE'] = $CapturePath
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Cannot start pre-push hook fixture.' }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Remove-Item -LiteralPath $inputPath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = ($stdout + $stderr).Trim()
    }
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
    Set-Content -LiteralPath (Join-Path $repo 'file.txt') -Value 'one' -Encoding UTF8
    Git $repo add . | Out-Null
    Git $repo commit -m initial | Out-Null
    $initialHead = (Git $repo rev-parse HEAD).Trim()
    Git $repo remote add origin $remote | Out-Null
    Git $repo checkout -b codex/root/feature | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'file.txt') -Value 'two' -Encoding UTF8
    Git $repo add file.txt | Out-Null
    Git $repo commit -m feature | Out-Null
    $featureHead = (Git $repo rev-parse HEAD).Trim()

    $allowed = Git-Result $repo push -u origin codex/root/feature
    if ($allowed.ExitCode -ne 0) { throw "codex/* push failed: $($allowed.Output)" }

    $mainPush = Git-Result $repo push origin HEAD:refs/heads/main
    if ($mainPush.ExitCode -eq 0 -or $mainPush.Output -notmatch 'refs/heads/main') {
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
    if ($delete.ExitCode -eq 0 -or $delete.Output -notmatch 'refs/heads/codex/root/feature') {
        throw 'Branch deletion was not rejected.'
    }

    $wrapperBin = Join-Path $tempRoot 'mock-bin'
    New-Item -ItemType Directory -Path $wrapperBin | Out-Null
    $wrapper = Join-Path $wrapperBin 'git'
    $wrapperScript = Join-Path $tempRoot 'git_wrapper.py'
    $capture = Join-Path $tempRoot 'lfs-input.bin'
    [System.IO.File]::WriteAllText(
        $wrapper,
        "#!/bin/sh`nexec python `"`$GIT_WRAPPER_PY`" `"`$@`"`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $wrapperScript,
        @'
import os
import subprocess
import sys

args = sys.argv[1:]
if args[:2] == ["lfs", "version"]:
    print("git-lfs/3.0.0")
    raise SystemExit(0)
if args[:2] == ["lfs", "pre-push"]:
    payload = sys.stdin.buffer.read()
    with open(os.environ["GIT_WRAPPER_CAPTURE"], "wb") as handle:
        handle.write(payload)
    raise SystemExit(0)
completed = subprocess.run([os.environ["GIT_WRAPPER_REAL"], *args], check=False)
raise SystemExit(completed.returncode)
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    $zero = '0' * 40
    $streamText = "refs/heads/codex/root/new $featureHead refs/heads/codex/root/new $zero`n" +
        "refs/heads/codex/root/feature $featureHead refs/heads/codex/root/feature $initialHead`n"
    $streamBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($streamText)
    $hookResult = Invoke-Hook `
        -Repository $repo `
        -InputBytes $streamBytes `
        -HookPath $sourceHook `
        -GitWrapper $wrapper `
        -WrapperScript $wrapperScript `
        -RealGit @(Get-Command git.exe -CommandType Application)[0].Source `
        -CapturePath $capture
    if ($hookResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $capture)) {
        throw "Instrumented multi-ref hook failed: $($hookResult.Output)"
    }
    $capturedBytes = [System.IO.File]::ReadAllBytes($capture)
    if (-not [System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($streamBytes, $capturedBytes)) {
        throw "Pre-push did not forward the exact multi-ref byte stream to Git LFS (expected $($streamBytes.Length) bytes, got $($capturedBytes.Length))."
    }

    Git $repo checkout -b codex/root/divergent main | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'file.txt') -Value 'divergent' -Encoding UTF8
    Git $repo add file.txt | Out-Null
    Git $repo commit -m divergent | Out-Null
    $divergentHead = (Git $repo rev-parse HEAD).Trim()
    Remove-Item -LiteralPath $capture -Force
    $nonFastForwardText = "refs/heads/codex/root/feature $divergentHead refs/heads/codex/root/feature $featureHead`n"
    $nonFastForward = Invoke-Hook `
        -Repository $repo `
        -InputBytes ([System.Text.UTF8Encoding]::new($false).GetBytes($nonFastForwardText)) `
        -HookPath $sourceHook `
        -GitWrapper $wrapper `
        -WrapperScript $wrapperScript `
        -RealGit @(Get-Command git.exe -CommandType Application)[0].Source `
        -CapturePath $capture
    if ($nonFastForward.ExitCode -eq 0 -or $nonFastForward.Output -notmatch 'non-fast-forward' -or
        (Test-Path -LiteralPath $capture)) {
        throw 'Non-fast-forward codex/* update was not rejected before Git LFS.'
    }

    $hookText = Get-Content -LiteralPath $sourceHook -Raw
    if ($hookText -match 'CODEX_INTEGRATOR' -or
        $hookText -notmatch 'cat > "\$updates_file"' -or
        $hookText -notmatch '"\$git_command" lfs pre-push "\$remote_name" "\$remote_url" < "\$updates_file"' -or
        $hookText -notmatch 'merge-base --is-ancestor') {
        throw 'Hook source contains a main bypass or lost the LFS chain.'
    }
    Write-Host 'PASS pre-push codex-only/no-main-bypass/no-delete/no-non-FF/exact-multi-ref-LFS-stream contract'
}
finally {
    if (Test-Path Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH) { Remove-Item Env:CODEX_INTEGRATOR_ALLOW_MAIN_PUSH }
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
