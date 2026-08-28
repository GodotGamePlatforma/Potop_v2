#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Repository = '.',
    [string]$BuildRoot,
    [string]$GodotConsolePath,
    [string]$ExportPreset = 'Windows Desktop',
    [ValidateRange(1, 600)][int]$SmokeFrames = 10,
    [ValidateRange(5, 600)][int]$SmokeTimeoutSeconds = 90,
    [ValidateRange(10, 3600)][int]$ExportTimeoutSeconds = 900,
    [switch]$Watch,
    [ValidateRange(5, 300)][int]$PollSeconds = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $output = & $FilePath @Arguments 2>&1
        }
        else {
            Push-Location -LiteralPath $WorkingDirectory
            try { $output = & $FilePath @Arguments 2>&1 }
            finally { Pop-Location }
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        throw "$FilePath $($Arguments -join ' ') failed ($exitCode): $text"
    }
    return $text
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    return Invoke-Native -FilePath 'git' -Arguments (@('-C', $script:RepoRoot) + $Arguments)
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [hashtable]$Environment = @{}
    )

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($name in $Environment.Keys) { $start.Environment[$name] = [string]$Environment[$name] }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "Could not start '$FilePath'." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch {}
        $process.WaitForExit()
        throw "Process timed out after $TimeoutSeconds seconds: $FilePath"
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = (($stdout, $stderr) -join "`n").Trim()
    }
}

function Write-DurableText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None,
        4096,
        [System.IO.FileOptions]::WriteThrough
    )
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}

function Resolve-PrivateChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped its private root: $fullPath"
    }
    return $fullPath
}

function Remove-PrivateDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label must be a directory: $Path"
    }
    $fullPath = Resolve-PrivateChildPath -Path $Path -AllowedRoot $AllowedRoot -Label $Label
    [System.IO.Directory]::Delete($fullPath, $true)
}

function Set-CurrentPointer {
    param([Parameter(Mandatory = $true)][string]$Sha)

    $current = Join-Path $script:BuildRootPath 'current'
    $temporary = Join-Path $script:BuildRootPath (".current-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    Write-DurableText -Path $temporary -Text "$Sha`n"
    try {
        if ((Test-Path -LiteralPath $current) -and
            -not (Test-Path -LiteralPath $current -PathType Leaf)) {
            throw 'builds/current must be a file containing one full SHA.'
        }
        [System.IO.File]::Move($temporary, $current, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [System.IO.File]::Delete($temporary)
        }
    }
}

function Test-CompleteArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Sha
    )

    $metadataPath = Join-Path $Directory 'build.json'
    $passPath = Join-Path $Directory 'PASS'
    $exePath = Join-Path $Directory 'OstatniPomost.exe'
    $pckPath = Join-Path $Directory 'OstatniPomost.pck'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $passPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $exePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $pckPath -PathType Leaf) -or
        (Get-Item -LiteralPath $exePath).Length -le 0 -or
        (Get-Item -LiteralPath $pckPath).Length -le 0) {
        return $false
    }
    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $pass = (Get-Content -LiteralPath $passPath -Raw).Trim()
        return $metadata.schema -ceq 'potop-playable-build-v1' -and
            $metadata.sha -ceq $Sha -and
            $metadata.status -ceq 'PASS' -and
            $pass -ceq $Sha
    }
    catch { return $false }
}

function Resolve-GodotConsole {
    if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
        $candidate = [System.IO.Path]::GetFullPath($GodotConsolePath)
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Godot console executable does not exist: $candidate"
        }
        return $candidate
    }
    foreach ($name in @('godot_console.exe', 'Godot_v4.7.1-stable_win64_console.exe', 'godot')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Godot console executable was not found. Pass -GodotConsolePath.'
}

function Invoke-LfsCheckout {
    param([Parameter(Mandatory = $true)][string]$Workspace)

    $hadSkipSmudge = Test-Path -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE'
    $previousSkipSmudge = [string]$env:GIT_LFS_SKIP_SMUDGE
    try {
        Remove-Item -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE' -ErrorAction SilentlyContinue
        Invoke-Native -FilePath 'git' -Arguments @(
            '-C', $Workspace,
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'checkout'
        ) | Out-Null
    }
    finally {
        if ($hadSkipSmudge) { $env:GIT_LFS_SKIP_SMUDGE = $previousSkipSmudge }
        else { Remove-Item -LiteralPath 'Env:GIT_LFS_SKIP_SMUDGE' -ErrorAction SilentlyContinue }
    }
}

function Remove-BuilderWorktree {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Sha
    )

    if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { return }
    $fullWorkspace = Resolve-PrivateChildPath `
        -Path $Workspace -AllowedRoot $script:WorktreeRoot -Label 'Builder worktree cleanup'
    $actualRoot = (Invoke-Native -FilePath 'git' -Arguments @(
        '-C', $fullWorkspace, 'rev-parse', '--show-toplevel'
    )).Trim()
    $actualSha = (Invoke-Native -FilePath 'git' -Arguments @(
        '-C', $fullWorkspace, 'rev-parse', 'HEAD'
    )).Trim()
    if (-not [string]::Equals(
            [System.IO.Path]::GetFullPath($actualRoot).TrimEnd('\', '/'),
            $fullWorkspace,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or $actualSha -cne $Sha) {
        throw "Builder worktree identity changed; preserving it for manual inspection: $fullWorkspace"
    }
    Invoke-Git -Arguments @('worktree', 'remove', '--force', '--', $fullWorkspace) | Out-Null
}

function Sync-Main {
    $sync = Join-Path $script:RepoRoot 'tools/sync_play_main.ps1'
    $result = Invoke-CapturedProcess -FilePath 'pwsh' -Arguments @(
        '-NoLogo', '-NoProfile', '-File', $sync,
        '-Repository', $script:RepoRoot
    ) -WorkingDirectory $script:RepoRoot -TimeoutSeconds 600
    if ($result.ExitCode -ne 0) { throw "Main sync failed: $($result.Output)" }

    $sha = (Invoke-Git -Arguments @('rev-parse', 'HEAD')).Trim()
    $mainSha = (Invoke-Git -Arguments @('rev-parse', 'refs/heads/main')).Trim()
    $remoteSha = (Invoke-Git -Arguments @('rev-parse', 'refs/remotes/origin/main')).Trim()
    $branch = (Invoke-Git -Arguments @('branch', '--show-current')).Trim()
    $status = Invoke-Git -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    if ($sha -cnotmatch '^[0-9a-f]{40}$' -or $sha -cne $mainSha -or $sha -cne $remoteSha -or
        $branch -cne 'main' -or -not [string]::IsNullOrWhiteSpace($status)) {
        throw "Builder source is not exact clean origin/main: branch=$branch HEAD=$sha main=$mainSha origin/main=$remoteSha status='$status'."
    }
    return $sha
}

function Publish-LastFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Staging,
        [Parameter(Mandatory = $true)][string]$Sha,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not (Test-Path -LiteralPath $Staging -PathType Container)) { return }
    $metadata = [ordered]@{
        schema = 'potop-playable-build-failure-v1'
        status = 'FAIL'
        sha = $Sha
        failed_at_utc = [DateTime]::UtcNow.ToString('o')
        message = $Message
    } | ConvertTo-Json
    Write-DurableText -Path (Join-Path $Staging 'FAIL.json') -Text ($metadata + "`n")

    $lastFailure = Join-Path $script:BuildRootPath 'last-failure'
    if (Test-Path -LiteralPath $lastFailure) {
        Remove-PrivateDirectory `
            -Path $lastFailure -AllowedRoot $script:BuildRootPath -Label 'Previous builder failure'
    }
    [System.IO.Directory]::Move($Staging, $lastFailure)
}

function Remove-StaleStaging {
    foreach ($directory in @(Get-ChildItem -LiteralPath $script:ByShaRoot -Directory -Filter '.staging-*')) {
        Remove-PrivateDirectory `
            -Path $directory.FullName -AllowedRoot $script:ByShaRoot -Label 'Stale builder staging'
    }
}

function Build-OneSha {
    param([Parameter(Mandatory = $true)][string]$Sha)

    if ($Sha -cnotmatch '^[0-9a-f]{40}$') { throw "Expected a full Git SHA, got '$Sha'." }
    $finalDirectory = Join-Path $script:ByShaRoot $Sha
    if (Test-Path -LiteralPath $finalDirectory) {
        if (-not (Test-CompleteArtifact -Directory $finalDirectory -Sha $Sha)) {
            throw "Existing by-SHA directory is incomplete and will not be overwritten: $finalDirectory"
        }
        Set-CurrentPointer -Sha $Sha
        Write-Output "CURRENT RECOVERED: $Sha"
        return
    }

    $token = [guid]::NewGuid().ToString('N')
    $workspace = Join-Path $script:WorktreeRoot "$Sha-$token"
    $staging = Join-Path $script:ByShaRoot ".staging-$Sha-$token"
    New-Item -ItemType Directory -Path $staging | Out-Null
    $worktreeAdded = $false
    try {
        Invoke-Git -Arguments @('worktree', 'add', '--detach', $workspace, $Sha) | Out-Null
        $worktreeAdded = $true
        Invoke-Native -FilePath 'git' -Arguments @(
            '-C', $workspace,
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'fetch', 'origin', $Sha
        ) | Out-Null
        Invoke-LfsCheckout -Workspace $workspace
        Invoke-Native -FilePath 'git' -Arguments @(
            '-C', $workspace,
            '-c', 'lfs.fetchinclude=', '-c', 'lfs.fetchexclude=',
            'lfs', 'fsck', $Sha
        ) | Out-Null

        $lfsPaths = (Invoke-Native -FilePath 'git' -Arguments @(
            '-C', $workspace, 'lfs', 'ls-files', '--name-only'
        )) -split "`r?`n"
        foreach ($relativePath in @($lfsPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $assetPath = Join-Path $workspace $relativePath
            if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
                throw "LFS working-tree file is missing: $relativePath"
            }
            $firstLine = Get-Content -LiteralPath $assetPath -TotalCount 1 -ErrorAction Stop
            if ([string]$firstLine -ceq 'version https://git-lfs.github.com/spec/v1') {
                throw "LFS pointer was not hydrated before export: $relativePath"
            }
        }

        $actualSha = (Invoke-Native -FilePath 'git' -Arguments @(
            '-C', $workspace, 'rev-parse', 'HEAD'
        )).Trim()
        $trackedStatus = Invoke-Native -FilePath 'git' -Arguments @(
            '-C', $workspace, 'status', '--porcelain=v1', '--untracked-files=no'
        )
        if ($actualSha -cne $Sha -or -not [string]::IsNullOrWhiteSpace($trackedStatus)) {
            throw "Detached builder worktree is not exact clean SHA ${Sha}: HEAD=$actualSha status='$trackedStatus'."
        }

        $exe = Join-Path $staging 'OstatniPomost.exe'
        $export = Invoke-CapturedProcess -FilePath $script:Godot -Arguments @(
            '--headless', '--path', $workspace, '--export-release', $ExportPreset, $exe
        ) -WorkingDirectory $workspace -TimeoutSeconds $ExportTimeoutSeconds
        [System.IO.File]::WriteAllText(
            (Join-Path $staging 'export.log'),
            $export.Output + "`n",
            [System.Text.UTF8Encoding]::new($false)
        )
        if ($export.ExitCode -ne 0 -or $export.Output -match '(?im)^\s*(?:ERROR|SCRIPT ERROR):') {
            throw "Godot export failed for $Sha."
        }

        $pck = Join-Path $staging 'OstatniPomost.pck'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
            -not (Test-Path -LiteralPath $pck -PathType Leaf) -or
            (Get-Item -LiteralPath $exe).Length -le 0 -or
            (Get-Item -LiteralPath $pck).Length -le 0) {
            throw "Godot export did not create non-empty EXE and PCK for $Sha."
        }

        $smokeRoot = Join-Path $workspace '.builder-smoke'
        $smokeHome = Join-Path $smokeRoot 'user'
        $smokeTemp = Join-Path $smokeRoot 'temp'
        New-Item -ItemType Directory -Path $smokeHome, $smokeTemp | Out-Null
        $smoke = Invoke-CapturedProcess -FilePath $exe -Arguments @(
            '--headless', '--quit-after', [string]$SmokeFrames,
            '--log-file', (Join-Path $staging 'smoke-godot.log')
        ) -WorkingDirectory $staging -TimeoutSeconds $SmokeTimeoutSeconds -Environment @{
            APPDATA = $smokeHome
            LOCALAPPDATA = $smokeHome
            TEMP = $smokeTemp
            TMP = $smokeTemp
            GODOT_SILENCE_ROOT_WARNING = '1'
        }
        [System.IO.File]::WriteAllText(
            (Join-Path $staging 'smoke.log'),
            $smoke.Output + "`n",
            [System.Text.UTF8Encoding]::new($false)
        )
        $godotSmokeLog = Join-Path $staging 'smoke-godot.log'
        $combinedSmoke = $smoke.Output
        if (Test-Path -LiteralPath $godotSmokeLog -PathType Leaf) {
            $combinedSmoke += "`n" + (Get-Content -LiteralPath $godotSmokeLog -Raw)
        }
        if ($smoke.ExitCode -ne 0 -or $combinedSmoke -match '(?im)^\s*(?:ERROR|SCRIPT ERROR):') {
            throw "Playable smoke failed for $Sha."
        }

        $metadata = [ordered]@{
            schema = 'potop-playable-build-v1'
            status = 'PASS'
            sha = $Sha
            built_at_utc = [DateTime]::UtcNow.ToString('o')
            preset = $ExportPreset
            executable = 'OstatniPomost.exe'
        } | ConvertTo-Json
        Write-DurableText -Path (Join-Path $staging 'build.json') -Text ($metadata + "`n")
        Write-DurableText -Path (Join-Path $staging 'PASS') -Text "$Sha`n"

        [System.IO.Directory]::Move($staging, $finalDirectory)
        Set-CurrentPointer -Sha $Sha
        Write-Output 'PLAYABLE BUILD PASS'
        Write-Output "  SHA:      $Sha"
        Write-Output "  artifact: $finalDirectory"
        Write-Output "  current:  $(Join-Path $script:BuildRootPath 'current')"
    }
    catch {
        $failure = $_
        try { Publish-LastFailure -Staging $staging -Sha $Sha -Message $failure.Exception.Message }
        catch { Write-Warning "Could not preserve bounded last-failure logs: $_" }
        throw $failure
    }
    finally {
        if ($worktreeAdded) {
            try { Remove-BuilderWorktree -Workspace $workspace -Sha $Sha }
            catch { Write-Warning $_ }
        }
        if (Test-Path -LiteralPath $staging -PathType Container) {
            try {
                Remove-PrivateDirectory `
                    -Path $staging -AllowedRoot $script:ByShaRoot -Label 'Builder staging cleanup'
            }
            catch { Write-Warning $_ }
        }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

$script:RepoRoot = [System.IO.Path]::GetFullPath(
    (Invoke-Native -FilePath 'git' -Arguments @('-C', $Repository, 'rev-parse', '--show-toplevel'))
).TrimEnd('\', '/')
$script:BuildRootPath = if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    Join-Path $script:RepoRoot 'builds'
}
else { [System.IO.Path]::GetFullPath($BuildRoot) }
$script:ByShaRoot = Join-Path $script:BuildRootPath 'by-sha'
$script:WorktreeRoot = Join-Path $script:BuildRootPath '.worktrees'
$script:Godot = Resolve-GodotConsole

$mutexBytes = [System.Text.Encoding]::UTF8.GetBytes($script:BuildRootPath.ToLowerInvariant())
$mutexHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($mutexBytes))
$mutex = [System.Threading.Mutex]::new($false, "Local\Potop.PlayableBuilder.$mutexHash")
$acquired = $false
try {
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw 'Another local playable builder already owns this build root.' }

    New-Item -ItemType Directory -Path $script:ByShaRoot, $script:WorktreeRoot -Force | Out-Null
    Remove-StaleStaging
    $lastFailedSha = ''
    do {
        $sha = ''
        try {
            $sha = Sync-Main
            if ($Watch -and $sha -ceq $lastFailedSha) {
                Write-Output "PLAYABLE BUILD WAITING: unchanged failed SHA $sha"
            }
            else {
                Build-OneSha -Sha $sha
                $lastFailedSha = ''
            }
        }
        catch {
            if (-not $Watch) { throw }
            if ($sha -cmatch '^[0-9a-f]{40}$') { $lastFailedSha = $sha }
            Write-Warning "Builder attempt failed; current is unchanged. $_"
        }

        if ($Watch) { Start-Sleep -Seconds $PollSeconds }
    } while ($Watch)
}
finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
