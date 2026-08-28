#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/plan_github_ruleset.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-ruleset-plan-test-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $json = & $tool -RepositorySlug 'GodotGamePlatforma/Potop_v2'
    $plan = ($json | Out-String) | ConvertFrom-Json
    if ([string]$plan.schema -cne 'potop-simple-ruleset-plan-v1' -or [bool]$plan.mutation_performed) {
        throw 'Ruleset plan schema/mutation marker is invalid.'
    }
    $payload = $plan.payload
    if ([string]$payload.target -cne 'branch' -or [string]$payload.enforcement -cne 'active' -or
        @($payload.bypass_actors).Count -ne 0 -or @($payload.conditions.ref_name.include).Count -ne 1 -or
        [string]$payload.conditions.ref_name.include[0] -cne 'refs/heads/main') {
        throw 'Ruleset does not protect exact main without bypass.'
    }
    $rules = @{}
    foreach ($rule in @($payload.rules)) {
        if ($rules.ContainsKey([string]$rule.type)) { throw "Duplicate rule '$($rule.type)'." }
        $rules[[string]$rule.type] = $rule
    }
    foreach ($required in @('deletion','non_fast_forward','pull_request','required_status_checks','merge_queue')) {
        if (-not $rules.ContainsKey($required)) { throw "Missing ruleset rule '$required'." }
    }
    $pull = $rules.pull_request.parameters
    if (@($pull.allowed_merge_methods).Count -ne 1 -or [string]$pull.allowed_merge_methods[0] -cne 'squash') {
        throw 'Squash is not the only allowed PR merge method.'
    }
    $checks = $rules.required_status_checks.parameters
    if (@($checks.required_status_checks).Count -ne 1 -or
        [string]$checks.required_status_checks[0].context -cne 'fast-check' -or
        [int]$checks.required_status_checks[0].integration_id -ne 15368 -or
        [bool]$checks.strict_required_status_checks_policy) {
        throw 'Required check is not the single non-strict GitHub Actions fast-check.'
    }
    $queue = $rules.merge_queue.parameters
    if ([string]$queue.merge_method -cne 'SQUASH' -or [string]$queue.grouping_strategy -cne 'ALLGREEN' -or
        [int]$queue.min_entries_to_merge -ne 1 -or [int]$queue.max_entries_to_merge -ne 1 -or
        [int]$queue.max_entries_to_build -ne 1 -or [int]$queue.min_entries_to_merge_wait_minutes -ne 0) {
        throw 'Native merge queue is not the exact SQUASH/ALLGREEN/group-size-one contract.'
    }

    $output = Join-Path $tempRoot 'plan.json'
    & $tool -OutputPath $output
    $written = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if ([string]$written.payload.rules[3].parameters.required_status_checks[0].context -cne 'fast-check') {
        throw 'Written plan differs from the stdout plan.'
    }

    $source = Get-Content -LiteralPath $tool -Raw
    foreach ($forbidden in @('Invoke-RestMethod', 'Invoke-WebRequest', 'gh api', 'Method PUT', 'Authorization =', 'GITHUB_TOKEN')) {
        if ($source -match [regex]::Escape($forbidden)) { throw "Plan tool can mutate live GitHub: '$forbidden'." }
    }
    Write-Host 'PASS plan_github_ruleset native-queue/squash/one-Actions-fast-check/no-bypass/no-live-mutation contract'
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
