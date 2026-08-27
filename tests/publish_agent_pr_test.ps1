$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'tools\publish_agent_pr.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw
[void][scriptblock]::Create($text)

function Assert-PublisherInvariant {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

$required = @(
    "'pr', 'list', '--repo', `$githubRepo, '--state', 'all'",
    "'rev-parse', '--verify'",
    "'refs/remotes/origin/main^{commit}'",
    "'assignment', 'current', '--json'",
    "'--assignment', `$assignmentId",
    "'--task-id', `$taskId",
    "'--thread-id', `$threadId",
    "'--owner', `$owner, '--base', `$originMain",
    "'event_type=verify-fast-pr'",
    "'client_payload[kind]=pull_request'",
    "'variable', 'get', 'AUTO_INTEGRATOR_ENABLED'",
    '"${head}:refs/heads/$branch"',
    "'--auto', '--squash', '--match-head-commit', `$head",
    "'assignment', 'close'",
    "if (`$remoteHead -cne `$head)",
    "if (`$null -ne `$state.mergedAt)",
    "if (`$null -ne `$pull.mergedAt)"
)
foreach ($marker in $required) {
    if (-not $text.Contains($marker)) {
        throw "publish_agent_pr.ps1 is missing required marker: $marker"
    }
}

$forbidden = @(
    '--admin',
    '--force',
    'integration-ready',
    'control-plane-reviewed',
    "'--auto', '--merge'",
    "'--disable-auto'",
    'ci_protected_paths.py',
    'MANUAL_CONTROL_PLANE',
    'auto_merge=off',
    '[string]$TaskId',
    '[string]$ThreadId',
    '[string]$AssignmentId',
    '[string]$Owner'
)
foreach ($marker in $forbidden) {
    if ($text.Contains($marker)) {
        throw "publish_agent_pr.ps1 contains forbidden marker: $marker"
    }
}

$freshBaseOffset = $text.IndexOf('Assert-RepositoryIdentity -Repository $repo')
$validationOffset = $text.IndexOf("'--assignment', `$assignmentId")
$pushOffset = $text.IndexOf("'push', '--set-upstream'")
$dispatchOffset = $text.IndexOf("'event_type=verify-fast-pr'")
$mergeOffset = $text.IndexOf("'--auto', '--squash'")
if (-not (0 -le $freshBaseOffset -and $freshBaseOffset -lt $validationOffset -and
    $validationOffset -lt $pushOffset -and $pushOffset -lt $dispatchOffset -and
    $dispatchOffset -lt $mergeOffset)) {
    throw 'Fresh-base, assignment validation, exact push, trusted dispatch and queue admission are not ordered safely.'
}

function Invoke-TestGit {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed ($exitCode): $($output | Out-String)"
    }
    return ($output | Out-String).Trim()
}

function Write-TestText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [System.IO.File]::WriteAllText(
        $Path,
        $Value,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function New-PublisherFixture {
    param([Parameter(Mandatory = $true)][string]$Name)
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'potop-publish-test-' + $Name + '-' + [Guid]::NewGuid().ToString('N')
    )
    $remote = Join-Path $fixtureRoot 'origin.git'
    $repository = Join-Path $fixtureRoot 'repo'
    [void](New-Item -ItemType Directory -Path $fixtureRoot)
    Invoke-TestGit -Arguments @('init', '--bare', '--initial-branch=main', $remote) | Out-Null
    Invoke-TestGit -Arguments @('init', '--initial-branch=main', $repository) | Out-Null
    Invoke-TestGit -Arguments @('-C', $repository, 'config', 'user.name', 'Publisher Test') | Out-Null
    Invoke-TestGit -Arguments @('-C', $repository, 'config', 'user.email', 'publisher@example.invalid') | Out-Null

    Write-TestText -Path (Join-Path $repository 'ordinary.txt') -Value "base`n"
    Write-TestText -Path (Join-Path $repository 'tools\workbench_contract.py') -Value "# fixture`n"
    Write-TestText -Path (Join-Path $repository 'tools\workbench_lock.py') -Value "# fixture`n"
    Write-TestText -Path (Join-Path $repository '.github\workflows\legacy.yml') -Value "name: legacy`n"
    Invoke-TestGit -Arguments @('-C', $repository, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $repository, 'commit', '-m', 'base') | Out-Null
    Invoke-TestGit -Arguments @('-C', $repository, 'remote', 'add', 'origin', $remote) | Out-Null
    Invoke-TestGit -Arguments @('-C', $repository, 'push', '--set-upstream', 'origin', 'main') | Out-Null
    return [pscustomobject]@{
        Root = $fixtureRoot
        Remote = $remote
        Repository = $repository
    }
}

$global:PublishAgentPrGhCalls = New-Object System.Collections.ArrayList
$global:PublishAgentPrHead = ''
$global:PublishAgentPrBase = ''
$global:PublishAgentPrPythonCalls = New-Object System.Collections.ArrayList
$global:PublishAgentPrMutateOnOwner = ''
$global:PublishAgentPrAssignmentId = '0123456789abcdef0123456789abcdef'
$global:PublishAgentPrAssignmentDigest = ('a' * 64)
$global:PublishAgentPrMergedList = '[]'
$global:PublishAgentPrAssignmentHead = ''
$global:PublishAgentPrAssignmentBranch = ''
$global:PublishAgentPrAutoEnabled = 'true'

function global:gh {
    $arguments = @($args | ForEach-Object { [string]$_ })
    [void]$global:PublishAgentPrGhCalls.Add(($arguments -join ' '))
    $result = switch ("$($arguments[0]) $($arguments[1])") {
        'repo view' { 'owner/repository' }
        'variable get' { $global:PublishAgentPrAutoEnabled }
        'pr list' { $global:PublishAgentPrMergedList }
        'pr create' { 'https://example.invalid/pull/1' }
        'pr view' {
            '{"number":1,"url":"https://example.invalid/pull/1","headRefOid":"' +
                $global:PublishAgentPrHead +
                '","baseRefOid":"' + $global:PublishAgentPrBase +
                '","mergedAt":null,"state":"OPEN","statusCheckRollup":[]}'
        }
        'pr merge' { 'auto merge enabled' }
        'api --method' { '' }
        default { throw "Unexpected fake gh command: $($arguments -join ' ')" }
    }
    $global:LASTEXITCODE = 0
    return $result
}

function global:python {
    $arguments = @($args | ForEach-Object { [string]$_ })
    [void]$global:PublishAgentPrPythonCalls.Add(($arguments -join ' '))
    $joined = $arguments -join ' '
    $ownerInvocation = $joined -match '(?:^| )validate(?: |$)' -and
        $joined -match '(?:^| )--assignment(?: |$)'
    if ($ownerInvocation -and
        -not [string]::IsNullOrWhiteSpace($global:PublishAgentPrMutateOnOwner)) {
        & git -C $global:PublishAgentPrMutateOnOwner commit --allow-empty `
            -m 'simulated owner-validation race' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot create the simulated owner-validation race commit.'
        }
        $global:PublishAgentPrMutateOnOwner = ''
    }
    if ($joined -match 'assignment current --json') {
        $global:LASTEXITCODE = 0
        return ('{"state":"RUNNING","assignment":{' +
            '"assignment_id":"' + $global:PublishAgentPrAssignmentId + '",' +
            '"assignment_digest":"' + $global:PublishAgentPrAssignmentDigest + '",' +
            '"task_id":"/root/publish-test","thread_id":"thread-publish-test",' +
            '"owner":"integration","head":"' +
            $global:PublishAgentPrAssignmentHead + '","branch":"' +
            $global:PublishAgentPrAssignmentBranch + '"}}')
    }
    if ($joined -match '(?:^| )validate(?: |$)' -and $joined -match '--json') {
        $global:LASTEXITCODE = 0
        return '{"ready":true,"assignment_state":"RUNNING"}'
    }
    if ($joined -match 'assignment close') {
        $global:LASTEXITCODE = 0
        return '{"state":"CLOSED"}'
    }
    $global:LASTEXITCODE = 0
}

$fixtures = New-Object System.Collections.ArrayList
$previousLocation = Get-Location
try {
    # A branch forked before the current origin/main must fail before push or PR.
    $stale = New-PublisherFixture -Name 'stale'
    [void]$fixtures.Add($stale)
    Invoke-TestGit -Arguments @('-C', $stale.Repository, 'checkout', '-b', 'codex/root/stale') | Out-Null
    Write-TestText -Path (Join-Path $stale.Repository 'feature.txt') -Value "feature`n"
    Invoke-TestGit -Arguments @('-C', $stale.Repository, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $stale.Repository, 'commit', '-m', 'feature') | Out-Null

    $updater = Join-Path $stale.Root 'updater'
    Invoke-TestGit -Arguments @('clone', $stale.Remote, $updater) | Out-Null
    Invoke-TestGit -Arguments @('-C', $updater, 'config', 'user.name', 'Main Updater') | Out-Null
    Invoke-TestGit -Arguments @('-C', $updater, 'config', 'user.email', 'updater@example.invalid') | Out-Null
    Write-TestText -Path (Join-Path $updater 'main-update.txt') -Value "new main`n"
    Invoke-TestGit -Arguments @('-C', $updater, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $updater, 'commit', '-m', 'move main') | Out-Null
    Invoke-TestGit -Arguments @('-C', $updater, 'push', 'origin', 'main') | Out-Null

    $global:PublishAgentPrGhCalls.Clear()
    $global:PublishAgentPrPythonCalls.Clear()
    Set-Location -LiteralPath $stale.Repository
    $staleFailed = $false
    $staleFailure = ''
    try {
        & $scriptPath -NoWait
    }
    catch {
        $staleFailure = $_.Exception.Message
        $staleFailed = $_.Exception.Message -like 'Repository identity changed:*'
    }
    Assert-PublisherInvariant $staleFailed (
        'A branch behind origin/main did not fail with the stale-base diagnostic. ' +
        "Actual: $staleFailure"
    )
    Assert-PublisherInvariant (
        @($global:PublishAgentPrGhCalls | Where-Object {
            $_ -like 'pr create *' -or $_ -like 'pr merge *' -or $_ -like 'pr view *'
        }).Count -eq 0
    ) 'The stale-base path called a mutating or materializing PR API.'
    Assert-PublisherInvariant (
        [string]::IsNullOrWhiteSpace((Invoke-TestGit -Arguments @(
            'ls-remote', '--heads', $stale.Remote, 'refs/heads/codex/root/stale'
        )))
    ) 'The stale-base path pushed the task branch.'
    Assert-PublisherInvariant (
        $global:PublishAgentPrPythonCalls.Count -eq 0
    ) 'The stale-base path ran later Python gates instead of failing immediately.'

    # A retry after exact squash merge closes the durable assignment before
    # fresh-base admission, because squash main is not an ancestor of PR HEAD.
    $merged = New-PublisherFixture -Name 'merged-recovery'
    [void]$fixtures.Add($merged)
    $mergedBranch = 'codex/root/merged-recovery'
    Invoke-TestGit -Arguments @('-C', $merged.Repository, 'checkout', '-b', $mergedBranch) | Out-Null
    Write-TestText -Path (Join-Path $merged.Repository 'ordinary.txt') -Value "merged recovery`n"
    Invoke-TestGit -Arguments @('-C', $merged.Repository, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $merged.Repository, 'commit', '-m', 'merged recovery') | Out-Null
    $mergedHead = Invoke-TestGit -Arguments @(
        '-C', $merged.Repository, 'rev-parse', 'HEAD^{commit}'
    )
    $mergedAssignmentHead = Invoke-TestGit -Arguments @(
        '-C', $merged.Repository, 'rev-parse', 'HEAD^1^{commit}'
    )
    $mergedUpdater = Join-Path $merged.Root 'merged-updater'
    Invoke-TestGit -Arguments @('clone', $merged.Remote, $mergedUpdater) | Out-Null
    Invoke-TestGit -Arguments @('-C', $mergedUpdater, 'config', 'user.name', 'Merge Updater') | Out-Null
    Invoke-TestGit -Arguments @('-C', $mergedUpdater, 'config', 'user.email', 'merge@example.invalid') | Out-Null
    Write-TestText -Path (Join-Path $mergedUpdater 'squash-main.txt') -Value "squash result`n"
    Invoke-TestGit -Arguments @('-C', $mergedUpdater, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $mergedUpdater, 'commit', '-m', 'squash main') | Out-Null
    Invoke-TestGit -Arguments @('-C', $mergedUpdater, 'push', 'origin', 'main') | Out-Null
    $global:PublishAgentPrAssignmentHead = $mergedAssignmentHead
    $global:PublishAgentPrAssignmentBranch = $mergedBranch
    $global:PublishAgentPrMergedList = @(
        [pscustomobject]@{
            number = 9
            url = 'https://example.invalid/pull/9'
            headRefOid = $mergedHead
            headRefName = $mergedBranch
            baseRefName = 'main'
            mergedAt = '2026-08-28T00:00:00Z'
            state = 'MERGED'
        }
    ) | ConvertTo-Json -Compress
    $global:PublishAgentPrGhCalls.Clear()
    $global:PublishAgentPrPythonCalls.Clear()
    Set-Location -LiteralPath $merged.Repository
    $mergedOutput = @(& $scriptPath -NoWait 2>&1) -join "`n"
    Assert-PublisherInvariant (
        $mergedOutput -match 'PR_MERGED_RECOVERED' -and
        $mergedOutput -match 'assignment_state=CLOSED'
    ) "Merged PR recovery did not close the assignment. Output: $mergedOutput"
    Assert-PublisherInvariant (
        @($global:PublishAgentPrPythonCalls | Where-Object {
            $_ -match 'assignment close' -and $_ -match 'immutable_pr_merged_recovery'
        }).Count -eq 1
    ) 'Merged PR recovery did not emit exactly one idempotent assignment close.'
    Assert-PublisherInvariant (
        @($global:PublishAgentPrGhCalls | Where-Object {
            $_ -like 'pr create *' -or $_ -like 'pr merge *' -or
            $_ -like 'api --method POST *'
        }).Count -eq 0
    ) 'Merged PR recovery attempted to republish or requeue the immutable PR.'
    $global:PublishAgentPrMergedList = '[]'
    $global:PublishAgentPrAssignmentHead = ''
    $global:PublishAgentPrAssignmentBranch = ''

    # A lock-free double snapshot rejects a HEAD change during owner validation
    # and still fails before push/PR.
    $raced = New-PublisherFixture -Name 'identity-race'
    [void]$fixtures.Add($raced)
    Invoke-TestGit -Arguments @('-C', $raced.Repository, 'checkout', '-b', 'codex/root/identity-race') | Out-Null
    Write-TestText -Path (Join-Path $raced.Repository 'ordinary.txt') -Value "race candidate`n"
    Invoke-TestGit -Arguments @('-C', $raced.Repository, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $raced.Repository, 'commit', '-m', 'race candidate') | Out-Null
    $global:PublishAgentPrHead = Invoke-TestGit -Arguments @(
        '-C', $raced.Repository, 'rev-parse', 'HEAD^{commit}'
    )
    $global:PublishAgentPrBase = Invoke-TestGit -Arguments @(
        '-C', $raced.Repository, 'rev-parse', 'refs/remotes/origin/main^{commit}'
    )
    $global:PublishAgentPrGhCalls.Clear()
    $global:PublishAgentPrPythonCalls.Clear()
    $global:PublishAgentPrMutateOnOwner = $raced.Repository
    Set-Location -LiteralPath $raced.Repository
    $raceFailed = $false
    $raceMessage = ''
    try {
        & $scriptPath -NoWait
    }
    catch {
        $raceMessage = $_.Exception.Message
        $raceFailed = $_.Exception.Message -like 'Repository identity changed:*'
    }
    finally {
        $global:PublishAgentPrMutateOnOwner = ''
    }
    Assert-PublisherInvariant $raceFailed "A HEAD change during owner validation was not rejected by the second snapshot: $raceMessage"
    Assert-PublisherInvariant (
        @($global:PublishAgentPrGhCalls | Where-Object {
            $_ -like 'pr create *' -or $_ -like 'pr merge *' -or
            $_ -like 'pr view *' -or $_ -like 'api --method POST *'
        }).Count -eq 0
    ) 'The raced identity path called a mutating or materializing PR API.'
    Assert-PublisherInvariant (
        [string]::IsNullOrWhiteSpace((Invoke-TestGit -Arguments @(
            'ls-remote', '--heads', $raced.Remote, 'refs/heads/codex/root/identity-race'
        )))
    ) 'The raced identity path pushed the task branch.'

    # The local publisher cannot enqueue anything while the trusted receiver is
    # deliberately disabled for bootstrap, canary or rollback.
    $disabled = New-PublisherFixture -Name 'auto-disabled'
    [void]$fixtures.Add($disabled)
    Invoke-TestGit -Arguments @('-C', $disabled.Repository, 'checkout', '-b', 'codex/root/auto-disabled') | Out-Null
    Write-TestText -Path (Join-Path $disabled.Repository 'ordinary.txt') -Value "disabled candidate`n"
    Invoke-TestGit -Arguments @('-C', $disabled.Repository, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $disabled.Repository, 'commit', '-m', 'disabled candidate') | Out-Null
    $global:PublishAgentPrHead = Invoke-TestGit -Arguments @(
        '-C', $disabled.Repository, 'rev-parse', 'HEAD^{commit}'
    )
    $global:PublishAgentPrBase = Invoke-TestGit -Arguments @(
        '-C', $disabled.Repository, 'rev-parse', 'refs/remotes/origin/main^{commit}'
    )
    $global:PublishAgentPrGhCalls.Clear()
    $global:PublishAgentPrPythonCalls.Clear()
    $global:PublishAgentPrAutoEnabled = 'false'
    Set-Location -LiteralPath $disabled.Repository
    $disabledFailed = $false
    try {
        & $scriptPath -NoWait
    }
    catch {
        $disabledFailed = $_.Exception.Message -like `
            'Trusted automatic admission is not enabled*'
    }
    finally {
        $global:PublishAgentPrAutoEnabled = 'true'
    }
    Assert-PublisherInvariant $disabledFailed `
        'AUTO_INTEGRATOR_ENABLED=false did not fail closed before publication.'
    Assert-PublisherInvariant (
        @($global:PublishAgentPrGhCalls | Where-Object {
            $_ -like 'pr create *' -or $_ -like 'pr merge *' -or
            $_ -like 'api --method POST *'
        }).Count -eq 0
    ) 'Disabled automatic admission still created, dispatched or merged a PR.'
    Assert-PublisherInvariant (
        [string]::IsNullOrWhiteSpace((Invoke-TestGit -Arguments @(
            'ls-remote', '--heads', $disabled.Remote,
            'refs/heads/codex/root/auto-disabled'
        )))
    ) 'Disabled automatic admission still pushed the task branch.'

    # A fresh ordinary branch requests one native merge auto-merge.
    $ordinary = New-PublisherFixture -Name 'ordinary'
    [void]$fixtures.Add($ordinary)
    Invoke-TestGit -Arguments @('-C', $ordinary.Repository, 'checkout', '-b', 'codex/root/ordinary') | Out-Null
    Write-TestText -Path (Join-Path $ordinary.Repository 'ordinary.txt') -Value "ordinary change`n"
    Invoke-TestGit -Arguments @('-C', $ordinary.Repository, 'add', '--all') | Out-Null
    Invoke-TestGit -Arguments @('-C', $ordinary.Repository, 'commit', '-m', 'ordinary change') | Out-Null
    $global:PublishAgentPrHead = Invoke-TestGit -Arguments @(
        '-C', $ordinary.Repository, 'rev-parse', 'HEAD^{commit}'
    )
    $global:PublishAgentPrBase = Invoke-TestGit -Arguments @(
        '-C', $ordinary.Repository, 'rev-parse', 'refs/remotes/origin/main^{commit}'
    )
    $global:PublishAgentPrGhCalls.Clear()
    $global:PublishAgentPrPythonCalls.Clear()
    Set-Location -LiteralPath $ordinary.Repository
    $ordinaryOutput = @(& $scriptPath 2>&1) -join "`n"
    Assert-PublisherInvariant (
        $ordinaryOutput -match 'PR_READY' -and
        $ordinaryOutput -match 'auto_merge=native-queue-squash' -and
        $ordinaryOutput -match 'assignment_state=CLOSED'
    ) "Ordinary PR did not enter native merge auto-merge without blocking by default. Output: $ordinaryOutput"
    $ordinaryMergeCalls = @($global:PublishAgentPrGhCalls | Where-Object {
        $_ -like 'pr merge *'
    })
    Assert-PublisherInvariant (
        $ordinaryMergeCalls.Count -eq 1 -and
        $ordinaryMergeCalls[0] -match '(?:^| )--auto(?: |$)' -and
        $ordinaryMergeCalls[0] -match '(?:^| )--squash(?: |$)' -and
        $ordinaryMergeCalls[0] -notmatch '(?:^| )--merge(?: |$)'
    ) 'Ordinary PR did not request exactly one native --auto --squash.'
    Assert-PublisherInvariant (
        @($global:PublishAgentPrPythonCalls | Where-Object {
            $_ -match '(?:^| )validate(?: |$)' -and
            $_ -match '--assignment [0-9a-f]{32}' -and
            $_ -match '--task-id /root/publish-test' -and
            $_ -match '--thread-id thread-publish-test' -and
            $_ -match ('--base ' + [regex]::Escape($global:PublishAgentPrBase) + '(?: |$)')
        }).Count -eq 1
    ) 'Ordinary PR did not validate the complete committed diff from exact origin/main inside the assignment write-set.'
    Assert-PublisherInvariant (
        @($global:PublishAgentPrGhCalls | Where-Object {
            $_ -like 'api --method POST *' -and $_ -match 'event_type=verify-fast-pr' -and
            $_ -match 'client_payload\[head_sha\]=[0-9a-f]{40}'
        }).Count -eq 1
    ) 'Ordinary PR did not request the trusted exact-head fast-green receiver.'

    # Add/delete/rename of formerly protected paths uses the exact same ordinary
    # PR route. CI-S1 has no manual control-plane exception.
    foreach ($case in @('add', 'delete', 'rename')) {
        $fixture = New-PublisherFixture -Name $case
        [void]$fixtures.Add($fixture)
        $branch = "codex/integration/protected-$case"
        Invoke-TestGit -Arguments @('-C', $fixture.Repository, 'checkout', '-b', $branch) | Out-Null
        if ($case -eq 'add') {
            Write-TestText -Path (Join-Path $fixture.Repository '.github\workflows\added.yml') -Value "name: added`n"
        }
        elseif ($case -eq 'delete') {
            Remove-Item -LiteralPath (Join-Path $fixture.Repository '.github\workflows\legacy.yml')
        }
        else {
            [void](New-Item -ItemType Directory -Path (Join-Path $fixture.Repository 'docs') -Force)
            Invoke-TestGit -Arguments @(
                '-C', $fixture.Repository, 'mv', '.github/workflows/legacy.yml', 'docs/legacy.yml'
            ) | Out-Null
        }
        Invoke-TestGit -Arguments @('-C', $fixture.Repository, 'add', '--all') | Out-Null
        Invoke-TestGit -Arguments @('-C', $fixture.Repository, 'commit', '-m', "protected $case") | Out-Null
        $global:PublishAgentPrHead = Invoke-TestGit -Arguments @(
            '-C', $fixture.Repository, 'rev-parse', 'HEAD^{commit}'
        )
        $global:PublishAgentPrBase = Invoke-TestGit -Arguments @(
            '-C', $fixture.Repository, 'rev-parse', 'refs/remotes/origin/main^{commit}'
        )
        $global:PublishAgentPrGhCalls.Clear()
        $global:PublishAgentPrPythonCalls.Clear()
        Set-Location -LiteralPath $fixture.Repository
        $output = @(& $scriptPath -NoWait 2>&1) -join "`n"
        Assert-PublisherInvariant (
            $output -match 'PR_READY' -and
            $output -match 'auto_merge=native-queue-squash' -and
            $output -notmatch 'MANUAL_CONTROL_PLANE'
        ) "Formerly protected $case did not use the ordinary route. Output: $output"
        $mergeCalls = @($global:PublishAgentPrGhCalls | Where-Object { $_ -like 'pr merge *' })
        Assert-PublisherInvariant (
            $mergeCalls.Count -eq 1 -and
            $mergeCalls[0] -match '(?:^| )--auto(?: |$)' -and
            $mergeCalls[0] -match '(?:^| )--squash(?: |$)' -and
            $mergeCalls[0] -match '(?:^| )--match-head-commit [0-9a-f]{40}(?: |$)' -and
            $mergeCalls[0] -notmatch '(?:^| )--merge(?: |$)' -and
            $mergeCalls[0] -notmatch '(?:^| )--disable-auto(?: |$)'
        ) "Sensitive $case did not request the same queue/squash auto-merge."
        Assert-PublisherInvariant (
            @($global:PublishAgentPrGhCalls | Where-Object { $_ -like 'pr create *' }).Count -eq 1
        ) "Formerly protected $case did not open exactly one PR."
        Assert-PublisherInvariant (
            @($global:PublishAgentPrGhCalls | Where-Object {
                $_ -like 'api --method POST *' -and $_ -match 'event_type=verify-fast-pr'
            }).Count -eq 1
        ) "Sensitive $case did not request exactly one trusted fast-green dispatch."
    }
}
finally {
    Set-Location -LiteralPath $previousLocation
    Remove-Item -Path Function:\gh -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\python -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrGhCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrHead -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrBase -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrMergedList -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrAssignmentHead -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrAssignmentBranch -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrAutoEnabled -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrPythonCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrMutateOnOwner -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrAssignmentId -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name PublishAgentPrAssignmentDigest -Scope Global -ErrorAction SilentlyContinue
    foreach ($fixture in $fixtures) {
        if (Test-Path -LiteralPath $fixture.Root) {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }
    }
}

Write-Output 'publish_agent_pr_test PASS'
