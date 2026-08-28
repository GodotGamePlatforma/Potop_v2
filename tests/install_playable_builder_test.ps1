#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/install_playable_builder.ps1'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($tool, [ref]$tokens, [ref]$errors)
if (@($errors).Count -ne 0) {
    throw "install_playable_builder.ps1 does not parse: $($errors -join '; ')"
}
$source = Get-Content -LiteralPath $tool -Raw
foreach ($required in @(
    "'-Watch'",
    'New-ScheduledTaskTrigger -AtLogOn',
    '-StartWhenAvailable',
    '-MultipleInstances IgnoreNew',
    '-RestartCount 3',
    'Register-ScheduledTask',
    'Unregister-ScheduledTask',
    'build_playable_main.ps1',
    "`$gitDirectory, `$commonDirectory"
)) {
    if (-not $source.Contains($required)) {
        throw "Playable builder installer contract is missing: $required"
    }
}
foreach ($forbidden in @('Password','reset --hard','git clean','Remove-Item -Recurse')) {
    if ($source -match [regex]::Escape($forbidden)) {
        throw "Playable builder installer contains forbidden behavior: $forbidden"
    }
}

Write-Host 'PASS idempotent at-logon playable builder installer contract'
