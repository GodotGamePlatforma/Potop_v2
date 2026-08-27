#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('RunOnce', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'RunOnce',

    [string]$SourceRepository = (Split-Path -Parent $PSScriptRoot),
    [string]$PlayPath = '',
    [string]$GodotConsolePath = '',
    [string]$TaskName = 'Potop v2 - sync and build play-main'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = '',
        [switch]$AllowFailure
    )
    $previous = Get-Location
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location -LiteralPath $WorkingDirectory
        }
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location -LiteralPath $previous.Path
        $ErrorActionPreference = $oldPreference
    }
    $text = ($output | Out-String).Trim()
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$FilePath failed ($exitCode): $text"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $text }
}

function Resolve-GodotConsole {
    param([string]$Requested)
    $candidates = @(
        $Requested,
        $env:GODOT_CONSOLE_PATH,
        $env:GODOT4_CONSOLE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    foreach ($name in @(
        'Godot_v4.7.1-stable_win64_console.exe',
        'godot4_console.exe',
        'godot_console.exe',
        'godot.exe'
    )) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Godot 4.7.1 console executable was not found.'
}

function Write-Status {
    param([hashtable]$Value, [string]$Path)
    $Value['updated_at'] = [DateTime]::UtcNow.ToString('o')
    $json = $Value | ConvertTo-Json -Depth 8
    $temporary = "$Path.$PID.tmp"
    [IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-TextSha256 {
    param([string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

$sourceRoot = [System.IO.Path]::GetFullPath($SourceRepository).TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($PlayPath)) {
    $PlayPath = Join-Path (Split-Path -Parent $sourceRoot) 'play-main'
}
$playRoot = [System.IO.Path]::GetFullPath($PlayPath).TrimEnd('\', '/')
$stateRoot = Join-Path $env:LOCALAPPDATA 'OstatniPomost\play-main'
[IO.Directory]::CreateDirectory($stateRoot) | Out-Null
$statusPath = Join-Path $stateRoot 'status.json'
$lockPath = Join-Path $stateRoot 'sync.lock'
$installedScriptPath = Join-Path $stateRoot 'sync_play_main.ps1'
$managedClonePath = Join-Path $stateRoot 'managed-clone.json'

if ($Mode -eq 'Status') {
    if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
        Get-Content -LiteralPath $statusPath -Raw
    }
    else {
        Write-Output '{"result":"NEVER_RUN"}'
    }
    return
}

if ($Mode -eq 'Uninstall') {
    if ($PSCmdlet.ShouldProcess($TaskName, 'unregister scheduled play-main synchronization')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output "TASK_UNINSTALLED name=$TaskName"
    }
    return
}

if ($Mode -eq 'Install') {
    & $PSCommandPath -Mode RunOnce -SourceRepository $sourceRoot `
        -PlayPath $playRoot -GodotConsolePath $GodotConsolePath
    $playScript = Join-Path $playRoot 'tools\sync_play_main.ps1'
    if (-not (Test-Path -LiteralPath $playScript -PathType Leaf)) {
        throw "play-main does not contain the sync script: $playScript"
    }
    Copy-Item -LiteralPath $playScript -Destination $installedScriptPath -Force
    $pwsh = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $installedScriptPath + '"'), '-Mode', 'RunOnce',
        '-SourceRepository', ('"' + $playRoot + '"'),
        '-PlayPath', ('"' + $playRoot + '"')
    )
    if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
        $arguments += @('-GodotConsolePath', ('"' + $GodotConsolePath + '"'))
    }
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument ($arguments -join ' ')
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive -RunLevel Limited
    if ($PSCmdlet.ShouldProcess($TaskName, 'register one-minute play-main synchronization')) {
        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        Write-Output "TASK_INSTALLED name=$TaskName interval=PT1M play=$playRoot"
    }
    return
}

$lockStream = $null
$targetSha = ''
$currentMainSha = ''
$failureStage = 'startup'
$previousStatus = $null
$lastBuiltSha = ''
if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
    try { $previousStatus = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json }
    catch { $previousStatus = $null }
}
if ($null -ne $previousStatus) {
    if ($null -ne $previousStatus.PSObject.Properties['built_sha']) {
        $lastBuiltSha = [string]$previousStatus.built_sha
    }
    elseif ($null -ne $previousStatus.PSObject.Properties['last_built_sha']) {
        $lastBuiltSha = [string]$previousStatus.last_built_sha
    }
}
try {
    try {
        $lockStream = [IO.File]::Open(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        Write-Output 'SYNC_BUSY another play-main update/build is already running'
        return
    }

    $failureStage = 'resolve-origin'
    $originUrl = (Invoke-Native -FilePath git -Arguments @(
        '-C', $sourceRoot, 'remote', 'get-url', 'origin'
    )).Output
    $originUrlHash = Get-TextSha256 -Value $originUrl
    $managedClone = $null
    if (Test-Path -LiteralPath $managedClonePath -PathType Leaf) {
        $managedClone = Get-Content -LiteralPath $managedClonePath -Raw | ConvertFrom-Json
        if ([int]$managedClone.schema_version -ne 1 -or
            [string]$managedClone.play_path -cne $playRoot -or
            [string]$managedClone.origin_url_sha256 -cne $originUrlHash -or
            [string]$managedClone.state -notin @('CREATING', 'MANAGED')) {
            throw 'Managed play-main clone marker does not match this invocation.'
        }
    }
    if (-not (Test-Path -LiteralPath $playRoot -PathType Container)) {
        if (-not $PSCmdlet.ShouldProcess($playRoot, 'create standalone managed clone of origin/main')) {
            Write-Output "PLAN clone=$playRoot origin=$originUrl"
            return
        }
        Write-Status -Path $managedClonePath -Value @{
            schema_version = 1
            state = 'CREATING'
            play_path = $playRoot
            origin_url_sha256 = $originUrlHash
        }
        Invoke-Native -FilePath git -Arguments @(
            'clone', '--no-tags', '--single-branch', '--branch', 'main',
            $originUrl, $playRoot
        ) | Out-Null
    }
    elseif ($null -eq $managedClone) {
        throw 'Existing play path has no managed-clone marker; refusing to modify it.'
    }

    $failureStage = 'validate-managed-clone'
    $playTop = (Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'rev-parse', '--show-toplevel'
    )).Output
    if (-not [string]::Equals(
        [IO.Path]::GetFullPath($playTop).TrimEnd('\', '/'),
        $playRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Play path is not the exact standalone clone root: $playRoot"
    }
    $actualOrigin = (Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'remote', 'get-url', 'origin'
    )).Output
    if ((Get-TextSha256 -Value $actualOrigin) -cne $originUrlHash) {
        throw 'play-main origin differs from its managed-clone marker.'
    }
    $branch = (Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'branch', '--show-current'
    )).Output
    if ($branch -cne 'main') {
        throw "Managed play clone must stay on branch main, not $branch."
    }
    if (-not [string]::IsNullOrWhiteSpace((Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'status', '--porcelain=v1', '--untracked-files=all'
    )).Output)) {
        throw 'play-main has source changes; refusing to overwrite them.'
    }
    Write-Status -Path $managedClonePath -Value @{
        schema_version = 1
        state = 'MANAGED'
        play_path = $playRoot
        origin_url_sha256 = $originUrlHash
    }

    $failureStage = 'fetch-main'
    Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'fetch', '--no-tags', 'origin',
        '+refs/heads/main:refs/remotes/origin/main'
    ) | Out-Null
    $targetSha = (Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'rev-parse', '--verify',
        'refs/remotes/origin/main^{commit}'
    )).Output
    $previousSha = (Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'rev-parse', 'HEAD^{commit}'
    )).Output
    $currentMainSha = $previousSha
    if ($previousSha -ceq $targetSha -and $null -ne $previousStatus -and
        [string]$previousStatus.result -ceq 'PASS' -and
        [string]$previousStatus.built_sha -ceq $targetSha) {
        Write-Output "SYNC_UNCHANGED sha=$targetSha play=$playRoot"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($playRoot, "fast-forward main and build exact $targetSha")) {
        Write-Output "PLAN play=$playRoot target=$targetSha"
        return
    }
    if ($previousSha -cne $targetSha) {
        $failureStage = 'fast-forward-main'
        Invoke-Native -FilePath git -Arguments @(
            '-C', $playRoot, 'merge', '--ff-only',
            'refs/remotes/origin/main'
        ) | Out-Null
    }
    $updatedSha = (Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'rev-parse', 'HEAD^{commit}'
    )).Output
    if ($updatedSha -cne $targetSha) {
        throw "play-main did not fast-forward to exact origin/main: $updatedSha"
    }
    $currentMainSha = $updatedSha
    $failureStage = 'lfs'
    Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'lfs', 'pull', 'origin', 'main'
    ) | Out-Null
    $failureStage = 'map-check'
    $mapRoot = Join-Path $playRoot 'underwater_map_workbench'
    $mapResult = Invoke-Native -FilePath python -Arguments @(
        '-B', 'tools/build_underwater_map.py', '--check'
    ) -WorkingDirectory $mapRoot
    $failureStage = 'godot-import'
    $godot = Resolve-GodotConsole -Requested $GodotConsolePath
    $godotResult = Invoke-Native -FilePath $godot -Arguments @(
        '--headless', '--editor', '--path', $playRoot,
        '--audio-driver', 'Dummy', '--quit-after', '1'
    ) -AllowFailure
    if ($godotResult.ExitCode -ne 0 -or
        $godotResult.Output -match '(?im)^\s*(?:SCRIPT ERROR|ERROR)(?:\s|:)') {
        throw "Godot import/build failed: $($godotResult.Output)"
    }
    if (-not [string]::IsNullOrWhiteSpace((Invoke-Native -FilePath git -Arguments @(
        '-C', $playRoot, 'status', '--porcelain=v1', '--untracked-files=all'
    )).Output)) {
        throw 'Build changed tracked or nonignored source files in play-main.'
    }
    Write-Status -Path $statusPath -Value @{
        result = 'PASS'
        built_sha = $targetSha
        previous_sha = $previousSha
        play_path = $playRoot
        godot = $godot
        map_check = $mapResult.Output
    }
    $newPlayScript = Join-Path $playRoot 'tools\sync_play_main.ps1'
    if (Test-Path -LiteralPath $newPlayScript -PathType Leaf) {
        Copy-Item -LiteralPath $newPlayScript `
            -Destination $installedScriptPath -Force
    }
    Write-Output "SYNC_BUILT sha=$targetSha play=$playRoot status=$statusPath"
}
catch {
    $failure = $_.Exception.Message
    Write-Status -Path $statusPath -Value @{
        result = 'FAIL'
        stage = $failureStage
        target_sha = $targetSha
        current_main_sha = $currentMainSha
        last_built_sha = $lastBuiltSha
        play_path = $playRoot
        error = $failure
    }
    throw $failure
}
finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}
