#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$RepositorySlug = 'GodotGamePlatforma/Potop_v2',
    [string]$RulesetName = 'Protect main - simple agent flow',
    [ValidateRange(1, 2147483647)]
    [int]$GitHubActionsAppId = 15368,
    [ValidateRange(1, 1440)]
    [int]$QueueTimeoutMinutes = 120,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($RepositorySlug -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Invalid GitHub repository slug: '$RepositorySlug'."
}

$payload = [ordered]@{
    name = $RulesetName
    target = 'branch'
    enforcement = 'active'
    bypass_actors = @()
    conditions = [ordered]@{
        ref_name = [ordered]@{
            include = @('refs/heads/main')
            exclude = @()
        }
    }
    rules = @(
        [ordered]@{ type = 'deletion' },
        [ordered]@{ type = 'non_fast_forward' },
        [ordered]@{
            type = 'pull_request'
            parameters = [ordered]@{
                allowed_merge_methods = @('squash')
                dismiss_stale_reviews_on_push = $true
                dismissal_restriction = [ordered]@{
                    allowed_actors = @()
                    enabled = $false
                }
                require_code_owner_review = $false
                require_extra_approval_for_unattributed_changes = $false
                require_last_push_approval = $false
                required_approving_review_count = 0
                required_review_thread_resolution = $false
                required_reviewers = @()
            }
        },
        [ordered]@{
            type = 'required_status_checks'
            parameters = [ordered]@{
                do_not_enforce_on_create = $false
                strict_required_status_checks_policy = $false
                required_status_checks = @(
                    [ordered]@{
                        context = 'fast-check'
                        integration_id = $GitHubActionsAppId
                    }
                )
            }
        },
        [ordered]@{
            type = 'merge_queue'
            parameters = [ordered]@{
                check_response_timeout_minutes = $QueueTimeoutMinutes
                grouping_strategy = 'ALLGREEN'
                # One candidate may build at once; this is queue concurrency,
                # not a claim about how many PRs GitHub puts in a group.
                max_entries_to_build = 1
                # Merge exactly one successful squash result at a time.
                max_entries_to_merge = 1
                merge_method = 'SQUASH'
                min_entries_to_merge = 1
                min_entries_to_merge_wait_minutes = 0
            }
        }
    )
}

$plan = [ordered]@{
    schema = 'potop-simple-ruleset-plan-v1'
    repository = $RepositorySlug
    mutation_performed = $false
    required_check_owner = 'GitHub Actions'
    payload = $payload
}
$json = $plan | ConvertTo-Json -Depth 20

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolved = [System.IO.Path]::GetFullPath($OutputPath)
    $directory = Split-Path -Parent $resolved
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Output directory does not exist: '$directory'."
    }
    [System.IO.File]::WriteAllText($resolved, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host "RULESET PLAN WRITTEN: $resolved"
}
else {
    $json
}

Write-Host 'PLAN ONLY - no GitHub API mutation was performed.'
