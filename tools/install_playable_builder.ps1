#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [string]$GodotConsolePath,
    [string]$TaskName = 'Potop-v2-playable-builder',
    [ValidateRange(5, 300)][int]$PollSeconds = 30,
    [switch]$Uninstall,
    [switch]$StartNow
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-GitChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $command = @(Get-Command git -CommandType Application,ExternalScript -ErrorAction Stop)[0]
    $executable = if ($command.Path) { $command.Path } else { $command.Source }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $executable -C $Repository @Arguments 2>&1); $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $(($output | Out-String).Trim())"
    }
    return ($output | Out-String).Trim()
}

function Quote-TaskArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Contains('"')) { throw "Scheduled-task argument contains a quote: '$Value'." }
    return '"' + $Value + '"'
}

if ($TaskName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._ -]{0,100}$') {
    throw "Invalid scheduled task name: '$TaskName'."
}
if ($Uninstall) {
    if ($PSCmdlet.ShouldProcess($TaskName, 'unregister playable builder scheduled task')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "PLAYABLE BUILDER UNINSTALLED: $TaskName"
    }
    return
}

$repoTop = [System.IO.Path]::GetFullPath(
    (Invoke-GitChecked @('rev-parse', '--show-toplevel'))
).TrimEnd('\', '/')
$gitDirectory = [System.IO.Path]::GetFullPath(
    (Invoke-GitChecked @('rev-parse', '--path-format=absolute', '--git-dir'))
).TrimEnd('\', '/')
$commonDirectory = [System.IO.Path]::GetFullPath(
    (Invoke-GitChecked @('rev-parse', '--path-format=absolute', '--git-common-dir'))
).TrimEnd('\', '/')
if (-not [string]::Equals($gitDirectory, $commonDirectory, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
    throw 'The playable builder requires one standalone clone, not a linked worktree.'
}
$branch = (Invoke-GitChecked @('branch', '--show-current')).Trim()
$status = Invoke-GitChecked @('status', '--porcelain=v1', '--untracked-files=all')
if ($branch -cne 'main' -or -not [string]::IsNullOrWhiteSpace($status)) {
    throw "The playable builder clone must be clean on main: branch=$branch status='$status'."
}
$builder = Join-Path $repoTop 'tools/build_playable_main.ps1'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "Playable builder script is missing: '$builder'."
}
if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
    $GodotConsolePath = [System.IO.Path]::GetFullPath($GodotConsolePath)
    if (-not (Test-Path -LiteralPath $GodotConsolePath -PathType Leaf)) {
        throw "Godot console executable is missing: '$GodotConsolePath'."
    }
}
$pwshCommand = @(Get-Command pwsh -CommandType Application -ErrorAction Stop)[0]
$pwshPath = if (-not [string]::IsNullOrWhiteSpace([string]$pwshCommand.Path)) {
    [string]$pwshCommand.Path
}
else { [string]$pwshCommand.Source }

$argumentParts = @(
    '-NoLogo', '-NoProfile', '-NonInteractive', '-File', (Quote-TaskArgument $builder),
    '-Repository', (Quote-TaskArgument $repoTop), '-Watch',
    '-PollSeconds', [string]$PollSeconds
)
if (-not [string]::IsNullOrWhiteSpace($GodotConsolePath)) {
    $argumentParts += @('-GodotConsolePath', (Quote-TaskArgument $GodotConsolePath))
}
$action = New-ScheduledTaskAction -Execute $pwshPath -Argument ($argumentParts -join ' ')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

$installed = $false
if ($PSCmdlet.ShouldProcess($TaskName, "register automatic playable builder for '$repoTop'")) {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description 'Build exact Potop_v2 main SHA and promote builds/current only after PASS.' `
        -Force | Out-Null
    if ($StartNow) { Start-ScheduledTask -TaskName $TaskName }
    $installed = $true
}
if ($installed) { Write-Host "PLAYABLE BUILDER INSTALLED: $TaskName" }
else { Write-Host "PLAYABLE BUILDER PLAN ONLY: $TaskName" }
Write-Host "repository=$repoTop"
Write-Host "poll_seconds=$PollSeconds"
