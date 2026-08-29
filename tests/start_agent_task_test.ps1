#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/start_agent_task.ps1'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($tool, [ref]$tokens, [ref]$errors)
if (@($errors).Count -ne 0) {
    throw "start_agent_task.ps1 does not parse: $($errors -join '; ')"
}

$source = Get-Content -LiteralPath $tool -Raw
foreach ($required in @(
    "Join-Path (Split-Path -Parent `$primaryRoot) 'agent-worktrees'",
    '[guid]::NewGuid()',
    'yyyyMMdd-HHmmss',
    'cleanup_merged_worktrees.ps1',
    '-not `$PlanOnly',
    'setup_agent_worktree.ps1',
    'root|base|map|diver|integration',
    '`$arguments.Create = `$true',
    'AGENT TASK READY'
)) {
    if (-not $source.Contains($required.Replace('`$', '$'))) {
        throw "Simple task start contract is missing: $required"
    }
}
if ($source -match '(?i)reset\s+--hard|worktree\s+add|branch\s+-D') {
    throw 'The thin start helper must delegate creation and never reset/delete directly.'
}

Write-Host 'PASS one-command unique worktree start contract'
