#requires -Version 5.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'tools/plan_github_ruleset.ps1'
$integrationWorkflow = Join-Path $projectRoot '.github/workflows/agent-integration.yml'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("potop-ruleset-plan-test-" + [guid]::NewGuid().ToString('N'))
$hostPowerShell = if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Join-Path $PSHOME 'powershell.exe'
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}

function Run-Plan {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $hostPowerShell -NoLogo -NoProfile -File $tool @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

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
    if ([int]$pull.required_approving_review_count -ne 0 -or
        [bool]$pull.require_code_owner_review -or [bool]$pull.require_last_push_approval -or
        [bool]$pull.require_extra_approval_for_unattributed_changes -or
        [bool]$pull.required_review_thread_resolution -or @($pull.required_reviewers).Count -ne 0) {
        throw 'Simple agent flow unexpectedly requires a general PR review.'
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
        throw 'Native merge queue is not SQUASH/ALLGREEN with one concurrent build and one sequential merge.'
    }
    $workflowSource = Get-Content -LiteralPath $integrationWorkflow -Raw
    $timeoutMatch = [regex]::Match(
        $workflowSource,
        '(?ms)^  integration-green:\r?\n.*?^    timeout-minutes:\s*(\d+)\s*$'
    )
    if (-not $timeoutMatch.Success) {
        throw 'Cannot bind ruleset timeout to integration-green timeout-minutes.'
    }
    $integrationTimeout = [int]$timeoutMatch.Groups[1].Value
    if ($integrationTimeout -ne 120 -or [int]$queue.check_response_timeout_minutes -ne 180 -or
        [int]$queue.check_response_timeout_minutes -le $integrationTimeout -or
        [int]$plan.full_integration_timeout_minutes -ne $integrationTimeout -or
        [int]$plan.queue_check_timeout_minutes -ne [int]$queue.check_response_timeout_minutes) {
        throw 'Queue timeout is not pinned to 180 minutes and strictly greater than the 120-minute full integration job.'
    }

    $output = Join-Path $tempRoot 'plan.json'
    & $tool -OutputPath $output
    $written = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if ([string]$written.payload.rules[3].parameters.required_status_checks[0].context -cne 'fast-check') {
        throw 'Written plan differs from the stdout plan.'
    }

    foreach ($override in @(
        @('-GitHubActionsAppId', '1'),
        @('-QueueTimeoutMinutes', '1')
    )) {
        $overrideOutput = Join-Path $tempRoot ((($override[0] -replace '^-', '') + '.json'))
        $rejected = Run-Plan (@($override) + @('-OutputPath', $overrideOutput))
        if ($rejected.ExitCode -eq 0 -or (Test-Path -LiteralPath $overrideOutput)) {
            throw "Unsafe ruleset override generated a plan: $($override -join ' ') output=$($rejected.Output)"
        }
    }

    $source = Get-Content -LiteralPath $tool -Raw
    foreach ($forbidden in @('Invoke-RestMethod', 'Invoke-WebRequest', 'gh api', 'Method PUT', 'Authorization =', 'GITHUB_TOKEN')) {
        if ($source -match [regex]::Escape($forbidden)) { throw "Plan tool can mutate live GitHub: '$forbidden'." }
    }
    if ($source -match '\$GitHubActionsAppId|\$QueueTimeoutMinutes') {
        throw 'Ruleset tool still exposes an identity or timeout override.'
    }
    Write-Host 'PASS plan_github_ruleset native-queue/squash/Actions-App-15368/180min>120min/no-bypass/no-live-mutation contract'
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
