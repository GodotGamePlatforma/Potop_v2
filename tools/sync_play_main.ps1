#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('RunOnce', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'RunOnce',

    [string]$SourceRepository = (Split-Path -Parent $PSScriptRoot),
    [string]$OriginUrl = '',
    [string]$PlayPath = '',
    [string]$LatestPath = '',
    [string]$GodotConsolePath = '',
    [string]$ExportPreset = 'Windows Desktop',
    [string]$TaskName = 'Potop v2 - sync and build play-main',
    [switch]$RetryFailed
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

function Get-UtcText {
    return [DateTime]::UtcNow.ToString(
        'yyyy-MM-ddTHH:mm:ss.fffffffZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Write-Utf8Atomic {
    param([string]$Path, [string]$Text)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = Join-Path $parent (
        '.{0}.{1}.{2}.tmp' -f [IO.Path]::GetFileName($fullPath), $PID,
        [Guid]::NewGuid().ToString('N')
    )
    $backup = "$fullPath.$PID.$([Guid]::NewGuid().ToString('N')).bak"
    try {
        [IO.File]::WriteAllText(
            $temporary,
            $Text,
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            [IO.File]::Replace($temporary, $fullPath, $backup, $true)
        }
        else {
            [IO.File]::Move($temporary, $fullPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [IO.File]::Delete($temporary)
        }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            [IO.File]::Delete($backup)
        }
    }
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value)

    if ($Value -is [Collections.IDictionary]) {
        $Value['updated_at'] = Get-UtcText
    }
    elseif ($null -ne $Value.PSObject.Properties['updated_at']) {
        $Value.updated_at = Get-UtcText
    }
    $json = $Value | ConvertTo-Json -Depth 16
    Write-Utf8Atomic -Path $Path -Text ($json + "`n")
}

function Read-JsonObject {
    param([string]$Path, [string]$Label)

    try {
        $value = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "$Label is unreadable: $Path : $($_.Exception.Message)"
    }
    if ($null -eq $value -or $value -is [Array]) {
        throw "$Label must contain one JSON object: $Path"
    }
    return $value
}

function Get-TextSha256 {
    param([string]$Value)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace(
            '-', ''
        ).ToLowerInvariant()
    }
    finally {
        $hash.Dispose()
    }
}

function Get-FileSha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-ScriptAtomically {
    param([string]$Source, [string]$Destination)

    $sourcePath = [IO.Path]::GetFullPath($Source)
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    if ([string]::Equals(
        $sourcePath,
        $destinationPath,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        return
    }
    $bytes = [IO.File]::ReadAllBytes($sourcePath)
    $temporary = "$destinationPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    $backup = "$destinationPath.$PID.$([Guid]::NewGuid().ToString('N')).bak"
    try {
        [IO.File]::WriteAllBytes($temporary, $bytes)
        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            [IO.File]::Replace($temporary, $destinationPath, $backup, $true)
        }
        else {
            [IO.File]::Move($temporary, $destinationPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [IO.File]::Delete($temporary)
        }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            [IO.File]::Delete($backup)
        }
    }
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
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    foreach ($name in @(
        'Godot_v4.7.1-stable_win64_console.exe',
        'godot4_console.exe',
        'godot_console.exe',
        'godot.exe'
    )) {
        $command = Get-Command $name -CommandType Application `
            -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Godot 4.7.1 console executable was not found.'
}

function Assert-NoGodotErrors {
    param([string]$Output, [string]$Label)

    if ($Output -match '(?im)^\s*(?:SCRIPT ERROR|ERROR)(?:\s|:)') {
        throw "$Label emitted ERROR or SCRIPT ERROR: $Output"
    }
}

function Get-GitText {
    param(
        [string]$Repository,
        [string[]]$Arguments
    )

    $result = Invoke-Native -FilePath git -Arguments (
        @('-C', $Repository) + @($Arguments)
    )
    return [string]$result.Output
}

function Get-GitStatus {
    param([string]$Repository)

    return Get-GitText -Repository $Repository -Arguments @(
        'status', '--porcelain=v1', '--untracked-files=all'
    )
}

function Assert-FullSha {
    param([string]$Value, [string]$Label)

    if ($Value -cnotmatch '^[0-9a-f]{40}$') {
        throw "$Label is not one exact SHA-1 commit: $Value"
    }
    return $Value
}

function Assert-PathBelow {
    param([string]$Path, [string]$Root, [string]$Label)

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not $fullPath.StartsWith(
        $fullRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "$Label escapes its managed root: $fullPath"
    }
    return $fullPath
}

function Resolve-OriginUrl {
    param(
        [string]$Requested,
        [string]$BootstrapRepository,
        [string]$MirrorPath
    )

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return $Requested.Trim()
    }
    if (Test-Path -LiteralPath $MirrorPath -PathType Container) {
        return Get-GitText -Repository $MirrorPath `
            -Arguments @('remote', 'get-url', 'origin')
    }
    if (-not (Test-Path -LiteralPath $BootstrapRepository -PathType Container)) {
        throw "Bootstrap repository does not exist and OriginUrl was not supplied: $BootstrapRepository"
    }
    return Get-GitText -Repository $BootstrapRepository `
        -Arguments @('remote', 'get-url', 'origin')
}

function Test-ExportPresetAvailable {
    param([string]$Path, [string]$PresetName)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    $sections = [Text.RegularExpressions.Regex]::Matches(
        $text,
        '(?ms)^\[preset\.\d+\]\s*(?<body>.*?)(?=^\[preset\.\d+\]|\z)'
    )
    foreach ($section in $sections) {
        $body = [string]$section.Groups['body'].Value
        $name = [Text.RegularExpressions.Regex]::Match(
            $body,
            '(?m)^name="(?<value>[^"]+)"\s*$'
        )
        $platform = [Text.RegularExpressions.Regex]::Match(
            $body,
            '(?m)^platform="(?<value>[^"]+)"\s*$'
        )
        if ($name.Success -and $platform.Success -and
            [string]$name.Groups['value'].Value -ceq $PresetName -and
            [string]$platform.Groups['value'].Value -ceq 'Windows Desktop') {
            return $true
        }
    }
    return $false
}

function Test-ExportSmokeContractAvailable {
    param([string]$Repository)

    # The exported executable may only become playable when production code,
    # not the builder or its test double, owns both smoke proofs.
    $contractPath = Join-Path $Repository 'scripts\core\PlayMainExportSmoke.gd'
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
        return $false
    }
    $text = [IO.File]::ReadAllText($contractPath)
    return (
        $text.Contains('PLAY_MAIN_SMOKE_CREATE=PASS') -and
        $text.Contains('PLAY_MAIN_SMOKE_MAP_LOAD=PASS')
    )
}

function New-Queue {
    param([string]$OriginDigest)

    return [pscustomobject][ordered]@{
        schema_version = 1
        origin_url_sha256 = $OriginDigest
        observed_tip = ''
        entries = @()
        updated_at = Get-UtcText
    }
}

function Assert-Queue {
    param([object]$Queue, [string]$OriginDigest)

    if ([int]$Queue.schema_version -ne 1 -or
        [string]$Queue.origin_url_sha256 -cne $OriginDigest) {
        throw 'Persistent main queue identity is invalid.'
    }
    $observed = [string]$Queue.observed_tip
    if (-not [string]::IsNullOrWhiteSpace($observed)) {
        Assert-FullSha $observed 'Queue observed_tip' | Out-Null
    }
    $allowedStates = @(
        'PENDING', 'RUNNING', 'PROMOTING', 'FAIL',
        'EXPORT_BOOTSTRAP_REQUIRED', 'PASS'
    )
    $seen = @{}
    $expectedSequence = 1
    foreach ($entry in @($Queue.entries)) {
        $sha = Assert-FullSha ([string]$entry.sha) 'Queued SHA'
        if ($seen.ContainsKey($sha)) {
            throw "Persistent main queue contains duplicate SHA: $sha"
        }
        $seen[$sha] = $true
        if ([int]$entry.sequence -ne $expectedSequence) {
            throw 'Persistent main queue sequence is not contiguous.'
        }
        if ([string]$entry.state -notin $allowedStates) {
            throw "Persistent main queue has unknown state: $($entry.state)"
        }
        if ($null -eq $entry.PSObject.Properties['attempts']) {
            throw 'Persistent main queue entry has no attempts collection.'
        }
        $attemptIds = @{}
        foreach ($attempt in @($entry.attempts)) {
            $attemptId = [string]$attempt.attempt_id
            if ([string]::IsNullOrWhiteSpace($attemptId) -or
                $attemptIds.ContainsKey($attemptId)) {
                throw "Persistent main queue has an invalid attempt ID for $sha."
            }
            $attemptIds[$attemptId] = $true
        }
        $expectedSequence += 1
    }
    $Queue.entries = @($Queue.entries)
}

function Get-NewMainCommits {
    param([string]$MirrorPath, [string]$PreviousTip, [string]$TargetTip)

    if ([string]::IsNullOrWhiteSpace($PreviousTip)) {
        return @($TargetTip)
    }
    if ($PreviousTip -ceq $TargetTip) { return @() }
    $ancestry = Invoke-Native -FilePath git -Arguments @(
        '-C', $MirrorPath, 'merge-base', '--is-ancestor', $PreviousTip, $TargetTip
    ) -AllowFailure
    if ($ancestry.ExitCode -ne 0) {
        throw "origin/main is not a fast-forward of queued tip $PreviousTip."
    }
    $text = Get-GitText -Repository $MirrorPath -Arguments @(
        'rev-list', '--reverse', '--first-parent', "$PreviousTip..$TargetTip"
    )
    $commits = @($text -split "`r?`n" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    if ($commits.Count -eq 0 -or $commits[-1] -cne $TargetTip) {
        throw 'Cannot enumerate every new first-parent main SHA.'
    }
    foreach ($commit in $commits) {
        Assert-FullSha $commit 'Enumerated main SHA' | Out-Null
    }
    return $commits
}

function New-QueueEntry {
    param([int]$Sequence, [string]$Sha)

    return [pscustomobject][ordered]@{
        sequence = $Sequence
        sha = $Sha
        state = 'PENDING'
        attempts = @()
        active_attempt_id = ''
        active_attempt_path = ''
        last_result = ''
        last_error = ''
        enqueued_at = Get-UtcText
        updated_at = Get-UtcText
    }
}

function Set-EntryAttemptState {
    param(
        [object]$Entry,
        [string]$AttemptId,
        [string]$State,
        [string]$ReceiptPath,
        [string]$ErrorText = ''
    )

    $matches = @(@($Entry.attempts) | Where-Object {
        [string]$_.attempt_id -ceq $AttemptId
    })
    if ($matches.Count -ne 1) {
        throw "Queue attempt identity is not unique: $AttemptId"
    }
    $matches[0].state = $State
    $matches[0].receipt_path = $ReceiptPath
    $matches[0].error = $ErrorText
    $matches[0].terminal_at = Get-UtcText
}

function Test-ShouldPromoteCurrent {
    param(
        [string]$MirrorPath,
        [string]$CurrentSha,
        [string]$TargetSha
    )

    if ([string]::IsNullOrWhiteSpace($CurrentSha)) { return $true }
    if ($CurrentSha -ceq $TargetSha) { return $false }
    $currentBeforeTarget = Invoke-Native -FilePath git -Arguments @(
        '-C', $MirrorPath, 'merge-base', '--is-ancestor', $CurrentSha, $TargetSha
    ) -AllowFailure
    if ($currentBeforeTarget.ExitCode -eq 0) { return $true }
    $targetBeforeCurrent = Invoke-Native -FilePath git -Arguments @(
        '-C', $MirrorPath, 'merge-base', '--is-ancestor', $TargetSha, $CurrentSha
    ) -AllowFailure
    if ($targetBeforeCurrent.ExitCode -eq 0) { return $false }
    throw "Playable current and candidate are not on one main lineage: current=$CurrentSha target=$TargetSha"
}

function Write-CurrentPointer {
    param(
        [string]$Path,
        [string]$Sha,
        [string]$BuildPath,
        [string]$AttemptId,
        [string]$ReceiptSha256
    )

    Write-JsonAtomic -Path $Path -Value ([ordered]@{
        schema_version = 1
        sha = $Sha
        build_path = $BuildPath
        attempt_id = $AttemptId
        attempt_receipt_sha256 = $ReceiptSha256
        promoted_at = Get-UtcText
        updated_at = Get-UtcText
    })
}

function Get-CurrentPointer {
    param([string]$Path, [string]$BuildsRoot)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $current = Read-JsonObject -Path $Path -Label 'Current build pointer'
    $sha = Assert-FullSha ([string]$current.sha) 'Current build SHA'
    if ([int]$current.schema_version -ne 1) {
        throw 'Current build pointer schema is invalid.'
    }
    $expected = [IO.Path]::GetFullPath((Join-Path $BuildsRoot $sha))
    $actual = [IO.Path]::GetFullPath([string]$current.build_path)
    if (-not [string]::Equals(
        $expected,
        $actual,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Current build pointer does not name its immutable SHA directory.'
    }
    $markerPath = Join-Path $actual 'build.json'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw 'Current build pointer targets a build without build.json.'
    }
    $marker = Read-JsonObject -Path $markerPath -Label 'Immutable build marker'
    if ([int]$marker.schema_version -ne 1 -or
        [string]$marker.result -cne 'PASS' -or
        [string]$marker.sha -cne $sha) {
        throw 'Current build pointer targets an invalid immutable build.'
    }
    return $current
}

function Write-RunStatus {
    param(
        [string]$Path,
        [string]$Result,
        [string]$Stage,
        [string]$TargetSha,
        [string]$CurrentSha,
        [string]$QueuePath,
        [string]$AttemptId = '',
        [string]$AttemptReceipt = '',
        [string]$BuildPath = '',
        [string]$ErrorText = ''
    )

    Write-JsonAtomic -Path $Path -Value ([ordered]@{
        schema_version = 1
        check_name = 'full-green'
        result = $Result
        stage = $Stage
        target_sha = $TargetSha
        current_sha = $CurrentSha
        queue_path = $QueuePath
        attempt_id = $AttemptId
        attempt_receipt = $AttemptReceipt
        build_path = $BuildPath
        error = $ErrorText
        updated_at = Get-UtcText
    })
}

function Write-Alert {
    param(
        [string]$Path,
        [bool]$Active,
        [string]$Result,
        [string]$Sha,
        [string]$Stage,
        [string]$ErrorText = ''
    )

    Write-JsonAtomic -Path $Path -Value ([ordered]@{
        schema_version = 1
        check_name = 'full-green'
        active = $Active
        result = $Result
        sha = $Sha
        stage = $Stage
        error = $ErrorText
        updated_at = Get-UtcText
    })
}

function Remove-CandidateWorktree {
    param([string]$MirrorPath, [string]$CandidateSource)

    if ([string]::IsNullOrWhiteSpace($CandidateSource)) { return }
    if (Test-Path -LiteralPath $CandidateSource -PathType Container) {
        if (-not [string]::IsNullOrWhiteSpace((Get-GitStatus $CandidateSource))) {
            throw "Candidate worktree is dirty and was preserved: $CandidateSource"
        }
        Invoke-Native -FilePath git -Arguments @(
            '-C', $MirrorPath, 'worktree', 'remove', $CandidateSource
        ) | Out-Null
    }
    else {
        Invoke-Native -FilePath git -Arguments @(
            '-C', $MirrorPath, 'worktree', 'prune', '--expire=now'
        ) | Out-Null
    }
}

function Recover-RunningEntry {
    param(
        [object]$Entry,
        [string]$MirrorPath,
        [string]$AttemptsRoot
    )

    $attemptId = [string]$Entry.active_attempt_id
    $attemptPath = [string]$Entry.active_attempt_path
    if ([string]::IsNullOrWhiteSpace($attemptId) -or
        [string]::IsNullOrWhiteSpace($attemptPath)) {
        throw "RUNNING queue entry has no exact active attempt: $($Entry.sha)"
    }
    $safeAttempt = Assert-PathBelow $attemptPath $AttemptsRoot 'Recovery attempt'
    $candidateSource = Join-Path $safeAttempt 'source'
    Remove-CandidateWorktree -MirrorPath $MirrorPath `
        -CandidateSource $candidateSource
    $receiptPath = Join-Path $safeAttempt 'attempt.json'
    $recoveryError = 'Interrupted process recovered before a new unique attempt.'
    if (Test-Path -LiteralPath $safeAttempt -PathType Container) {
        Write-JsonAtomic -Path $receiptPath -Value ([ordered]@{
            schema_version = 1
            result = 'ABORTED_RECOVERY'
            sha = [string]$Entry.sha
            attempt_id = $attemptId
            error = $recoveryError
            terminal_at = Get-UtcText
            updated_at = Get-UtcText
        })
    }
    Set-EntryAttemptState -Entry $Entry -AttemptId $attemptId `
        -State 'ABORTED_RECOVERY' -ReceiptPath $receiptPath `
        -ErrorText $recoveryError
    $Entry.state = 'PENDING'
    $Entry.active_attempt_id = ''
    $Entry.active_attempt_path = ''
    $Entry.last_result = 'RECOVERED'
    $Entry.last_error = $recoveryError
    $Entry.updated_at = Get-UtcText
}

$sourceRoot = [IO.Path]::GetFullPath($SourceRepository).TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($PlayPath)) {
    $PlayPath = Join-Path (Split-Path -Parent $sourceRoot) 'play-main'
}
$playRoot = [IO.Path]::GetFullPath($PlayPath).TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($LatestPath)) {
    $LatestPath = "$playRoot-source"
}
$latestRoot = [IO.Path]::GetFullPath($LatestPath).TrimEnd('\', '/')
if ([string]::Equals(
    $latestRoot,
    $playRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Trusted source mirror and play output root must use different paths.'
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'OstatniPomost\play-main'
$statusPath = Join-Path $stateRoot 'status.json'
$alertPath = Join-Path $stateRoot 'alert.json'
$queuePath = Join-Path $stateRoot 'queue.json'
$lockPath = Join-Path $stateRoot 'sync.lock'
$installedScriptPath = Join-Path $stateRoot 'sync_play_main.ps1'
$sourceMarkerPath = Join-Path $stateRoot 'source-mirror.json'
$playMarkerPath = Join-Path $playRoot '.play-main-managed.json'
$buildsRoot = Join-Path $playRoot 'builds'
$attemptsRoot = Join-Path $playRoot 'attempts'
$currentPath = Join-Path $playRoot 'current.json'

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
    if ($PSCmdlet.ShouldProcess($TaskName, 'unregister scheduled play-main builder')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false `
            -ErrorAction SilentlyContinue
        Write-Output "TASK_UNINSTALLED name=$TaskName"
    }
    return
}

if ($WhatIfPreference) {
    Write-Output (
        "PLAN mode=$Mode source=$latestRoot play=$playRoot " +
        "queue=$queuePath current=$currentPath"
    )
    return
}

if ($Mode -eq 'Install') {
    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $resolvedOrigin = Resolve-OriginUrl -Requested $OriginUrl `
        -BootstrapRepository $sourceRoot -MirrorPath $latestRoot
    Copy-ScriptAtomically -Source $PSCommandPath -Destination $installedScriptPath
    $pwsh = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
    $quoted = {
        param([string]$Value)
        return '"' + $Value.Replace('"', '\"') + '"'
    }
    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', (& $quoted $installedScriptPath), '-Mode', 'RunOnce',
        '-SourceRepository', (& $quoted $latestRoot),
        '-OriginUrl', (& $quoted $resolvedOrigin),
        '-LatestPath', (& $quoted $latestRoot),
        '-PlayPath', (& $quoted $playRoot),
        '-ExportPreset', (& $quoted $ExportPreset)
    )
    if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
        $arguments += @('-GodotConsolePath', (& $quoted $GodotConsolePath))
    }
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument ($arguments -join ' ')
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 4)
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Write-Output "TASK_INSTALLED name=$TaskName interval=PT1M play=$playRoot"
    try {
        & $installedScriptPath -Mode RunOnce -SourceRepository $latestRoot `
            -OriginUrl $resolvedOrigin -LatestPath $latestRoot `
            -PlayPath $playRoot -GodotConsolePath $GodotConsolePath `
            -ExportPreset $ExportPreset -RetryFailed
    }
    catch {
        Write-Output (
            "INITIAL_BUILD_FAILED task remains installed error={0}" -f `
                $_.Exception.Message
        )
    }
    return
}

$lockStream = $null
$failureStage = 'startup'
$targetSha = ''
$currentSha = ''
$failureRecorded = $false
try {
    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    try {
        $lockStream = [IO.File]::Open(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        Write-Output 'SYNC_BUSY another play-main builder is already running'
        return
    }

    $failureStage = 'resolve-origin'
    $resolvedOrigin = Resolve-OriginUrl -Requested $OriginUrl `
        -BootstrapRepository $sourceRoot -MirrorPath $latestRoot
    $originDigest = Get-TextSha256 $resolvedOrigin

    $failureStage = 'source-mirror'
    $sourceMarker = $null
    if (Test-Path -LiteralPath $sourceMarkerPath -PathType Leaf) {
        $sourceMarker = Read-JsonObject -Path $sourceMarkerPath `
            -Label 'Trusted source mirror marker'
        if ([int]$sourceMarker.schema_version -ne 1 -or
            [string]$sourceMarker.path -cne $latestRoot -or
            [string]$sourceMarker.origin_url_sha256 -cne $originDigest -or
            [string]$sourceMarker.state -notin @('CREATING', 'MANAGED')) {
            throw 'Trusted source mirror marker does not match this invocation.'
        }
    }
    if (-not (Test-Path -LiteralPath $latestRoot -PathType Container)) {
        if ($null -ne $sourceMarker -and
            [string]$sourceMarker.state -cne 'CREATING') {
            throw 'Managed source mirror disappeared after successful creation.'
        }
        Write-JsonAtomic -Path $sourceMarkerPath -Value ([ordered]@{
            schema_version = 1
            state = 'CREATING'
            path = $latestRoot
            origin_url_sha256 = $originDigest
            updated_at = Get-UtcText
        })
        Invoke-Native -FilePath git -Arguments @(
            'clone', '--bare', '--no-tags', $resolvedOrigin, $latestRoot
        ) | Out-Null
    }
    elseif ($null -eq $sourceMarker) {
        throw 'Existing source mirror has no managed marker; refusing to use it.'
    }
    $isBare = Get-GitText -Repository $latestRoot `
        -Arguments @('rev-parse', '--is-bare-repository')
    if ($isBare -cne 'true') {
        throw 'Trusted source mirror must be a standalone bare clone.'
    }
    $mirrorCommon = [IO.Path]::GetFullPath((
        Get-GitText -Repository $latestRoot -Arguments @(
            'rev-parse', '--path-format=absolute', '--git-common-dir'
        )
    )).TrimEnd('\', '/')
    if (-not [string]::Equals(
        $mirrorCommon,
        $latestRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Trusted source mirror common-dir differs from its standalone root.'
    }
    $actualOrigin = Get-GitText -Repository $latestRoot `
        -Arguments @('remote', 'get-url', 'origin')
    if ((Get-TextSha256 $actualOrigin) -cne $originDigest) {
        throw 'Trusted source mirror origin differs from its managed marker.'
    }
    if (Test-Path -LiteralPath $sourceRoot -PathType Container) {
        $bootstrapCommonResult = Invoke-Native -FilePath git -Arguments @(
            '-C', $sourceRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir'
        ) -AllowFailure
        if ($bootstrapCommonResult.ExitCode -eq 0) {
            $bootstrapCommon = [IO.Path]::GetFullPath(
                $bootstrapCommonResult.Output
            ).TrimEnd('\', '/')
            if ([string]::Equals(
                $bootstrapCommon,
                $mirrorCommon,
                [StringComparison]::OrdinalIgnoreCase
            ) -and -not [string]::Equals(
                $sourceRoot,
                $latestRoot,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw 'Trusted source mirror shares a common-dir with authoring.'
            }
        }
    }
    Write-JsonAtomic -Path $sourceMarkerPath -Value ([ordered]@{
        schema_version = 1
        state = 'MANAGED'
        path = $latestRoot
        origin_url_sha256 = $originDigest
        updated_at = Get-UtcText
    })

    $failureStage = 'play-root'
    if (-not (Test-Path -LiteralPath $playRoot -PathType Container)) {
        [IO.Directory]::CreateDirectory($playRoot) | Out-Null
        Write-JsonAtomic -Path $playMarkerPath -Value ([ordered]@{
            schema_version = 1
            play_path = $playRoot
            source_path = $latestRoot
            origin_url_sha256 = $originDigest
            updated_at = Get-UtcText
        })
    }
    elseif (-not (Test-Path -LiteralPath $playMarkerPath -PathType Leaf)) {
        throw 'Existing play output root has no managed marker; refusing to modify it.'
    }
    $playMarker = Read-JsonObject -Path $playMarkerPath `
        -Label 'Play output marker'
    if ([int]$playMarker.schema_version -ne 1 -or
        [string]$playMarker.play_path -cne $playRoot -or
        [string]$playMarker.source_path -cne $latestRoot -or
        [string]$playMarker.origin_url_sha256 -cne $originDigest) {
        throw 'Play output marker does not match this invocation.'
    }
    [IO.Directory]::CreateDirectory($buildsRoot) | Out-Null
    [IO.Directory]::CreateDirectory($attemptsRoot) | Out-Null

    $current = Get-CurrentPointer -Path $currentPath -BuildsRoot $buildsRoot
    if ($null -ne $current) { $currentSha = [string]$current.sha }

    $failureStage = 'fetch-main'
    Invoke-Native -FilePath git -Arguments @(
        '-C', $latestRoot, 'fetch', '--no-tags', 'origin',
        'refs/heads/main:refs/remotes/origin/main'
    ) | Out-Null
    $targetSha = Assert-FullSha (
        Get-GitText -Repository $latestRoot -Arguments @(
            'rev-parse', '--verify', 'refs/remotes/origin/main^{commit}'
        )
    ) 'Fetched origin/main'

    $failureStage = 'queue-load'
    if (Test-Path -LiteralPath $queuePath -PathType Leaf) {
        $queue = Read-JsonObject -Path $queuePath -Label 'Persistent main queue'
    }
    else {
        $queue = New-Queue -OriginDigest $originDigest
    }
    Assert-Queue -Queue $queue -OriginDigest $originDigest
    $previousTip = [string]$queue.observed_tip
    if ([string]::IsNullOrWhiteSpace($previousTip) -and
        -not [string]::IsNullOrWhiteSpace($currentSha)) {
        $previousTip = $currentSha
    }
    $newCommits = @(Get-NewMainCommits -MirrorPath $latestRoot `
        -PreviousTip $previousTip -TargetTip $targetSha)
    foreach ($sha in $newCommits) {
        $nextSequence = @($queue.entries).Count + 1
        $queue.entries = @($queue.entries) + @(
            (New-QueueEntry -Sequence $nextSequence -Sha $sha)
        )
    }
    $queue.observed_tip = $targetSha
    Write-JsonAtomic -Path $queuePath -Value $queue

    $running = @(@($queue.entries) | Where-Object {
        [string]$_.state -ceq 'RUNNING'
    })
    if ($running.Count -gt 1) {
        throw 'Persistent main queue contains more than one RUNNING SHA.'
    }
    if ($running.Count -eq 1) {
        $failureStage = 'recover-running'
        Recover-RunningEntry -Entry $running[0] -MirrorPath $latestRoot `
            -AttemptsRoot $attemptsRoot
        Write-JsonAtomic -Path $queuePath -Value $queue
        Write-Output "SYNC_RECOVERED sha=$($running[0].sha)"
    }

    $builtCount = 0
    $attemptedSequences = @{}
    $terminalFailures = New-Object System.Collections.ArrayList
    while ($true) {
        $entry = @($queue.entries | Where-Object {
            $state = [string]$_.state
            $sequenceKey = [string]$_.sequence
            -not $attemptedSequences.ContainsKey($sequenceKey) -and (
                $state -ceq 'PENDING' -or
                $state -ceq 'PROMOTING' -or
                ($RetryFailed -and
                    $state -in @('FAIL', 'EXPORT_BOOTSTRAP_REQUIRED'))
            )
        } | Sort-Object -Property sequence | Select-Object -First 1)
        if ($entry.Count -eq 0) { break }
        $entry = $entry[0]
        $attemptedSequences[[string]$entry.sequence] = $true
        $sha = [string]$entry.sha
        $buildPath = Join-Path $buildsRoot $sha

        if (Test-Path -LiteralPath $buildPath -PathType Container) {
            $failureStage = 'recover-promotion'
            try {
                $buildMarkerPath = Join-Path $buildPath 'build.json'
                $buildMarker = Read-JsonObject -Path $buildMarkerPath `
                    -Label 'Recovered immutable build marker'
                if ([int]$buildMarker.schema_version -ne 1 -or
                    [string]$buildMarker.result -cne 'PASS' -or
                    [string]$buildMarker.sha -cne $sha) {
                    throw "Existing immutable build is invalid: $buildPath"
                }
                $receiptPath = Join-Path $buildPath 'attempt.json'
                $attemptId = [string]$buildMarker.attempt_id
                $receipt = Read-JsonObject -Path $receiptPath `
                    -Label 'Recovered immutable attempt receipt'
                if ([string]$receipt.result -cne 'PASS' -or
                    [string]$receipt.sha -cne $sha -or
                    [string]$receipt.attempt_id -cne $attemptId) {
                    throw "Recovered immutable attempt receipt is invalid: $receiptPath"
                }
                Set-EntryAttemptState -Entry $entry -AttemptId $attemptId `
                    -State 'PROMOTING' -ReceiptPath $receiptPath
                $entry.state = 'PROMOTING'
                $entry.active_attempt_id = $attemptId
                $entry.active_attempt_path = $buildPath
                $entry.last_result = 'PROMOTING'
                $entry.last_error = ''
                $entry.updated_at = Get-UtcText
                Write-JsonAtomic -Path $queuePath -Value $queue

                if (Test-ShouldPromoteCurrent -MirrorPath $latestRoot `
                        -CurrentSha $currentSha -TargetSha $sha) {
                    Write-CurrentPointer -Path $currentPath -Sha $sha `
                        -BuildPath $buildPath -AttemptId $attemptId `
                        -ReceiptSha256 (Get-FileSha256 $receiptPath)
                    $currentSha = $sha
                }
                Set-EntryAttemptState -Entry $entry -AttemptId $attemptId `
                    -State 'PASS' -ReceiptPath $receiptPath
                $entry.state = 'PASS'
                $entry.active_attempt_id = ''
                $entry.active_attempt_path = ''
                $entry.last_result = 'PASS'
                $entry.last_error = ''
                $entry.updated_at = Get-UtcText
                Write-JsonAtomic -Path $queuePath -Value $queue
                Write-Output "SYNC_RECOVERED_PROMOTION sha=$sha build=$buildPath"
            }
            catch {
                $promotionFailure = $_.Exception.Message
                Write-RunStatus -Path $statusPath -Result 'PROMOTION_IN_DOUBT' `
                    -Stage $failureStage -TargetSha $sha -CurrentSha $currentSha `
                    -QueuePath $queuePath -ErrorText $promotionFailure
                Write-Alert -Path $alertPath -Active $true `
                    -Result 'PROMOTION_IN_DOUBT' -Sha $sha `
                    -Stage $failureStage -ErrorText $promotionFailure
                $failureRecorded = $true
                throw
            }
            continue
        }

        if ([string]$entry.state -ne 'PENDING' -and
            -not ($RetryFailed -and
                [string]$entry.state -in @('FAIL', 'EXPORT_BOOTSTRAP_REQUIRED'))) {
            throw "Cannot process queued SHA $sha from state $($entry.state)."
        }

        $attemptId = '{0}-{1}' -f (
            [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'),
            [Guid]::NewGuid().ToString('N')
        )
        $shaAttemptsRoot = Join-Path $attemptsRoot $sha
        $attemptPath = Join-Path $shaAttemptsRoot $attemptId
        $candidateSource = Join-Path $attemptPath 'source'
        $exportRoot = Join-Path $attemptPath 'export'
        $evidenceRoot = Join-Path $attemptPath 'evidence'
        $attemptReceipt = Join-Path $attemptPath 'attempt.json'
        $runnerReceipt = Join-Path $evidenceRoot 'full-run.receipt'
        [IO.Directory]::CreateDirectory($exportRoot) | Out-Null
        [IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null

        $queueAttempt = [pscustomobject][ordered]@{
            attempt_id = $attemptId
            state = 'RUNNING'
            attempt_path = $attemptPath
            receipt_path = $attemptReceipt
            error = ''
            started_at = Get-UtcText
            terminal_at = ''
        }
        $entry.attempts = @($entry.attempts) + @($queueAttempt)
        $entry.state = 'RUNNING'
        $entry.active_attempt_id = $attemptId
        $entry.active_attempt_path = $attemptPath
        $entry.last_result = 'RUNNING'
        $entry.last_error = ''
        $entry.updated_at = Get-UtcText
        Write-JsonAtomic -Path $queuePath -Value $queue
        Write-JsonAtomic -Path $attemptReceipt -Value ([ordered]@{
            schema_version = 1
            result = 'RUNNING'
            sha = $sha
            attempt_id = $attemptId
            stage = 'start'
            error = ''
            updated_at = Get-UtcText
        })

        $candidateRegistered = $false
        $attemptStage = 'lfs-fetch'
        try {
            Invoke-Native -FilePath git -Arguments @(
                '-C', $latestRoot, 'lfs', 'fetch', 'origin', $sha
            ) | Out-Null

            $attemptStage = 'candidate-worktree'
            Invoke-Native -FilePath git -Arguments @(
                '-C', $latestRoot, 'worktree', 'add', '--detach',
                $candidateSource, $sha
            ) | Out-Null
            $candidateRegistered = $true
            $candidateHead = Assert-FullSha (
                Get-GitText -Repository $candidateSource `
                    -Arguments @('rev-parse', 'HEAD^{commit}')
            ) 'Candidate worktree HEAD'
            if ($candidateHead -cne $sha -or
                -not [string]::IsNullOrWhiteSpace((
                    Get-GitText -Repository $candidateSource `
                        -Arguments @('branch', '--show-current')
                )) -or
                -not [string]::IsNullOrWhiteSpace((Get-GitStatus $candidateSource))) {
                throw 'Candidate worktree is not clean, detached and bound to exact SHA.'
            }
            $candidateCommon = [IO.Path]::GetFullPath((
                Get-GitText -Repository $candidateSource -Arguments @(
                    'rev-parse', '--path-format=absolute', '--git-common-dir'
                )
            )).TrimEnd('\', '/')
            if (-not [string]::Equals(
                $candidateCommon,
                $mirrorCommon,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw 'Candidate worktree does not belong to trusted source mirror.'
            }

            $attemptStage = 'lfs-checkout'
            Invoke-Native -FilePath git -Arguments @(
                '-C', $candidateSource, 'lfs', 'checkout'
            ) | Out-Null
            Invoke-Native -FilePath git -Arguments @(
                '-C', $candidateSource, 'lfs', 'fsck', '--objects',
                '--pointers', 'HEAD'
            ) | Out-Null

            $attemptStage = 'map-check'
            $mapRoot = Join-Path $candidateSource 'underwater_map_workbench'
            $mapResult = Invoke-Native -FilePath python -Arguments @(
                '-B', 'tools/build_underwater_map.py', '--check'
            ) -WorkingDirectory $mapRoot
            Write-Utf8Atomic -Path (Join-Path $evidenceRoot 'map-check.log') `
                -Text ($mapResult.Output + "`n")

            $attemptStage = 'export-preflight'
            $exportPresetPath = Join-Path $candidateSource 'export_presets.cfg'
            $productionManifest = Join-Path $candidateSource `
                'underwater_map_workbench\map_manifest.json'
            if (-not (Test-Path -LiteralPath $productionManifest -PathType Leaf)) {
                throw 'Required production map manifest is missing from the exact candidate.'
            }
            if (-not (Test-ExportSmokeContractAvailable `
                    -Repository $candidateSource)) {
                throw (
                    'Required production exported-application smoke contract is missing ' +
                    'from scripts/core/PlayMainExportSmoke.gd.'
                )
            }
            if (-not (Test-ExportPresetAvailable -Path $exportPresetPath `
                -PresetName $ExportPreset)) {
                throw (
                    "Required Windows export preset '$ExportPreset' is missing " +
                    'from export_presets.cfg.'
                )
            }
            $godot = Resolve-GodotConsole -Requested $GodotConsolePath
            $exportExe = Join-Path $exportRoot 'OstatniPomost.exe'

            $attemptStage = 'export'
            $exportResult = Invoke-Native -FilePath $godot -Arguments @(
                '--headless', '--path', $candidateSource,
                '--export-release', $ExportPreset, $exportExe
            )
            Assert-NoGodotErrors -Output $exportResult.Output -Label 'Godot export'
            Write-Utf8Atomic -Path (Join-Path $evidenceRoot 'export.log') `
                -Text ($exportResult.Output + "`n")
            if (-not (Test-Path -LiteralPath $exportExe -PathType Leaf) -or
                (Get-Item -LiteralPath $exportExe).Length -le 0) {
                throw 'Godot export did not create a nonempty Windows executable.'
            }

            $attemptStage = 'full-runner'
            $runner = Join-Path $candidateSource 'tests\run_all_tests.ps1'
            if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
                throw "Missing full isolated runner: $runner"
            }
            $runnerResult = Invoke-Native -FilePath powershell.exe -Arguments @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $runner,
                '-GodotConsolePath', $godot,
                '-SourceRepositoryPath', $candidateSource,
                '-Full',
                '-RunReceiptOutputPath', $runnerReceipt
            )
            Assert-NoGodotErrors -Output $runnerResult.Output `
                -Label 'Full isolated runner'
            Write-Utf8Atomic -Path (Join-Path $evidenceRoot 'full-runner.log') `
                -Text ($runnerResult.Output + "`n")
            if (-not (Test-Path -LiteralPath $runnerReceipt -PathType Leaf) -or
                [IO.File]::ReadAllText($runnerReceipt) -notmatch `
                    '(?m)^(?:overall|status)=PASS\s*$') {
                throw 'Full isolated runner did not produce a PASS receipt.'
            }

            $attemptStage = 'export-smoke'
            $smokeResult = Invoke-Native -FilePath $exportExe -Arguments @(
                '--headless', '--quit-after', '30', '--',
                '--play-main-smoke', '--build-sha', $sha
            )
            Assert-NoGodotErrors -Output $smokeResult.Output `
                -Label 'Exported application smoke'
            Write-Utf8Atomic -Path (Join-Path $evidenceRoot 'export-smoke.log') `
                -Text ($smokeResult.Output + "`n")
            if ($smokeResult.Output -notmatch `
                    '(?m)^PLAY_MAIN_SMOKE_CREATE=PASS\s*$' -or
                $smokeResult.Output -notmatch `
                    '(?m)^PLAY_MAIN_SMOKE_MAP_LOAD=PASS\s*$') {
                throw (
                    'Exported application smoke did not prove both game creation ' +
                    'and production map loading.'
                )
            }

            $attemptStage = 'source-postflight'
            if ((Get-GitText -Repository $candidateSource `
                    -Arguments @('rev-parse', 'HEAD^{commit}')) -cne $sha -or
                -not [string]::IsNullOrWhiteSpace((Get-GitStatus $candidateSource))) {
                throw 'Build or validation changed the exact candidate source.'
            }

            $attemptStage = 'finalize-build'
            Write-JsonAtomic -Path $attemptReceipt -Value ([ordered]@{
                schema_version = 1
                result = 'PASS'
                sha = $sha
                attempt_id = $attemptId
                stage = 'complete'
                export_sha256 = Get-FileSha256 $exportExe
                run_receipt_sha256 = Get-FileSha256 $runnerReceipt
                error = ''
                terminal_at = Get-UtcText
                updated_at = Get-UtcText
            })
            Write-JsonAtomic -Path (Join-Path $attemptPath 'build.json') `
                -Value ([ordered]@{
                    schema_version = 1
                    result = 'PASS'
                    sha = $sha
                    attempt_id = $attemptId
                    export_relative_path = 'export/OstatniPomost.exe'
                    run_receipt_relative_path = 'evidence/full-run.receipt'
                    created_at = Get-UtcText
                    updated_at = Get-UtcText
                })
            Remove-CandidateWorktree -MirrorPath $latestRoot `
                -CandidateSource $candidateSource
            $candidateRegistered = $false
            if (Test-Path -LiteralPath $buildPath) {
                throw "Immutable build path already exists: $buildPath"
            }
            [IO.Directory]::Move($attemptPath, $buildPath)

            $finalReceipt = Join-Path $buildPath 'attempt.json'
            $receiptDigest = Get-FileSha256 $finalReceipt
            $attemptStage = 'promote-current'
            Set-EntryAttemptState -Entry $entry -AttemptId $attemptId `
                -State 'PROMOTING' -ReceiptPath $finalReceipt
            $entry.state = 'PROMOTING'
            $entry.active_attempt_path = $buildPath
            $entry.last_result = 'PROMOTING'
            $entry.last_error = ''
            $entry.updated_at = Get-UtcText
            Write-JsonAtomic -Path $queuePath -Value $queue

            if (Test-ShouldPromoteCurrent -MirrorPath $latestRoot `
                    -CurrentSha $currentSha -TargetSha $sha) {
                Write-CurrentPointer -Path $currentPath -Sha $sha `
                    -BuildPath $buildPath -AttemptId $attemptId `
                    -ReceiptSha256 $receiptDigest
                $currentSha = $sha
            }

            Set-EntryAttemptState -Entry $entry -AttemptId $attemptId `
                -State 'PASS' -ReceiptPath $finalReceipt
            $entry.state = 'PASS'
            $entry.active_attempt_id = ''
            $entry.active_attempt_path = ''
            $entry.last_result = 'PASS'
            $entry.updated_at = Get-UtcText
            Write-JsonAtomic -Path $queuePath -Value $queue
            Write-RunStatus -Path $statusPath -Result 'PASS' -Stage 'complete' `
                -TargetSha $sha -CurrentSha $currentSha -QueuePath $queuePath `
                -AttemptId $attemptId -AttemptReceipt $finalReceipt `
                -BuildPath $buildPath
            $unresolved = @($queue.entries | Where-Object {
                [string]$_.state -in @('FAIL', 'EXPORT_BOOTSTRAP_REQUIRED')
            } | Sort-Object -Property sequence -Descending)
            if ($unresolved.Count -eq 0) {
                Write-Alert -Path $alertPath -Active $false -Result 'PASS' `
                    -Sha $sha -Stage 'complete'
            }
            else {
                Write-Alert -Path $alertPath -Active $true `
                    -Result ([string]$unresolved[0].state) `
                    -Sha ([string]$unresolved[0].sha) -Stage 'queued-failure' `
                    -ErrorText ([string]$unresolved[0].last_error)
            }
            $builtCount += 1
            Write-Output "SYNC_BUILT sha=$sha build=$buildPath current=$currentPath"
        }
        catch {
            $failure = $_.Exception.Message
            if ((Test-Path -LiteralPath $buildPath -PathType Container) -or
                [string]$entry.state -ceq 'PROMOTING') {
                Write-RunStatus -Path $statusPath -Result 'PROMOTION_IN_DOUBT' `
                    -Stage $attemptStage -TargetSha $sha -CurrentSha $currentSha `
                    -QueuePath $queuePath -AttemptId $attemptId `
                    -ErrorText $failure
                Write-Alert -Path $alertPath -Active $true `
                    -Result 'PROMOTION_IN_DOUBT' -Sha $sha `
                    -Stage $attemptStage -ErrorText $failure
                $failureRecorded = $true
                throw
            }
            $result = 'FAIL'
            if ($attemptStage -ceq 'export-preflight') {
                $result = 'EXPORT_BOOTSTRAP_REQUIRED'
            }
            if ($candidateRegistered -or
                (Test-Path -LiteralPath $candidateSource -PathType Container)) {
                try {
                    Remove-CandidateWorktree -MirrorPath $latestRoot `
                        -CandidateSource $candidateSource
                }
                catch {
                    $failure = "$failure | cleanup: $($_.Exception.Message)"
                }
            }
            if (Test-Path -LiteralPath $attemptPath -PathType Container) {
                Write-JsonAtomic -Path $attemptReceipt -Value ([ordered]@{
                    schema_version = 1
                    result = $result
                    sha = $sha
                    attempt_id = $attemptId
                    stage = $attemptStage
                    error = $failure
                    terminal_at = Get-UtcText
                    updated_at = Get-UtcText
                })
            }
            Set-EntryAttemptState -Entry $entry -AttemptId $attemptId `
                -State $result -ReceiptPath $attemptReceipt -ErrorText $failure
            $entry.state = $result
            $entry.active_attempt_id = ''
            $entry.active_attempt_path = ''
            $entry.last_result = $result
            $entry.last_error = $failure
            $entry.updated_at = Get-UtcText
            Write-JsonAtomic -Path $queuePath -Value $queue
            Write-RunStatus -Path $statusPath -Result $result `
                -Stage $attemptStage -TargetSha $sha -CurrentSha $currentSha `
                -QueuePath $queuePath -AttemptId $attemptId `
                -AttemptReceipt $attemptReceipt -ErrorText $failure
            Write-Alert -Path $alertPath -Active $true -Result $result `
                -Sha $sha -Stage $attemptStage -ErrorText $failure
            $failureRecorded = $true
            [void]$terminalFailures.Add("${sha}:${result}:${failure}")
            Write-Output (
                "SYNC_BUILD_FAILED result=$result stage=$attemptStage " +
                "sha=$sha current=$currentSha alert=$alertPath"
            )
            continue
        }
    }

    if ($builtCount -eq 0) {
        $remaining = @($queue.entries | Where-Object {
            [string]$_.state -cne 'PASS'
        })
        if ($remaining.Count -eq 0) {
            Write-RunStatus -Path $statusPath -Result 'PASS' -Stage 'unchanged' `
                -TargetSha $targetSha -CurrentSha $currentSha `
                -QueuePath $queuePath
            Write-Output "SYNC_UNCHANGED sha=$targetSha current=$currentSha"
        }
        else {
            Write-Output (
                "SYNC_NO_PENDING unresolved_failures=$($remaining.Count) " +
                "current=$currentSha"
            )
        }
    }
    if ($terminalFailures.Count -gt 0) {
        throw (
            'One or more exact main SHA builds failed after the remaining queue ' +
            "continued: $($terminalFailures -join ' | ')"
        )
    }
}
catch {
    if (-not $failureRecorded) {
        $failure = $_.Exception.Message
        try {
            Write-RunStatus -Path $statusPath -Result 'FAIL' `
                -Stage $failureStage -TargetSha $targetSha `
                -CurrentSha $currentSha -QueuePath $queuePath `
                -ErrorText $failure
            Write-Alert -Path $alertPath -Active $true -Result 'FAIL' `
                -Sha $targetSha -Stage $failureStage -ErrorText $failure
        }
        catch {
            # Preserve the original failure when even durable reporting is unavailable.
        }
    }
    throw
}
finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}
