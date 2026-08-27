#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Contract {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

function Invoke-Git {
    param(
        [string]$Repository,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output | Out-String)"
    }
    return ($output | Out-String).Trim()
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)

    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Read-Json {
    param([string]$Path)

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-Json {
    param([string]$Path, [object]$Value)

    Write-Utf8 -Path $Path -Value (($Value | ConvertTo-Json -Depth 16) + "`n")
}

function Add-MainCommit {
    param(
        [string]$Repository,
        [string]$RevisionPath,
        [string]$Value,
        [string]$Message
    )

    Write-Utf8 -Path $RevisionPath -Value ($Value + "`n")
    Invoke-Git $Repository add --all | Out-Null
    Invoke-Git $Repository commit -m $Message | Out-Null
    Invoke-Git $Repository push origin main | Out-Null
    return Invoke-Git $Repository rev-parse 'HEAD^{commit}'
}

function Find-QueueEntry {
    param([object]$Queue, [string]$Sha)

    $matches = @(@($Queue.entries) | Where-Object {
        [string]$_.sha -ceq $Sha
    })
    Assert-Contract ($matches.Count -eq 1) "Queue entry is not unique: $Sha"
    return $matches[0]
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptUnderTest = Join-Path $repoRoot 'tools\sync_play_main.ps1'
$text = [IO.File]::ReadAllText($scriptUnderTest)
$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $scriptUnderTest,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
Assert-Contract ($parseErrors.Count -eq 0) 'sync_play_main.ps1 does not parse.'

foreach ($required in @(
    "'clone', '--bare', '--no-tags'",
    "'refs/heads/main:refs/remotes/origin/main'",
    "'rev-list', '--reverse', '--first-parent'",
    "'merge-base', '--is-ancestor'",
    "'lfs', 'fetch', 'origin', `$sha",
    "'lfs', 'checkout'",
    "'lfs', 'fsck', '--objects'",
    "'tools/build_underwater_map.py', '--check'",
    "'--export-release', `$ExportPreset, `$exportExe",
    "'-SourceRepositoryPath', `$candidateSource",
    "'-Full'",
    "'--play-main-smoke'",
    'PLAY_MAIN_SMOKE_CREATE=PASS',
    'PLAY_MAIN_SMOKE_MAP_LOAD=PASS',
    "result = 'EXPORT_BOOTSTRAP_REQUIRED'",
    "state = 'RUNNING'",
    "state = 'PENDING'",
    'ABORTED_RECOVERY',
    'current.json',
    "Join-Path `$buildsRoot `$sha",
    '[IO.File]::Replace',
    '[IO.Directory]::Move($attemptPath, $buildPath)',
    'INITIAL_BUILD_FAILED task remains installed',
    'SYNC_NO_PENDING',
    'PROMOTION_IN_DOUBT',
    'SYNC_BUSY another play-main builder is already running'
)) {
    Assert-Contract ($text.Contains($required)) `
        "Missing local-builder contract marker: $required"
}
foreach ($forbidden in @(
    "'reset'",
    "'clean'",
    "'--force'",
    "'worktree', 'remove', '--force'",
    '-InPlace',
    'Start-Job'
)) {
    Assert-Contract (-not $text.Contains($forbidden)) `
        "Unsafe local-builder marker found: $forbidden"
}
$registerOffset = $text.IndexOf('Register-ScheduledTask -TaskName')
$initialBuildOffset = $text.IndexOf('& $installedScriptPath -Mode RunOnce')
Assert-Contract ($registerOffset -ge 0 -and $initialBuildOffset -gt $registerOffset) `
    'Install does not register the scheduled task before the fallible initial build.'

$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $systemTemp (
    'codex-play-main-queue-test-' + [Guid]::NewGuid().ToString('N')
)
$origin = Join-Path $testRoot 'origin.git'
$source = Join-Path $testRoot 'authoring-source'
$mirror = Join-Path $testRoot 'latest-main.git'
$play = Join-Path $testRoot 'play-main'
$localData = Join-Path $testRoot 'local-data'
$fakeGodot = Join-Path $testRoot 'fake-godot.exe'
$godotLog = Join-Path $testRoot 'fake-godot.log'
$runnerLog = Join-Path $testRoot 'fake-runner.log'
$oldLocalAppData = $env:LOCALAPPDATA
$oldFailSha = $env:PLAY_MAIN_FAIL_SHA
$oldGodotLog = $env:PLAY_MAIN_GODOT_LOG
$oldRunnerLog = $env:PLAY_MAIN_RUNNER_LOG

try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null

    $fakeGodotSource = @'
using System;
using System.IO;
using System.Reflection;

public static class FakeGodot
{
    public static int Main(string[] args)
    {
        string log = Environment.GetEnvironmentVariable("PLAY_MAIN_GODOT_LOG");
        if (!String.IsNullOrEmpty(log))
        {
            File.AppendAllText(log, String.Join("|", args) + Environment.NewLine);
        }
        int exportIndex = Array.IndexOf(args, "--export-release");
        if (exportIndex >= 0)
        {
            if (exportIndex + 2 >= args.Length)
            {
                Console.Error.WriteLine("missing fake export destination");
                return 8;
            }
            string destination = args[exportIndex + 2];
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            File.Copy(Assembly.GetExecutingAssembly().Location, destination, true);
            Console.WriteLine("FAKE_GODOT_EXPORT=PASS");
            return 0;
        }
        if (Array.IndexOf(args, "--play-main-smoke") >= 0)
        {
            Console.WriteLine("PLAY_MAIN_SMOKE_CREATE=PASS");
            Console.WriteLine("PLAY_MAIN_SMOKE_MAP_LOAD=PASS");
            return 0;
        }
        Console.WriteLine("FAKE_GODOT_IDLE=PASS");
        return 0;
    }
}
'@
    $fakeGodotSourcePath = Join-Path $testRoot 'fake-godot.cs'
    Write-Utf8 -Path $fakeGodotSourcePath -Value $fakeGodotSource
    $windowsDirectory = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::Windows
    )
    $compiler = @(
        (Join-Path $windowsDirectory `
            'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $windowsDirectory `
            'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($compiler)) `
        'Cannot locate the Windows C# compiler for the fake Godot executable.'
    $compileOutput = & $compiler /nologo /target:exe "/out:$fakeGodot" `
        $fakeGodotSourcePath 2>&1
    Assert-Contract ($LASTEXITCODE -eq 0) `
        "Cannot compile the fake Godot executable: $($compileOutput | Out-String)"
    Assert-Contract (Test-Path -LiteralPath $fakeGodot -PathType Leaf) `
        'Cannot compile the fake Godot/exported application.'

    & git init --bare $origin | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize disposable origin.' }
    & git clone $origin $source | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot clone disposable authoring source.' }
    Invoke-Git $source checkout -b main | Out-Null
    Invoke-Git $source config user.email 'play-main-test@example.invalid' | Out-Null
    Invoke-Git $source config user.name 'Play Main Test' | Out-Null
    Invoke-Git $source config core.autocrlf false | Out-Null

    $mapTool = Join-Path $source `
        'underwater_map_workbench\tools\build_underwater_map.py'
    $mapManifest = Join-Path $source `
        'underwater_map_workbench\map_manifest.json'
    $exportSmokeContract = Join-Path $source `
        'scripts\core\PlayMainExportSmoke.gd'
    $runner = Join-Path $source 'tests\run_all_tests.ps1'
    $revision = Join-Path $source 'revision.txt'
    Write-Utf8 -Path $mapTool -Value @'
import sys
print("MOCK_MAP_CHECK=PASS")
sys.exit(0)
'@
    Write-Utf8 -Path $runner -Value @'
#requires -Version 5.1
param(
    [string]$GodotConsolePath,
    [string]$SourceRepositoryPath,
    [switch]$Full,
    [string]$RunReceiptOutputPath
)
$ErrorActionPreference = 'Stop'
if (-not $Full) { throw 'mock runner requires -Full' }
$sha = (& git -C $SourceRepositoryPath rev-parse 'HEAD^{commit}' 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sha -cnotmatch '^[0-9a-f]{40}$') {
    throw "mock runner cannot resolve exact candidate SHA: $sha"
}
$branch = (& git -C $SourceRepositoryPath branch --show-current 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($branch)) {
    throw "mock runner source is not detached: $branch"
}
if (-not [string]::IsNullOrWhiteSpace($env:PLAY_MAIN_RUNNER_LOG)) {
    [IO.File]::AppendAllText(
        $env:PLAY_MAIN_RUNNER_LOG,
        "$sha|$RunReceiptOutputPath`n",
        [Text.UTF8Encoding]::new($false)
    )
}
if ([string]$env:PLAY_MAIN_FAIL_SHA -ceq $sha) {
    [IO.File]::WriteAllText(
        $RunReceiptOutputPath,
        "status=FAIL`n",
        [Text.UTF8Encoding]::new($false)
    )
    throw "MOCK_FULL_FAILURE sha=$sha"
}
[IO.File]::WriteAllText(
    $RunReceiptOutputPath,
    "status=PASS`n",
    [Text.UTF8Encoding]::new($false)
)
Write-Output "MOCK_FULL_PASS sha=$sha godot=$GodotConsolePath"
'@
    Write-Utf8 -Path $mapManifest -Value "{}`n"
    Write-Utf8 -Path $exportSmokeContract -Value @'
extends Node

const CREATE_MARKER := "PLAY_MAIN_SMOKE_CREATE=PASS"
const MAP_LOAD_MARKER := "PLAY_MAIN_SMOKE_MAP_LOAD=PASS"
'@
    Write-Utf8 -Path (Join-Path $source 'project.godot') -Value @'
[application]
config/name="Play Main Builder Test"
'@
    Write-Utf8 -Path (Join-Path $source 'export_presets.cfg') -Value @'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
'@
    Write-Utf8 -Path $revision -Value "initial`n"
    Invoke-Git $source add --all | Out-Null
    Invoke-Git $source commit -m 'initial main' | Out-Null
    Invoke-Git $source push -u origin main | Out-Null
    $firstSha = Invoke-Git $source rev-parse 'HEAD^{commit}'

    $env:PLAY_MAIN_GODOT_LOG = $godotLog
    $env:PLAY_MAIN_RUNNER_LOG = $runnerLog
    $env:PLAY_MAIN_FAIL_SHA = ''

    $whatIfData = Join-Path $testRoot 'what-if-local-data'
    $whatIfMirror = Join-Path $testRoot 'what-if-mirror.git'
    $whatIfPlay = Join-Path $testRoot 'what-if-play'
    $sourceHeadBeforeWhatIf = Invoke-Git $source rev-parse 'HEAD^{commit}'
    $sourceStatusBeforeWhatIf = Invoke-Git $source status --porcelain=v1 `
        --untracked-files=all
    $env:LOCALAPPDATA = $whatIfData
    $whatIfOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -LatestPath $whatIfMirror `
        -PlayPath $whatIfPlay -GodotConsolePath $fakeGodot -WhatIf
    Assert-Contract (($whatIfOutput | Out-String) -match 'PLAN mode=RunOnce') `
        'RunOnce -WhatIf did not report a plan.'
    foreach ($unexpected in @($whatIfData, $whatIfMirror, $whatIfPlay)) {
        Assert-Contract (-not (Test-Path -LiteralPath $unexpected)) `
            "RunOnce -WhatIf mutated filesystem state: $unexpected"
    }
    Assert-Contract (
        (Invoke-Git $source rev-parse 'HEAD^{commit}') -ceq $sourceHeadBeforeWhatIf -and
        (Invoke-Git $source status --porcelain=v1 --untracked-files=all) `
            -ceq $sourceStatusBeforeWhatIf
    ) 'RunOnce -WhatIf changed the bootstrap repository.'

    $env:LOCALAPPDATA = $localData
    $firstOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -LatestPath $mirror -PlayPath $play `
        -GodotConsolePath $fakeGodot
    Assert-Contract (($firstOutput | Out-String) -match "SYNC_BUILT sha=$firstSha") `
        'Initial exact-main build did not pass.'
    $currentPath = Join-Path $play 'current.json'
    $queuePath = Join-Path $localData 'OstatniPomost\play-main\queue.json'
    $statusPath = Join-Path $localData 'OstatniPomost\play-main\status.json'
    $alertPath = Join-Path $localData 'OstatniPomost\play-main\alert.json'
    $current = Read-Json $currentPath
    Assert-Contract ([string]$current.sha -ceq $firstSha) `
        'Initial current pointer does not contain exact first SHA.'
    Assert-Contract (
        [string]$current.build_path -ceq (Join-Path $play "builds\$firstSha") -and
        (Test-Path -LiteralPath (Join-Path $current.build_path 'build.json') `
            -PathType Leaf) -and
        (Test-Path -LiteralPath (
            Join-Path $current.build_path 'export\OstatniPomost.exe'
        ) -PathType Leaf)
    ) 'Initial immutable build directory is incomplete.'

    Assert-Contract ((Invoke-Git $mirror rev-parse --is-bare-repository) -ceq 'true') `
        'Trusted latest-main source is not a bare standalone clone.'
    $sourceCommon = [IO.Path]::GetFullPath((
        Invoke-Git $source rev-parse --path-format=absolute --git-common-dir
    )).TrimEnd('\', '/')
    $mirrorCommon = [IO.Path]::GetFullPath((
        Invoke-Git $mirror rev-parse --path-format=absolute --git-common-dir
    )).TrimEnd('\', '/')
    Assert-Contract (-not [string]::Equals(
        $sourceCommon,
        $mirrorCommon,
        [StringComparison]::OrdinalIgnoreCase
    )) 'Trusted source mirror shares authoring common-dir.'

    $secondSha = Add-MainCommit -Repository $source -RevisionPath $revision `
        -Value 'second' -Message 'second main'
    $thirdSha = Add-MainCommit -Repository $source -RevisionPath $revision `
        -Value 'third' -Message 'third main'
    $currentBeforeFailure = [IO.File]::ReadAllText($currentPath)
    $env:PLAY_MAIN_FAIL_SHA = $secondSha
    $failed = $false
    try {
        & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
            -LatestPath $mirror -PlayPath $play `
            -GodotConsolePath $fakeGodot | Out-Null
    }
    catch { $failed = $true }
    Assert-Contract $failed 'Mocked full-runner failure did not fail the build.'
    $currentAfterContinuedQueue = Read-Json $currentPath
    Assert-Contract (
        [string]$currentAfterContinuedQueue.sha -ceq $thirdSha -and
        [string]$currentAfterContinuedQueue.sha -cne $secondSha
    ) 'A failed SHA blocked the later independent main SHA or became current.'
    $queue = Read-Json $queuePath
    Assert-Contract (@($queue.entries).Count -eq 3) `
        'Two main commits were not durably queued in one fetch.'
    Assert-Contract (
        [string]$queue.entries[0].sha -ceq $firstSha -and
        [string]$queue.entries[1].sha -ceq $secondSha -and
        [string]$queue.entries[2].sha -ceq $thirdSha
    ) 'Persistent queue skipped or reordered a main SHA.'
    $secondEntry = Find-QueueEntry $queue $secondSha
    $thirdEntry = Find-QueueEntry $queue $thirdSha
    Assert-Contract (
        [string]$secondEntry.state -ceq 'FAIL' -and
        [string]$thirdEntry.state -ceq 'PASS'
    ) 'Queue did not retain the failed SHA while completing the later main SHA.'
    $failedReceipt = [string]$secondEntry.attempts[0].receipt_path
    Assert-Contract (Test-Path -LiteralPath $failedReceipt -PathType Leaf) `
        'Failed attempt receipt was not retained.'
    $status = Read-Json $statusPath
    $alert = Read-Json $alertPath
    Assert-Contract (
        [string]$status.result -ceq 'PASS' -and
        [string]$status.target_sha -ceq $thirdSha -and
        [bool]$alert.active -and [string]$alert.sha -ceq $secondSha
    ) 'Later PASS did not preserve the earlier exact-SHA failure alert.'

    $waitingOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -LatestPath $mirror -PlayPath $play `
        -GodotConsolePath $fakeGodot
    Assert-Contract (($waitingOutput | Out-String) -match 'SYNC_NO_PENDING') `
        'Failed SHA retried without explicit -RetryFailed.'
    $waitingQueue = Read-Json $queuePath
    Assert-Contract (@((Find-QueueEntry $waitingQueue $secondSha).attempts).Count -eq 1) `
        'Bounded waiting created another attempt receipt.'

    $env:PLAY_MAIN_FAIL_SHA = ''
    $retryOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -LatestPath $mirror -PlayPath $play `
        -GodotConsolePath $fakeGodot -RetryFailed
    $retryText = $retryOutput | Out-String
    Assert-Contract (
        $retryText -match "SYNC_BUILT sha=$secondSha" -and
        $retryText -notmatch "SYNC_BUILT sha=$thirdSha"
    ) 'Retry did not process only the explicitly retried failed SHA.'
    $queue = Read-Json $queuePath
    $secondEntry = Find-QueueEntry $queue $secondSha
    Assert-Contract (
        [string]$secondEntry.state -ceq 'PASS' -and
        @($secondEntry.attempts).Count -eq 2 -and
        [string]$secondEntry.attempts[0].attempt_id -cne `
            [string]$secondEntry.attempts[1].attempt_id -and
        [string]$secondEntry.attempts[0].receipt_path -cne `
            [string]$secondEntry.attempts[1].receipt_path
    ) 'Retry did not preserve unique immutable attempt receipts.'
    $current = Read-Json $currentPath
    Assert-Contract ([string]$current.sha -ceq $thirdSha) `
        'Retry of an older SHA moved current backwards from the latest PASS.'
    foreach ($sha in @($secondSha, $thirdSha)) {
        Assert-Contract (Test-Path -LiteralPath (Join-Path $play "builds\$sha") `
            -PathType Container) "Immutable build is missing: $sha"
    }

    $fourthSha = Add-MainCommit -Repository $source -RevisionPath $revision `
        -Value 'fourth' -Message 'fourth main'
    $env:PLAY_MAIN_FAIL_SHA = $fourthSha
    try {
        & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
            -LatestPath $mirror -PlayPath $play `
            -GodotConsolePath $fakeGodot | Out-Null
        throw 'Expected fourth SHA failure did not occur.'
    }
    catch {
        if ($_.Exception.Message -eq 'Expected fourth SHA failure did not occur.') {
            throw
        }
    }
    $queue = Read-Json $queuePath
    $fourthEntry = Find-QueueEntry $queue $fourthSha
    $interruptedAttempt = $fourthEntry.attempts[-1]
    $fourthEntry.state = 'RUNNING'
    $fourthEntry.active_attempt_id = [string]$interruptedAttempt.attempt_id
    $fourthEntry.active_attempt_path = [string]$interruptedAttempt.attempt_path
    $interruptedAttempt.state = 'RUNNING'
    $interruptedAttempt.terminal_at = ''
    Write-Json -Path $queuePath -Value $queue
    $env:PLAY_MAIN_FAIL_SHA = ''
    $restartOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -LatestPath $mirror -PlayPath $play `
        -GodotConsolePath $fakeGodot
    Assert-Contract (
        ($restartOutput | Out-String) -match "SYNC_RECOVERED sha=$fourthSha" -and
        ($restartOutput | Out-String) -match "SYNC_BUILT sha=$fourthSha"
    ) 'Restart did not resume the first nonterminal SHA.'
    $queue = Read-Json $queuePath
    $fourthEntry = Find-QueueEntry $queue $fourthSha
    Assert-Contract (
        [string]$fourthEntry.state -ceq 'PASS' -and
        @($fourthEntry.attempts).Count -eq 2 -and
        [string]$fourthEntry.attempts[0].state -ceq 'ABORTED_RECOVERY' -and
        [string]$fourthEntry.attempts[1].state -ceq 'PASS'
    ) 'Restart recovery lost the interrupted attempt or reused its receipt.'
    Assert-Contract ([string](Read-Json $currentPath).sha -ceq $fourthSha) `
        'Recovered PASS did not promote exact fourth SHA.'

    [IO.File]::Delete((Join-Path $source 'export_presets.cfg'))
    $fifthSha = Add-MainCommit -Repository $source -RevisionPath $revision `
        -Value 'missing-export-preset' -Message 'remove export preset'
    $currentBeforeBootstrapFailure = [IO.File]::ReadAllText($currentPath)
    $bootstrapFailed = $false
    try {
        & $scriptUnderTest -Mode RunOnce -SourceRepository $source `
            -LatestPath $mirror -PlayPath $play `
            -GodotConsolePath $fakeGodot | Out-Null
    }
    catch { $bootstrapFailed = $true }
    Assert-Contract $bootstrapFailed `
        'Missing export_presets.cfg did not stop the exact SHA.'
    Assert-Contract (
        [IO.File]::ReadAllText($currentPath) -ceq $currentBeforeBootstrapFailure
    ) 'EXPORT_BOOTSTRAP_REQUIRED changed current.json.'
    $bootstrapStatus = Read-Json $statusPath
    $bootstrapAlert = Read-Json $alertPath
    $queue = Read-Json $queuePath
    Assert-Contract (
        [string]$bootstrapStatus.result -ceq 'EXPORT_BOOTSTRAP_REQUIRED' -and
        [string]$bootstrapStatus.stage -ceq 'export-preflight' -and
        [string]$bootstrapAlert.result -ceq 'EXPORT_BOOTSTRAP_REQUIRED' -and
        [bool]$bootstrapAlert.active -and
        [string](Find-QueueEntry $queue $fifthSha).state -ceq `
            'EXPORT_BOOTSTRAP_REQUIRED'
    ) 'Missing export preset did not publish bootstrap status and alert.'

    Write-Utf8 -Path (Join-Path $source 'export_presets.cfg') -Value @'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
'@
    $sixthSha = Add-MainCommit -Repository $source -RevisionPath $revision `
        -Value 'restore-export-preset' -Message 'restore export preset'
    $sixthOutput = & $scriptUnderTest -Mode RunOnce `
        -SourceRepository $source -LatestPath $mirror -PlayPath $play `
        -GodotConsolePath $fakeGodot
    Assert-Contract (($sixthOutput | Out-String) -match "SYNC_BUILT sha=$sixthSha") `
        'A prior export bootstrap failure blocked a later corrected main SHA.'
    $queue = Read-Json $queuePath
    Assert-Contract (
        [string](Find-QueueEntry $queue $fifthSha).state -ceq `
            'EXPORT_BOOTSTRAP_REQUIRED' -and
        [string](Find-QueueEntry $queue $sixthSha).state -ceq 'PASS' -and
        [string](Read-Json $currentPath).sha -ceq $sixthSha
    ) 'Corrected main SHA was not promoted while retaining prior failure evidence.'

    $lockPath = Join-Path $localData 'OstatniPomost\play-main\sync.lock'
    $lock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    try {
        $busyOutput = & $scriptUnderTest -Mode RunOnce `
            -SourceRepository $source -LatestPath $mirror -PlayPath $play `
            -GodotConsolePath $fakeGodot
        Assert-Contract (($busyOutput | Out-String) -match 'SYNC_BUSY') `
            'Concurrent invocation did not exit through the single builder lock.'
    }
    finally {
        $lock.Dispose()
    }

    $runnerLines = @([IO.File]::ReadAllLines($runnerLog))
    Assert-Contract ($runnerLines.Count -ge 7) `
        'Mock full runner did not observe all attempts.'
    foreach ($line in $runnerLines) {
        $parts = $line -split '\|', 2
        Assert-Contract (
            $parts.Count -eq 2 -and $parts[0] -match '^[0-9a-f]{40}$' -and
            -not [string]::IsNullOrWhiteSpace($parts[1])
        ) "Mock runner log lost exact SHA or unique receipt: $line"
    }
    $godotLines = @([IO.File]::ReadAllLines($godotLog))
    Assert-Contract (
        @($godotLines | Where-Object { $_ -match '--export-release' }).Count -ge 7 -and
        @($godotLines | Where-Object { $_ -match '--play-main-smoke' }).Count -ge 5
    ) 'Mock Godot did not exercise both real export and exported-EXE smoke paths.'

    $worktrees = Invoke-Git $mirror worktree list --porcelain
    Assert-Contract ($worktrees -notmatch '(?m)^worktree .*[\\/]attempts[\\/]') `
        'A candidate worktree remained registered after terminal attempts.'
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if ($null -eq $oldFailSha) {
        Remove-Item Env:PLAY_MAIN_FAIL_SHA -ErrorAction SilentlyContinue
    }
    else { $env:PLAY_MAIN_FAIL_SHA = $oldFailSha }
    if ($null -eq $oldGodotLog) {
        Remove-Item Env:PLAY_MAIN_GODOT_LOG -ErrorAction SilentlyContinue
    }
    else { $env:PLAY_MAIN_GODOT_LOG = $oldGodotLog }
    if ($null -eq $oldRunnerLog) {
        Remove-Item Env:PLAY_MAIN_RUNNER_LOG -ErrorAction SilentlyContinue
    }
    else { $env:PLAY_MAIN_RUNNER_LOG = $oldRunnerLog }

    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith(
        $systemTemp + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    ) -and (Test-Path -LiteralPath $resolvedTestRoot -PathType Container)) {
        foreach ($file in [IO.Directory]::EnumerateFiles(
            $resolvedTestRoot,
            '*',
            [IO.SearchOption]::AllDirectories
        )) {
            [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
        }
        $directories = @([IO.Directory]::EnumerateDirectories(
            $resolvedTestRoot,
            '*',
            [IO.SearchOption]::AllDirectories
        )) | Sort-Object Length -Descending
        foreach ($directory in $directories) {
            [IO.File]::SetAttributes($directory, [IO.FileAttributes]::Directory)
        }
        [IO.Directory]::Delete($resolvedTestRoot, $true)
    }
}

Write-Output 'sync_play_main_test: PASS'
