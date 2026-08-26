#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$GodotConsolePath,

    [string]$TargetA = "tests/workbench_boundary_test.gd",

    [string]$TargetB = "tests/campaign_map_contract_test.gd",

    [string]$EvidenceRoot,

    [ValidateRange(1, 3600)]
    [int]$ImportTimeoutSeconds = 600,

    [ValidateRange(1, 3600)]
    [int]$TestTimeoutSeconds = 180,

    [ValidateRange(30, 7200)]
    [int]$AcceptanceTimeoutSeconds = 1800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Assert-AcceptanceInvariant {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Text)

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return [System.BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

function ConvertTo-NativeProcessArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]'\') {
            $backslashCount += 1
            continue
        }
        if ($character -eq [char]'"') {
            if ($backslashCount -gt 0) {
                [void]$builder.Append([char]'\', $backslashCount * 2)
            }
            [void]$builder.Append('\"')
        }
        else {
            if ($backslashCount -gt 0) {
                [void]$builder.Append([char]'\', $backslashCount)
            }
            [void]$builder.Append($character)
        }
        $backslashCount = 0
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append([char]'\', $backslashCount * 2)
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Set-SafeGitChildEnvironment {
    param([System.Diagnostics.ProcessStartInfo]$StartInfo)

    # Never let caller-scoped repository/index/object overrides redirect a
    # supposedly temporary Git operation back into the real repository. The
    # same sanitized environment is inherited by both runner children.
    $redirectingNames = @(
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_COMMON_DIR",
        "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_QUARANTINE_PATH",
        "GIT_NAMESPACE",
        "GIT_CONFIG_PARAMETERS",
        "GIT_CONFIG_COUNT",
        "GIT_PREFIX",
        "GIT_SUPER_PREFIX",
        "GIT_REPLACE_REF_BASE"
    )
    foreach ($name in $redirectingNames) {
        [void]$StartInfo.EnvironmentVariables.Remove($name)
    }
    foreach ($name in @($StartInfo.EnvironmentVariables.Keys)) {
        if ([string]$name -match '^GIT_CONFIG_(?:KEY|VALUE)_[0-9]+$') {
            [void]$StartInfo.EnvironmentVariables.Remove([string]$name)
        }
    }
    $StartInfo.EnvironmentVariables["GIT_OPTIONAL_LOCKS"] = "0"
}

function Stop-AcceptanceProcessTree {
    param([AllowNull()][System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }
    try {
        if ($Process.HasExited) {
            return
        }
    }
    catch {
        return
    }

    try {
        $Process.Kill($true)
    }
    catch {
        try {
            $taskkill = Get-Command -Name "taskkill.exe" -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $taskkill) {
                & $taskkill.Source /PID $Process.Id /T /F *> $null
            }
        }
        catch {
            # The final direct kill below remains the PowerShell 5.1 fallback.
        }
        try {
            if (-not $Process.HasExited) {
                $Process.Kill()
            }
        }
        catch {
            # The caller will still fail the acceptance if the process survives.
        }
    }
    try {
        [void]$Process.WaitForExit(30000)
    }
    catch {
        # Preserve the original acceptance failure; cleanup remains path-scoped.
    }
}

function Invoke-NativeProcessCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [int[]]$AllowedExitCodes = @(0)
    )

    $process = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = (@($Arguments) | ForEach-Object {
            ConvertTo-NativeProcessArgument -Argument ([string]$_)
        }) -join " "
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        Set-SafeGitChildEnvironment -StartInfo $startInfo
        try {
            $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        }
        catch {
            # Older PowerShell/.NET combinations still expose decoded text.
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Could not start '$FilePath'."
        }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-AcceptanceProcessTree -Process $process
            throw "Process '$FilePath' timed out after $TimeoutSeconds seconds."
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($AllowedExitCodes -notcontains $process.ExitCode) {
            throw (
                "Process '$FilePath' failed with exit code $($process.ExitCode). " +
                "stdout='$($output.Trim())' stderr='$($errorText.Trim())'"
            )
        }
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Output = [string]$output
            Error = [string]$errorText
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

$gitCommand = Get-Command -Name "git" -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $gitCommand) {
    throw "Git is required for the linked-worktree acceptance."
}
$gitExecutable = $gitCommand.Source

function Invoke-GitCapture {
    param(
        [string]$RepositoryRoot,
        [string[]]$Arguments,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [int[]]$AllowedExitCodes = @(0)
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]"\/")
    $safeDirectory = $normalizedRoot.Replace('\', '/')
    return Invoke-NativeProcessCapture `
        -FilePath $script:gitExecutable `
        -Arguments (@("-c", "safe.directory=$safeDirectory", "-C", $normalizedRoot) + @($Arguments)) `
        -WorkingDirectory $normalizedRoot `
        -TimeoutSeconds $TimeoutSeconds `
        -AllowedExitCodes $AllowedExitCodes
}

function Resolve-GitReportedPath {
    param(
        [string]$RepositoryRoot,
        [string]$ReportedPath
    )

    $trimmed = $ReportedPath.Trim()
    if ([System.IO.Path]::IsPathRooted($trimmed)) {
        return [System.IO.Path]::GetFullPath($trimmed).TrimEnd([char[]]"\/")
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $trimmed)).TrimEnd([char[]]"\/")
}

function Test-PathInsideRoot {
    param(
        [string]$CandidatePath,
        [string]$RootPath,
        [switch]$AllowEqual
    )

    $candidate = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd([char[]]"\/")
    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]"\/")
    if ($AllowEqual -and [string]::Equals($candidate, $root, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-GitClosurePaths {
    param([string]$RepositoryRoot)

    $normalizedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]"\/")
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $query = Invoke-GitCapture `
        -RepositoryRoot $normalizedRoot `
        -Arguments @("ls-files", "--cached", "--others", "--exclude-standard", "-z")

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $paths = [System.Collections.Generic.List[string]]::new()
    $rawPaths = $query.Output.Split([char[]]@([char]0), [System.StringSplitOptions]::None)
    foreach ($rawPath in $rawPaths) {
        if ([string]::IsNullOrEmpty($rawPath)) {
            continue
        }
        $relativePath = $rawPath.Replace('\', '/')
        $segments = @($relativePath.Split('/'))
        if ([System.IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -eq ".git" -or
            $relativePath.StartsWith(".git/", [StringComparison]::OrdinalIgnoreCase) -or
            $segments -contains "..") {
            throw "Git-closed snapshot path escaped or entered Git metadata: '$relativePath'."
        }
        $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Git-closed snapshot path escaped source root: '$relativePath'."
        }
        if (-not $seen.Add($relativePath)) {
            throw "Git-closed snapshot contains duplicate path '$relativePath'."
        }
        $paths.Add($relativePath)
    }

    $result = [string[]]$paths.ToArray()
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Assert-NoReparsePointComponents {
    param(
        [string]$RootPath,
        [string]$RelativePath
    )

    $cursor = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]"\/")
    $rootItem = Get-Item -LiteralPath $cursor -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Snapshot root is a reparse point: '$cursor'."
    }
    foreach ($segment in @($RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar).Split(
        [char[]]@([System.IO.Path]::DirectorySeparatorChar),
        [System.StringSplitOptions]::None
    ))) {
        $cursor = Join-Path $cursor $segment
        if (-not (Test-Path -LiteralPath $cursor)) {
            break
        }
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Git-closed snapshot traverses reparse point '$cursor'."
        }
    }
}

function Get-ClosureFingerprint {
    param(
        [string]$RootPath,
        [string[]]$Paths
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]"\/")
    $rootPrefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    $records = [System.Collections.Generic.List[string]]::new()
    $materializedRecords = [System.Collections.Generic.List[string]]::new()
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($relativePath in @($Paths)) {
        Assert-NoReparsePointComponents -RootPath $normalizedRoot -RelativePath $relativePath
        $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Fingerprint path escaped '$normalizedRoot': '$relativePath'."
        }
        $pathToken = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($relativePath))
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            $records.Add("M`t$pathToken")
            $entries.Add([pscustomobject]@{
                RelativePath = $relativePath
                Exists = $false
                Length = 0L
                Sha256 = ""
            })
            continue
        }
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Git-closed snapshot entry is not a file: '$relativePath'."
        }
        $item = Get-Item -LiteralPath $absolutePath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Git-closed acceptance does not copy reparse-point entries: '$relativePath'."
        }
        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToLowerInvariant()
        $record = "F`t$pathToken`t$($item.Length)`t$sha256"
        $records.Add($record)
        $materializedRecords.Add($record)
        $entries.Add([pscustomobject]@{
            RelativePath = $relativePath
            Exists = $true
            Length = [long]$item.Length
            Sha256 = $sha256
        })
    }

    return [pscustomobject]@{
        Digest = Get-Sha256Text -Text ([string]::Join("`n", $records))
        MaterializedDigest = Get-Sha256Text -Text ([string]::Join("`n", $materializedRecords))
        PathCount = @($Paths).Count
        FileCount = @($entries | Where-Object Exists).Count
        MissingCount = @($entries | Where-Object { -not $_.Exists }).Count
        Paths = @($Paths)
        Entries = @($entries)
    }
}

function Get-GitRepositoryAudit {
    param([string]$RepositoryRoot)

    $normalizedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]"\/")
    $head = (Invoke-GitCapture -RepositoryRoot $normalizedRoot -Arguments @("rev-parse", "--verify", "HEAD")).Output.Trim().ToLowerInvariant()
    $tree = (Invoke-GitCapture -RepositoryRoot $normalizedRoot -Arguments @("rev-parse", "--verify", "HEAD^{tree}")).Output.Trim().ToLowerInvariant()
    $status = (Invoke-GitCapture -RepositoryRoot $normalizedRoot -Arguments @("status", "--porcelain=v1", "--untracked-files=all", "-z")).Output
    $headRef = (Invoke-GitCapture `
        -RepositoryRoot $normalizedRoot `
        -Arguments @("symbolic-ref", "-q", "HEAD") `
        -AllowedExitCodes @(0, 1)).Output.Trim()
    $refs = (Invoke-GitCapture `
        -RepositoryRoot $normalizedRoot `
        -Arguments @("for-each-ref", "--sort=refname", "--format=%(refname)%09%(objectname)%09%(objecttype)%09%(symref)", "refs")).Output
    $commonDirText = (Invoke-GitCapture -RepositoryRoot $normalizedRoot -Arguments @("rev-parse", "--git-common-dir")).Output
    $topLevel = (Invoke-GitCapture -RepositoryRoot $normalizedRoot -Arguments @("rev-parse", "--show-toplevel")).Output.Trim()
    $paths = @(Get-GitClosurePaths -RepositoryRoot $normalizedRoot)
    $closure = Get-ClosureFingerprint -RootPath $normalizedRoot -Paths $paths

    Assert-AcceptanceInvariant `
        -Condition ($head -match '^[0-9a-f]{40,64}$' -and $tree -match '^[0-9a-f]{40,64}$') `
        -Message "Git audit did not return valid HEAD/tree IDs."

    return [pscustomobject]@{
        Root = [System.IO.Path]::GetFullPath($topLevel).TrimEnd([char[]]"\/")
        CommonDir = Resolve-GitReportedPath -RepositoryRoot $normalizedRoot -ReportedPath $commonDirText
        Head = $head
        Tree = $tree
        HeadRef = $headRef
        StatusDigest = Get-Sha256Text -Text $status
        WorktreeClean = [string]::IsNullOrEmpty($status)
        RefsDigest = Get-Sha256Text -Text ($headRef + "`n" + $refs)
        Closure = $closure
    }
}

function Get-ClosureDifferenceSummary {
    param(
        [pscustomobject]$BeforeClosure,
        [pscustomobject]$AfterClosure,
        [int]$MaximumEntries = 12
    )

    $beforeByPath = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $afterByPath = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $allPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($BeforeClosure.Entries)) {
        $beforeByPath[[string]$entry.RelativePath] = $entry
        [void]$allPaths.Add([string]$entry.RelativePath)
    }
    foreach ($entry in @($AfterClosure.Entries)) {
        $afterByPath[[string]$entry.RelativePath] = $entry
        [void]$allPaths.Add([string]$entry.RelativePath)
    }
    $orderedPaths = [string[]]@($allPaths)
    [Array]::Sort($orderedPaths, [StringComparer]::Ordinal)
    $differences = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $orderedPaths) {
        $beforeEntry = if ($beforeByPath.ContainsKey($path)) { $beforeByPath[$path] } else { $null }
        $afterEntry = if ($afterByPath.ContainsKey($path)) { $afterByPath[$path] } else { $null }
        $beforeToken = if ($null -eq $beforeEntry) {
            "ABSENT"
        }
        elseif (-not $beforeEntry.Exists) {
            "MISSING"
        }
        else {
            "F:$($beforeEntry.Length):$($beforeEntry.Sha256)"
        }
        $afterToken = if ($null -eq $afterEntry) {
            "ABSENT"
        }
        elseif (-not $afterEntry.Exists) {
            "MISSING"
        }
        else {
            "F:$($afterEntry.Length):$($afterEntry.Sha256)"
        }
        if ($beforeToken -cne $afterToken) {
            $differences.Add("$path [$beforeToken -> $afterToken]")
            if ($differences.Count -ge $MaximumEntries) {
                break
            }
        }
    }
    if ($differences.Count -eq 0) {
        return "no per-path difference found"
    }
    return [string]::Join("; ", $differences)
}

function Assert-RepositoryAuditUnchanged {
    param(
        [pscustomobject]$Before,
        [pscustomobject]$After,
        [string]$Label
    )

    foreach ($propertyName in @(
        "Root", "CommonDir", "Head", "Tree", "HeadRef", "StatusDigest", "WorktreeClean", "RefsDigest"
    )) {
        if ([string]$Before.$propertyName -cne [string]$After.$propertyName) {
            throw "$Label changed '$propertyName': before='$($Before.$propertyName)' after='$($After.$propertyName)'."
        }
    }
    foreach ($propertyName in @("Digest", "MaterializedDigest", "PathCount", "FileCount", "MissingCount")) {
        if ([string]$Before.Closure.$propertyName -cne [string]$After.Closure.$propertyName) {
            $differenceSummary = Get-ClosureDifferenceSummary -BeforeClosure $Before.Closure -AfterClosure $After.Closure
            throw "$Label changed closure '$propertyName': before='$($Before.Closure.$propertyName)' after='$($After.Closure.$propertyName)'; paths: $differenceSummary."
        }
    }
}

function Copy-ClosedSnapshot {
    param(
        [string]$SourceRoot,
        [pscustomobject]$SourceAuditBefore,
        [string]$DestinationRoot
    )

    [void](New-Item -ItemType Directory -Path $DestinationRoot)
    $destinationPrefix = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    foreach ($entry in @($SourceAuditBefore.Closure.Entries | Where-Object Exists)) {
        $sourcePath = Join-Path $SourceRoot $entry.RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $DestinationRoot $entry.RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
        if (-not $destinationPath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Snapshot copy escaped temporary repository: '$($entry.RelativePath)'."
        }
        $destinationDirectory = [System.IO.Path]::GetDirectoryName($destinationPath)
        if (-not [string]::IsNullOrWhiteSpace($destinationDirectory)) {
            [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)
        }
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    $sourceAuditAfter = Get-GitRepositoryAudit -RepositoryRoot $SourceRoot
    Assert-RepositoryAuditUnchanged `
        -Before $SourceAuditBefore `
        -After $sourceAuditAfter `
        -Label "Real source while closing the temporary snapshot"
    $destinationClosure = Get-ClosureFingerprint `
        -RootPath $DestinationRoot `
        -Paths @($SourceAuditBefore.Closure.Paths)
    Assert-AcceptanceInvariant `
        -Condition ($destinationClosure.Digest -eq $SourceAuditBefore.Closure.Digest -and
            $destinationClosure.PathCount -eq $SourceAuditBefore.Closure.PathCount -and
            $destinationClosure.FileCount -eq $SourceAuditBefore.Closure.FileCount -and
            $destinationClosure.MissingCount -eq $SourceAuditBefore.Closure.MissingCount) `
        -Message "Temporary repository copy does not match the exact Git-closed source snapshot."
    return $destinationClosure
}

function Copy-ExactMaterializedSnapshot {
    param(
        [string]$SourceRoot,
        [pscustomobject]$SourceClosure,
        [string]$DestinationRoot
    )

    $normalizedSource = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd([char[]]"\/")
    $normalizedDestination = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd([char[]]"\/")
    $destinationPrefix = $normalizedDestination + [System.IO.Path]::DirectorySeparatorChar
    $destinationRootItem = Get-Item -LiteralPath $normalizedDestination -Force
    if (($destinationRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to materialize an exact snapshot through reparse-point destination '$normalizedDestination'."
    }

    $materializedEntries = @($SourceClosure.Entries | Where-Object Exists)
    $materializedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $materializedEntries) {
        $relativePath = [string]$entry.RelativePath
        $materializedPaths.Add($relativePath)
        $nativeRelativePath = $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $normalizedSource $nativeRelativePath))
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $normalizedDestination $nativeRelativePath))
        if (-not $destinationPath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Materialized snapshot path escaped its linked worktree: '$relativePath'."
        }
        $sourceItem = Get-Item -LiteralPath $sourcePath -Force
        if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
            [long]$sourceItem.Length -ne [long]$entry.Length -or
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.Sha256) {
            throw "Temporary materialized source changed before linked-worktree closure: '$relativePath'."
        }

        $cursor = $normalizedDestination
        $segments = @($nativeRelativePath.Split(
            [char[]]@([System.IO.Path]::DirectorySeparatorChar),
            [System.StringSplitOptions]::None
        ))
        for ($segmentIndex = 0; $segmentIndex -lt $segments.Count - 1; $segmentIndex++) {
            $cursor = Join-Path $cursor $segments[$segmentIndex]
            if (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $cursor)
            }
            $cursorItem = Get-Item -LiteralPath $cursor -Force
            if (($cursorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to materialize an exact snapshot through reparse point '$cursor'."
            }
        }
        if (Test-Path -LiteralPath $destinationPath) {
            $destinationItem = Get-Item -LiteralPath $destinationPath -Force
            if (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to overwrite reparse-point worktree entry '$destinationPath'."
            }
        }
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    $destinationClosure = Get-ClosureFingerprint `
        -RootPath $normalizedDestination `
        -Paths ([string[]]$materializedPaths.ToArray())
    Assert-AcceptanceInvariant `
        -Condition ($destinationClosure.Digest -eq $SourceClosure.MaterializedDigest -and
            $destinationClosure.PathCount -eq $materializedEntries.Count -and
            $destinationClosure.FileCount -eq $materializedEntries.Count -and
            $destinationClosure.MissingCount -eq 0) `
        -Message "Linked worktree does not reproduce the byte-exact materialized Git-closed snapshot."
    return $destinationClosure
}

function Normalize-TargetPath {
    param(
        [string]$Target,
        [string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "$ParameterName cannot be empty."
    }
    $normalized = $Target.Trim().Replace('\', '/')
    $segments = @($normalized.Split('/'))
    if ([System.IO.Path]::IsPathRooted($normalized) -or
        $normalized.StartsWith("/", [StringComparison]::Ordinal) -or
        $segments -contains ".." -or
        $segments -contains "." -or
        $segments -contains "" -or
        $normalized.Contains(":") -or
        [System.IO.Path]::GetExtension($normalized).ToLowerInvariant() -notin @(".gd", ".tscn")) {
        throw "$ParameterName must be a project-relative .gd or .tscn path without traversal: '$Target'."
    }
    return $normalized
}

function Get-WorktreeState {
    param([string]$WorktreeRoot)

    $head = (Invoke-GitCapture -RepositoryRoot $WorktreeRoot -Arguments @("rev-parse", "--verify", "HEAD")).Output.Trim().ToLowerInvariant()
    $tree = (Invoke-GitCapture -RepositoryRoot $WorktreeRoot -Arguments @("rev-parse", "--verify", "HEAD^{tree}")).Output.Trim().ToLowerInvariant()
    $status = (Invoke-GitCapture -RepositoryRoot $WorktreeRoot -Arguments @("status", "--porcelain=v1", "--untracked-files=all", "-z")).Output
    $commonDirText = (Invoke-GitCapture -RepositoryRoot $WorktreeRoot -Arguments @("rev-parse", "--git-common-dir")).Output
    $paths = @(Get-GitClosurePaths -RepositoryRoot $WorktreeRoot)
    return [pscustomobject]@{
        Head = $head
        Tree = $tree
        Clean = [string]::IsNullOrEmpty($status)
        StatusDigest = Get-Sha256Text -Text $status
        StatusDisplay = [regex]::Replace($status, '\x00', ' | ').Trim()
        CommonDir = Resolve-GitReportedPath -RepositoryRoot $WorktreeRoot -ReportedPath $commonDirText
        Closure = Get-ClosureFingerprint -RootPath $WorktreeRoot -Paths $paths
    }
}

function Assert-WorktreeStateUnchanged {
    param(
        [pscustomobject]$Before,
        [pscustomobject]$After,
        [string]$Label
    )

    Assert-AcceptanceInvariant -Condition ($Before.Clean -and $After.Clean) -Message "$Label was not clean before and after the runner."
    foreach ($propertyName in @("Head", "Tree", "StatusDigest", "CommonDir")) {
        if ([string]$Before.$propertyName -cne [string]$After.$propertyName) {
            throw "$Label changed '$propertyName'."
        }
    }
    foreach ($propertyName in @("Digest", "MaterializedDigest", "PathCount", "FileCount", "MissingCount")) {
        if ([string]$Before.Closure.$propertyName -cne [string]$After.Closure.$propertyName) {
            throw "$Label changed source snapshot '$propertyName'."
        }
    }
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([AllowEmptyString()][string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function New-RunnerEncodedCommand {
    param(
        [string]$RunnerPath,
        [string]$Target,
        [string]$ReceiptPath,
        [AllowEmptyString()][string]$RequestedGodotPath,
        [int]$ImportTimeout,
        [int]$TestTimeout
    )

    $invocation = @(
        "& $(ConvertTo-PowerShellSingleQuotedLiteral -Value $RunnerPath)",
        "-Target $(ConvertTo-PowerShellSingleQuotedLiteral -Value $Target)",
        "-KeepWorkspace",
        "-RunReceiptOutputPath $(ConvertTo-PowerShellSingleQuotedLiteral -Value $ReceiptPath)",
        "-ImportTimeoutSeconds $ImportTimeout",
        "-TestTimeoutSeconds $TestTimeout"
    )
    if (-not [string]::IsNullOrWhiteSpace($RequestedGodotPath)) {
        $invocation += "-GodotConsolePath $(ConvertTo-PowerShellSingleQuotedLiteral -Value $RequestedGodotPath)"
    }
    $command = @(
        '$ErrorActionPreference = "Stop"',
        'try {',
        ('    ' + ($invocation -join ' ')),
        '    if ($null -eq $LASTEXITCODE) { exit 0 }',
        '    exit ([int]$LASTEXITCODE)',
        '}',
        'catch {',
        '    [Console]::Error.WriteLine(($_ | Out-String))',
        '    exit 1',
        '}'
    ) -join "`n"
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
}

function Start-RunnerLane {
    param(
        [string]$LaneName,
        [string]$PowerShellExecutable,
        [string]$WorktreeRoot,
        [string]$Target,
        [string]$ReceiptPath,
        [string]$StdoutLogPath,
        [string]$StderrLogPath,
        [AllowEmptyString()][string]$RequestedGodotPath,
        [int]$ImportTimeout,
        [int]$TestTimeout
    )

    $runnerPath = Join-Path $WorktreeRoot "tests/run_all_tests.ps1"
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath $runnerPath -PathType Leaf) -Message "Lane $LaneName runner is missing."
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath (Join-Path $WorktreeRoot $Target.Replace('/', [System.IO.Path]::DirectorySeparatorChar)) -PathType Leaf) -Message "Lane $LaneName target '$Target' is missing."
    $encodedCommand = New-RunnerEncodedCommand `
        -RunnerPath $runnerPath `
        -Target $Target `
        -ReceiptPath $ReceiptPath `
        -RequestedGodotPath $RequestedGodotPath `
        -ImportTimeout $ImportTimeout `
        -TestTimeout $TestTimeout

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PowerShellExecutable
    $startInfo.Arguments = (@(
        "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand
    ) | ForEach-Object { ConvertTo-NativeProcessArgument -Argument ([string]$_) }) -join " "
    $startInfo.WorkingDirectory = $WorktreeRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    Set-SafeGitChildEnvironment -StartInfo $startInfo

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        $process.Dispose()
        throw "Could not start runner lane $LaneName."
    }
    return [pscustomobject]@{
        Name = $LaneName
        WorktreeRoot = $WorktreeRoot
        Target = $Target
        ReceiptPath = $ReceiptPath
        StdoutLogPath = $StdoutLogPath
        StderrLogPath = $StderrLogPath
        Process = $process
        OutputTask = $process.StandardOutput.ReadToEndAsync()
        ErrorTask = $process.StandardError.ReadToEndAsync()
        StartedUtc = $process.StartTime.ToUniversalTime()
    }
}

function Complete-RunnerLanes {
    param(
        [object[]]$Lanes,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $timedOut = $false
    while (@($Lanes | Where-Object { -not $_.Process.HasExited }).Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $timedOut = $true
            foreach ($lane in $Lanes) {
                Stop-AcceptanceProcessTree -Process $lane.Process
            }
            break
        }
        Start-Sleep -Milliseconds 200
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($lane in $Lanes) {
        try {
            if (-not $lane.Process.HasExited) {
                Stop-AcceptanceProcessTree -Process $lane.Process
            }
            $stdout = $lane.OutputTask.GetAwaiter().GetResult()
            $stderr = $lane.ErrorTask.GetAwaiter().GetResult()
            [System.IO.File]::WriteAllText($lane.StdoutLogPath, $stdout, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($lane.StderrLogPath, $stderr, [System.Text.UTF8Encoding]::new($false))
            $results.Add([pscustomobject]@{
                Name = $lane.Name
                WorktreeRoot = $lane.WorktreeRoot
                Target = $lane.Target
                ReceiptPath = $lane.ReceiptPath
                StdoutLogPath = $lane.StdoutLogPath
                StderrLogPath = $lane.StderrLogPath
                ExitCode = [int]$lane.Process.ExitCode
                StartedUtc = $lane.StartedUtc
                ExitedUtc = $lane.Process.ExitTime.ToUniversalTime()
                Stdout = [string]$stdout
                Stderr = [string]$stderr
                TimedOut = $timedOut
            })
        }
        finally {
            $lane.Process.Dispose()
        }
    }
    return @($results)
}

function ConvertFrom-ReceiptField {
    param([string]$Value)

    try {
        return [System.Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($Value))
    }
    catch {
        throw "Run receipt contains invalid Base64 UTF-8 metadata."
    }
}

function Read-TargetRunReceipt {
    param([string]$ReceiptPath)

    $normalizedPath = [System.IO.Path]::GetFullPath($ReceiptPath)
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath $normalizedPath -PathType Leaf) -Message "Run receipt is missing: '$normalizedPath'."
    $text = [System.IO.File]::ReadAllText($normalizedPath)
    Assert-AcceptanceInvariant -Condition (-not $text.Contains("`r") -and $text.EndsWith("`n", [StringComparison]::Ordinal)) -Message "Run receipt is not canonical LF text with one final newline."
    $lines = @($text.Split([char]"`n"))
    Assert-AcceptanceInvariant -Condition ($lines.Count -gt 2 -and $lines[$lines.Count - 1] -eq "") -Message "Run receipt envelope is incomplete."
    $lines = @($lines[0..($lines.Count - 2)])
    Assert-AcceptanceInvariant -Condition ($lines[0] -match '^canonical_sha256=([0-9a-f]{64})$') -Message "Run receipt has no canonical SHA-256 envelope."
    $declaredDigest = $Matches[1]
    $canonicalBody = [string]::Join("`n", $lines[1..($lines.Count - 1)])
    Assert-AcceptanceInvariant -Condition ((Get-Sha256Text -Text $canonicalBody) -eq $declaredDigest) -Message "Run receipt canonical SHA-256 does not match its body."

    $scalars = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line.StartsWith("target=", [StringComparison]::Ordinal)) {
            $targets.Add($line.Substring("target=".Length))
            continue
        }
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            throw "Run receipt contains invalid scalar line '$line'."
        }
        $key = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        if ($scalars.ContainsKey($key)) {
            throw "Run receipt contains duplicate scalar '$key'."
        }
        $scalars.Add($key, $value)
    }
    return [pscustomobject]@{
        Path = $normalizedPath
        Digest = $declaredDigest
        Scalars = $scalars
        Targets = @($targets)
    }
}

function Assert-TargetRunReceipt {
    param(
        [pscustomobject]$Receipt,
        [string]$ExpectedHead,
        [string]$ExpectedTree,
        [string]$ExpectedSnapshot,
        [string]$ExpectedTarget,
        [string]$ExpectedRunnerSha256
    )

    $requiredValues = [ordered]@{
        version = "godot-test-run-receipt-v1"
        source_head = $ExpectedHead
        source_tree = $ExpectedTree
        source_worktree_clean = "1"
        source_status_digest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        source_snapshot = $ExpectedSnapshot
        suite_mode = "target"
        import = "PASS"
        godot_service_port_scope = "import-and-tests"
        target_count = "1"
        pass = "1"
        fail = "0"
        skip = "0"
        blocking = "0"
        overall = "PASS"
    }
    foreach ($key in $requiredValues.Keys) {
        if (-not $Receipt.Scalars.ContainsKey($key) -or $Receipt.Scalars[$key] -cne [string]$requiredValues[$key]) {
            throw "Receipt '$($Receipt.Path)' has invalid '$key'."
        }
    }
    Assert-AcceptanceInvariant -Condition ($Receipt.Targets.Count -eq 1) -Message "Targeted receipt must contain exactly one closed target record."
    $parts = @($Receipt.Targets[0].Split('|'))
    Assert-AcceptanceInvariant `
        -Condition ($parts.Count -eq 6 -and
            $parts[0] -eq "0" -and
            (ConvertFrom-ReceiptField -Value $parts[1]) -ceq $ExpectedTarget -and
            $parts[3] -eq "PASS" -and
            $parts[4] -eq "0" -and
            $parts[5] -eq "0") `
        -Message "Targeted receipt result does not prove '$ExpectedTarget' PASS."

    foreach ($portKey in @("debug_server_port", "dap_port", "lsp_port")) {
        Assert-AcceptanceInvariant -Condition ($Receipt.Scalars.ContainsKey($portKey) -and $Receipt.Scalars[$portKey] -match '^[0-9]+$') -Message "Receipt has invalid '$portKey'."
        $port = [int]$Receipt.Scalars[$portKey]
        Assert-AcceptanceInvariant -Condition ($port -ge 1024 -and $port -le 65535) -Message "Receipt port '$portKey' is outside the accepted range."
    }
    $ports = @(
        [int]$Receipt.Scalars["debug_server_port"],
        [int]$Receipt.Scalars["dap_port"],
        [int]$Receipt.Scalars["lsp_port"]
    )
    Assert-AcceptanceInvariant -Condition (@($ports | Select-Object -Unique).Count -eq 3) -Message "One runner reused a Godot service port internally."

    $runId = ConvertFrom-ReceiptField -Value $Receipt.Scalars["overlay_run_id"]
    $userDirectory = ConvertFrom-ReceiptField -Value $Receipt.Scalars["overlay_user_directory"]
    Assert-AcceptanceInvariant -Condition ($runId -match '^run_[0-9]{8}_[0-9]{6}_[0-9]{3}_[0-9]+_[0-9a-f]{32}$') -Message "Receipt run ID is invalid."
    Assert-AcceptanceInvariant -Condition ($userDirectory -ceq "OstatniPomost/TestRuns/$runId") -Message "Receipt user:// directory is not bound to its run ID."
    Assert-AcceptanceInvariant `
        -Condition ($Receipt.Scalars.ContainsKey("runner_sha256") -and
            $Receipt.Scalars["runner_sha256"] -match '^[0-9a-f]{64}$' -and
            $Receipt.Scalars["runner_sha256"] -ceq $ExpectedRunnerSha256) `
        -Message "Receipt does not bind the exact common runner revision."
    $godotVersion = ConvertFrom-ReceiptField -Value $Receipt.Scalars["godot_version"]
    Assert-AcceptanceInvariant -Condition (-not [string]::IsNullOrWhiteSpace($godotVersion)) -Message "Receipt Godot version is empty."
    return [pscustomobject]@{
        RunId = $runId
        UserDirectoryName = $userDirectory
        Ports = $ports
        RunnerSha256 = [string]$Receipt.Scalars["runner_sha256"]
        GodotVersion = $godotVersion
    }
}

function Remove-AnsiControlSequences {
    param([AllowEmptyString()][string]$Text)

    return [regex]::Replace($Text, '(?:\x1B\[[0-?]*[ -/]*[@-~])|(?:\x1B\][^\x07]*(?:\x07|\x1B\\))', '')
}

function Get-UniqueOutputPath {
    param(
        [string]$Output,
        [string]$Label
    )

    $clean = Remove-AnsiControlSequences -Text $Output
    $pattern = '(?m)^\s*' + [regex]::Escape($Label) + ':\s*(.+?)\s*$'
    $matches = [regex]::Matches($clean, $pattern)
    Assert-AcceptanceInvariant -Condition ($matches.Count -eq 1) -Message "Runner output must contain exactly one '${Label}:' path."
    return [System.IO.Path]::GetFullPath($matches[0].Groups[1].Value.Trim()).TrimEnd([char[]]"\/")
}

function Assert-RunnerWorkspaceEvidence {
    param(
        [pscustomobject]$LaneResult,
        [pscustomobject]$ReceiptMetadata
    )

    $workspacePath = Get-UniqueOutputPath -Output $LaneResult.Stdout -Label "Test workspace preserved"
    $projectPath = Get-UniqueOutputPath -Output $LaneResult.Stdout -Label "Project"
    $userPath = Get-UniqueOutputPath -Output $LaneResult.Stdout -Label "Test user:// preserved"
    Assert-AcceptanceInvariant -Condition ([string]::Equals($workspacePath, $projectPath, [StringComparison]::OrdinalIgnoreCase)) -Message "Runner project path differs from its preserved workspace."
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath $workspacePath -PathType Container) -Message "Preserved runner workspace does not exist: '$workspacePath'."
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath $userPath -PathType Container) -Message "Preserved runner user:// does not exist: '$userPath'."
    Assert-AcceptanceInvariant -Condition ([System.IO.Path]::GetFileName($userPath) -ceq $ReceiptMetadata.RunId) -Message "Preserved user:// path is not bound to the receipt run ID."
    $cachePath = [System.IO.Path]::GetFullPath((Join-Path $workspacePath ".godot")).TrimEnd([char[]]"\/")
    $importCachePath = [System.IO.Path]::GetFullPath((Join-Path $cachePath "imported")).TrimEnd([char[]]"\/")
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath $cachePath -PathType Container) -Message "Runner workspace has no private .godot cache."
    Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath $importCachePath -PathType Container) -Message "Runner workspace has no private import cache."
    Assert-AcceptanceInvariant -Condition (@(Get-ChildItem -LiteralPath $importCachePath -File -Force -ErrorAction Stop).Count -gt 0) -Message "Runner import cache is empty."
    return [pscustomobject]@{
        WorkspacePath = $workspacePath
        UserPath = $userPath
        CachePath = $cachePath
        ImportCachePath = $importCachePath
    }
}

function Assert-VerifiedFixtureRoot {
    param(
        [string]$FixtureRoot,
        [string]$FixtureToken
    )

    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]"\/")
    $normalizedFixture = [System.IO.Path]::GetFullPath($FixtureRoot).TrimEnd([char[]]"\/")
    $expectedPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    $fixtureName = [System.IO.Path]::GetFileName($normalizedFixture)
    if (-not $normalizedFixture.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([System.IO.Path]::GetDirectoryName($normalizedFixture).TrimEnd([char[]]"\/"), $tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fixtureName -notmatch '^ostatni_pomost_parallel_worktree_acceptance_[0-9a-f]{32}$') {
        throw "Refusing cleanup outside the exact acceptance temp prefix: '$normalizedFixture'."
    }
    $fixtureItem = Get-Item -LiteralPath $normalizedFixture -Force
    if (($fixtureItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing cleanup of a reparse-point acceptance fixture: '$normalizedFixture'."
    }
    $markerPath = Join-Path $normalizedFixture "ACCEPTANCE_FIXTURE.marker"
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
        [System.IO.File]::ReadAllText($markerPath) -cne $FixtureToken) {
        throw "Refusing cleanup of an unverified acceptance fixture: '$normalizedFixture'."
    }
    $pendingDirectories = [System.Collections.Generic.Stack[string]]::new()
    $pendingDirectories.Push($normalizedFixture)
    while ($pendingDirectories.Count -gt 0) {
        $directory = $pendingDirectories.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing cleanup of a fixture containing reparse point '$($child.FullName)'."
            }
            if ($child.PSIsContainer) {
                $pendingDirectories.Push($child.FullName)
            }
        }
    }
    return $normalizedFixture
}

function Remove-VerifiedFixtureRoot {
    param(
        [string]$FixtureRoot,
        [string]$FixtureToken
    )

    if (-not (Test-Path -LiteralPath $FixtureRoot)) {
        return
    }
    $verified = Assert-VerifiedFixtureRoot -FixtureRoot $FixtureRoot -FixtureToken $FixtureToken
    Remove-Item -LiteralPath $verified -Recurse -Force
}

$sourceProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..")).TrimEnd([char[]]"\/")
$targetAResolved = Normalize-TargetPath -Target $TargetA -ParameterName "-TargetA"
$targetBResolved = Normalize-TargetPath -Target $TargetB -ParameterName "-TargetB"
Assert-AcceptanceInvariant `
    -Condition (-not [string]::Equals($targetAResolved, $targetBResolved, [StringComparison]::OrdinalIgnoreCase)) `
    -Message "The two acceptance lanes must use two distinct explicit targets."

$sourceTopLevel = (Invoke-GitCapture -RepositoryRoot $sourceProjectRoot -Arguments @("rev-parse", "--show-toplevel")).Output.Trim()
$sourceProjectRoot = [System.IO.Path]::GetFullPath($sourceTopLevel).TrimEnd([char[]]"\/")
Assert-AcceptanceInvariant -Condition (Test-Path -LiteralPath (Join-Path $sourceProjectRoot "project.godot") -PathType Leaf) -Message "Source root has no project.godot."

$evidenceBase = if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localData)) {
        $localData = [System.IO.Path]::GetTempPath()
    }
    Join-Path $localData "OstatniPomost/ParallelWorktreeAcceptance"
}
else {
    $expandedEvidence = [Environment]::ExpandEnvironmentVariables($EvidenceRoot.Trim())
    if (-not [System.IO.Path]::IsPathRooted($expandedEvidence)) {
        throw "-EvidenceRoot must be an absolute path outside the source checkout."
    }
    $expandedEvidence
}
$evidenceBase = [System.IO.Path]::GetFullPath($evidenceBase).TrimEnd([char[]]"\/")
Assert-AcceptanceInvariant -Condition (-not (Test-PathInsideRoot -CandidatePath $evidenceBase -RootPath $sourceProjectRoot -AllowEqual)) -Message "Evidence root must stay outside the real source checkout."
[void](New-Item -ItemType Directory -Path $evidenceBase -Force)
$acceptanceId = "acceptance_{0}_{1}_{2}" -f (Get-Date -Format "yyyyMMdd_HHmmss_fff"), $PID, [Guid]::NewGuid().ToString("N")
$evidenceRunRoot = [System.IO.Path]::GetFullPath((Join-Path $evidenceBase $acceptanceId))
[void](New-Item -ItemType Directory -Path $evidenceRunRoot)

$fixtureToken = [Guid]::NewGuid().ToString("N")
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ("ostatni_pomost_parallel_worktree_acceptance_" + [Guid]::NewGuid().ToString("N"))))
[void](New-Item -ItemType Directory -Path $fixtureRoot)
[System.IO.File]::WriteAllText((Join-Path $fixtureRoot "ACCEPTANCE_FIXTURE.marker"), $fixtureToken, [System.Text.UTF8Encoding]::new($false))

$temporaryRepositoryRoot = Join-Path $fixtureRoot "snapshot-repository"
$linkedWorktreesRoot = Join-Path $fixtureRoot "linked-worktrees"
$worktreeA = Join-Path $linkedWorktreesRoot "lane-a"
$worktreeB = Join-Path $linkedWorktreesRoot "lane-b"
$receiptAPath = Join-Path $evidenceRunRoot "lane-a.receipt"
$receiptBPath = Join-Path $evidenceRunRoot "lane-b.receipt"
$stdoutAPath = Join-Path $evidenceRunRoot "lane-a.stdout.log"
$stderrAPath = Join-Path $evidenceRunRoot "lane-a.stderr.log"
$stdoutBPath = Join-Path $evidenceRunRoot "lane-b.stdout.log"
$stderrBPath = Join-Path $evidenceRunRoot "lane-b.stderr.log"

$sourceAuditBefore = $null
$sourceAuditAfter = $null
$primaryException = $null
$auditException = $null
$cleanupException = $null
$activeLanes = @()
$acceptanceData = $null

try {
    $sourceAuditBefore = Get-GitRepositoryAudit -RepositoryRoot $sourceProjectRoot
    [void](Copy-ClosedSnapshot `
        -SourceRoot $sourceProjectRoot `
        -SourceAuditBefore $sourceAuditBefore `
        -DestinationRoot $temporaryRepositoryRoot)

    $emptyGitTemplate = Join-Path $fixtureRoot "empty-git-template"
    [void](New-Item -ItemType Directory -Path $emptyGitTemplate)
    [void](Invoke-NativeProcessCapture `
        -FilePath $gitExecutable `
        -Arguments @("init", "--quiet", "--template=$($emptyGitTemplate.Replace('\', '/'))", $temporaryRepositoryRoot) `
        -WorkingDirectory $fixtureRoot)
    $temporaryGitDir = Resolve-GitReportedPath `
        -RepositoryRoot $temporaryRepositoryRoot `
        -ReportedPath (Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("rev-parse", "--git-dir")).Output
    Assert-AcceptanceInvariant -Condition (Test-PathInsideRoot -CandidatePath $temporaryGitDir -RootPath $fixtureRoot) -Message "Temporary Git dir escaped the verified fixture."
    $temporaryInfoDirectory = Join-Path $temporaryGitDir "info"
    [void](New-Item -ItemType Directory -Path $temporaryInfoDirectory -Force)
    # The temporary immutable tree must store the exact working bytes. This
    # Git-private highest-precedence rule prevents repository EOL/LFS filters
    # from normalizing the copied snapshot; it never enters the commit.
    [System.IO.File]::WriteAllText(
        (Join-Path $temporaryInfoDirectory "attributes"),
        "* -text -filter -eol`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $emptyHooks = Join-Path $fixtureRoot "empty-hooks"
    [void](New-Item -ItemType Directory -Path $emptyHooks)
    $emptyGlobalAttributes = Join-Path $fixtureRoot "empty-global-attributes"
    [System.IO.File]::WriteAllText($emptyGlobalAttributes, "", [System.Text.UTF8Encoding]::new($false))
    foreach ($configuration in @(
        @("core.autocrlf", "false"),
        @("core.filemode", "false"),
        @("core.attributesFile", $emptyGlobalAttributes.Replace('\', '/')),
        @("core.fsmonitor", "false"),
        @("core.untrackedCache", "false"),
        @("maintenance.auto", "false"),
        @("gc.auto", "0"),
        @("commit.gpgSign", "false"),
        @("core.hooksPath", $emptyHooks.Replace('\', '/')),
        @("filter.lfs.required", "false"),
        @("filter.lfs.process", ""),
        @("filter.lfs.clean", ""),
        @("filter.lfs.smudge", "")
    )) {
        [void](Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("config", $configuration[0], $configuration[1]))
    }
    [void](Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("add", "--force", "--all", "--", ".") -TimeoutSeconds 600)
    [void](Invoke-GitCapture `
        -RepositoryRoot $temporaryRepositoryRoot `
        -Arguments @(
            "-c", "user.name=ParallelWorktreeAcceptance",
            "-c", "user.email=parallel.worktree.acceptance@example.invalid",
            "commit", "--quiet", "--no-verify", "--no-gpg-sign", "-m", "immutable Git-closed acceptance snapshot"
        ) `
        -TimeoutSeconds 600)

    $temporaryCommit = (Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("rev-parse", "--verify", "HEAD")).Output.Trim().ToLowerInvariant()
    $temporaryTree = (Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("rev-parse", "--verify", "HEAD^{tree}")).Output.Trim().ToLowerInvariant()
    $temporaryCommonDir = Resolve-GitReportedPath `
        -RepositoryRoot $temporaryRepositoryRoot `
        -ReportedPath (Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("rev-parse", "--git-common-dir")).Output
    $temporaryStatus = (Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("status", "--porcelain=v1", "--untracked-files=all", "-z")).Output
    $temporaryRemotes = (Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("remote")).Output
    Assert-AcceptanceInvariant -Condition ([string]::IsNullOrEmpty($temporaryStatus)) -Message "Temporary snapshot repository is not clean after its isolated commit."
    Assert-AcceptanceInvariant -Condition ([string]::IsNullOrWhiteSpace($temporaryRemotes)) -Message "Temporary snapshot repository unexpectedly has a remote."
    $expectedCommittedPaths = @($sourceAuditBefore.Closure.Entries | Where-Object Exists | ForEach-Object RelativePath)
    $temporaryCommittedPaths = @(Get-GitClosurePaths -RepositoryRoot $temporaryRepositoryRoot)
    Assert-AcceptanceInvariant `
        -Condition ([string]::Join("`n", $temporaryCommittedPaths) -ceq [string]::Join("`n", $expectedCommittedPaths)) `
        -Message "Temporary commit path closure differs from the materialized source snapshot."
    $temporaryWorkingClosure = Get-ClosureFingerprint -RootPath $temporaryRepositoryRoot -Paths $temporaryCommittedPaths
    Assert-AcceptanceInvariant `
        -Condition ($temporaryWorkingClosure.Digest -eq $sourceAuditBefore.Closure.MaterializedDigest) `
        -Message "Temporary repository working bytes differ from the materialized source snapshot."

    [void](New-Item -ItemType Directory -Path $linkedWorktreesRoot)
    [void](Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("worktree", "add", "--quiet", "--detach", $worktreeA, $temporaryCommit) -TimeoutSeconds 600)
    [void](Invoke-GitCapture -RepositoryRoot $temporaryRepositoryRoot -Arguments @("worktree", "add", "--quiet", "--detach", $worktreeB, $temporaryCommit) -TimeoutSeconds 600)
    [void](Copy-ExactMaterializedSnapshot -SourceRoot $temporaryRepositoryRoot -SourceClosure $sourceAuditBefore.Closure -DestinationRoot $worktreeA)
    [void](Copy-ExactMaterializedSnapshot -SourceRoot $temporaryRepositoryRoot -SourceClosure $sourceAuditBefore.Closure -DestinationRoot $worktreeB)

    $worktreeABefore = Get-WorktreeState -WorktreeRoot $worktreeA
    $worktreeBBefore = Get-WorktreeState -WorktreeRoot $worktreeB
    Assert-AcceptanceInvariant `
        -Condition ($worktreeABefore.Clean -and $worktreeBBefore.Clean) `
        -Message "Linked source worktrees must start clean: A='$($worktreeABefore.StatusDisplay)' B='$($worktreeBBefore.StatusDisplay)'."
    Assert-AcceptanceInvariant -Condition ($worktreeABefore.Head -eq $temporaryCommit -and $worktreeBBefore.Head -eq $temporaryCommit) -Message "Linked source worktrees do not share the immutable temporary commit."
    Assert-AcceptanceInvariant -Condition ($worktreeABefore.Tree -eq $temporaryTree -and $worktreeBBefore.Tree -eq $temporaryTree) -Message "Linked source worktrees do not share the immutable temporary tree."
    Assert-AcceptanceInvariant -Condition ($worktreeABefore.Closure.Digest -eq $worktreeBBefore.Closure.Digest) -Message "Linked source worktrees do not have the same Git-closed snapshot."
    Assert-AcceptanceInvariant -Condition ($worktreeABefore.Closure.Digest -eq $sourceAuditBefore.Closure.MaterializedDigest) -Message "Linked source worktrees are not the byte-exact materialized source snapshot."
    Assert-AcceptanceInvariant -Condition ([string]::Equals($worktreeABefore.CommonDir, $worktreeBBefore.CommonDir, [StringComparison]::OrdinalIgnoreCase)) -Message "Linked worktrees do not share one Git common-dir."
    Assert-AcceptanceInvariant -Condition ([string]::Equals($worktreeABefore.CommonDir, $temporaryCommonDir, [StringComparison]::OrdinalIgnoreCase)) -Message "Linked worktrees do not use the temporary repository common-dir."
    Assert-AcceptanceInvariant -Condition (Test-PathInsideRoot -CandidatePath $temporaryCommonDir -RootPath $fixtureRoot) -Message "Temporary Git common-dir escaped the verified fixture."
    Assert-AcceptanceInvariant -Condition (-not [string]::Equals($worktreeABefore.CommonDir, $sourceAuditBefore.CommonDir, [StringComparison]::OrdinalIgnoreCase)) -Message "Acceptance worktrees accidentally use the real repository Git common-dir."
    Assert-AcceptanceInvariant -Condition (-not (Test-Path -LiteralPath (Join-Path $worktreeA ".godot")) -and -not (Test-Path -LiteralPath (Join-Path $worktreeB ".godot"))) -Message "Linked source worktrees must not start with a shared/private .godot cache."
    $runnerSha256 = (Get-FileHash -LiteralPath (Join-Path $worktreeA "tests/run_all_tests.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-AcceptanceInvariant `
        -Condition ($runnerSha256 -eq (Get-FileHash -LiteralPath (Join-Path $worktreeB "tests/run_all_tests.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()) `
        -Message "Linked worktrees do not contain the same common runner bytes."

    $powerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $laneA = Start-RunnerLane `
        -LaneName "A" `
        -PowerShellExecutable $powerShellExecutable `
        -WorktreeRoot $worktreeA `
        -Target $targetAResolved `
        -ReceiptPath $receiptAPath `
        -StdoutLogPath $stdoutAPath `
        -StderrLogPath $stderrAPath `
        -RequestedGodotPath $GodotConsolePath `
        -ImportTimeout $ImportTimeoutSeconds `
        -TestTimeout $TestTimeoutSeconds
    $activeLanes = @($laneA)
    try {
        $laneB = Start-RunnerLane `
            -LaneName "B" `
            -PowerShellExecutable $powerShellExecutable `
            -WorktreeRoot $worktreeB `
            -Target $targetBResolved `
            -ReceiptPath $receiptBPath `
            -StdoutLogPath $stdoutBPath `
            -StderrLogPath $stderrBPath `
            -RequestedGodotPath $GodotConsolePath `
            -ImportTimeout $ImportTimeoutSeconds `
            -TestTimeout $TestTimeoutSeconds
        $activeLanes = @($laneA, $laneB)
    }
    catch {
        Stop-AcceptanceProcessTree -Process $laneA.Process
        throw
    }
    $laneResults = @(Complete-RunnerLanes -Lanes $activeLanes -TimeoutSeconds $AcceptanceTimeoutSeconds)
    $activeLanes = @()
    Assert-AcceptanceInvariant -Condition ($laneResults.Count -eq 2) -Message "Acceptance did not collect exactly two runner results."
    foreach ($laneResult in $laneResults) {
        Assert-AcceptanceInvariant -Condition (-not $laneResult.TimedOut -and $laneResult.ExitCode -eq 0) -Message "Runner lane $($laneResult.Name) failed; inspect '$($laneResult.StdoutLogPath)' and '$($laneResult.StderrLogPath)'."
    }
    $overlapStart = @($laneResults | ForEach-Object StartedUtc | Sort-Object -Descending)[0]
    $overlapEnd = @($laneResults | ForEach-Object ExitedUtc | Sort-Object)[0]
    $overlapMilliseconds = ($overlapEnd - $overlapStart).TotalMilliseconds
    Assert-AcceptanceInvariant -Condition ($overlapMilliseconds -gt 0) -Message "The two runner processes did not overlap in wall-clock time."

    $receiptA = Read-TargetRunReceipt -ReceiptPath $receiptAPath
    $receiptB = Read-TargetRunReceipt -ReceiptPath $receiptBPath
    $metadataA = Assert-TargetRunReceipt `
        -Receipt $receiptA `
        -ExpectedHead $temporaryCommit `
        -ExpectedTree $temporaryTree `
        -ExpectedSnapshot $worktreeABefore.Closure.Digest `
        -ExpectedTarget $targetAResolved `
        -ExpectedRunnerSha256 $runnerSha256
    $metadataB = Assert-TargetRunReceipt `
        -Receipt $receiptB `
        -ExpectedHead $temporaryCommit `
        -ExpectedTree $temporaryTree `
        -ExpectedSnapshot $worktreeBBefore.Closure.Digest `
        -ExpectedTarget $targetBResolved `
        -ExpectedRunnerSha256 $runnerSha256
    Assert-AcceptanceInvariant -Condition ($receiptA.Scalars["source_snapshot"] -eq $receiptB.Scalars["source_snapshot"]) -Message "Runner receipts do not bind the same source snapshot."
    Assert-AcceptanceInvariant -Condition ($metadataA.RunId -cne $metadataB.RunId) -Message "Concurrent runner lanes reused a run ID."
    Assert-AcceptanceInvariant -Condition ($metadataA.UserDirectoryName -cne $metadataB.UserDirectoryName) -Message "Concurrent runner lanes reused user://."
    Assert-AcceptanceInvariant -Condition ($metadataA.RunnerSha256 -eq $metadataB.RunnerSha256) -Message "Concurrent lanes did not execute the same runner revision."
    Assert-AcceptanceInvariant -Condition ($metadataA.GodotVersion -eq $metadataB.GodotVersion) -Message "Concurrent lanes did not execute the same Godot version."
    $allPorts = @($metadataA.Ports) + @($metadataB.Ports)
    Assert-AcceptanceInvariant -Condition (@($allPorts | Select-Object -Unique).Count -eq 6) -Message "Concurrent runner lanes reused at least one debug/DAP/LSP port."

    $laneAResult = @($laneResults | Where-Object Name -eq "A")[0]
    $laneBResult = @($laneResults | Where-Object Name -eq "B")[0]
    $workspaceEvidenceA = Assert-RunnerWorkspaceEvidence -LaneResult $laneAResult -ReceiptMetadata $metadataA
    $workspaceEvidenceB = Assert-RunnerWorkspaceEvidence -LaneResult $laneBResult -ReceiptMetadata $metadataB
    foreach ($evidence in @($workspaceEvidenceA, $workspaceEvidenceB)) {
        foreach ($path in @($evidence.WorkspacePath, $evidence.UserPath)) {
            Assert-AcceptanceInvariant `
                -Condition (-not (Test-PathInsideRoot -CandidatePath $path -RootPath $fixtureRoot -AllowEqual) -and
                    -not (Test-PathInsideRoot -CandidatePath $path -RootPath $sourceProjectRoot -AllowEqual)) `
                -Message "Runner workspace/user evidence is not external: '$path'."
        }
    }
    foreach ($propertyName in @("WorkspacePath", "UserPath", "CachePath", "ImportCachePath")) {
        Assert-AcceptanceInvariant `
            -Condition (-not [string]::Equals($workspaceEvidenceA.$propertyName, $workspaceEvidenceB.$propertyName, [StringComparison]::OrdinalIgnoreCase)) `
            -Message "Concurrent runner lanes reused '$propertyName'."
    }
    Assert-AcceptanceInvariant `
        -Condition (-not (Test-PathInsideRoot -CandidatePath $workspaceEvidenceA.WorkspacePath -RootPath $workspaceEvidenceB.WorkspacePath -AllowEqual) -and
            -not (Test-PathInsideRoot -CandidatePath $workspaceEvidenceB.WorkspacePath -RootPath $workspaceEvidenceA.WorkspacePath -AllowEqual) -and
            -not (Test-PathInsideRoot -CandidatePath $workspaceEvidenceA.UserPath -RootPath $workspaceEvidenceB.UserPath -AllowEqual) -and
            -not (Test-PathInsideRoot -CandidatePath $workspaceEvidenceB.UserPath -RootPath $workspaceEvidenceA.UserPath -AllowEqual)) `
        -Message "Concurrent runner workspaces/user directories are nested rather than isolated."
    foreach ($pathPair in @(
        @($stdoutAPath, $stdoutBPath),
        @($stderrAPath, $stderrBPath),
        @($receiptAPath, $receiptBPath)
    )) {
        Assert-AcceptanceInvariant -Condition (-not [string]::Equals($pathPair[0], $pathPair[1], [StringComparison]::OrdinalIgnoreCase)) -Message "Concurrent lanes reused an evidence/log path."
        Assert-AcceptanceInvariant -Condition ((Test-Path -LiteralPath $pathPair[0] -PathType Leaf) -and (Test-Path -LiteralPath $pathPair[1] -PathType Leaf)) -Message "Concurrent lane evidence/log file is missing."
    }
    Assert-AcceptanceInvariant -Condition (-not (Test-Path -LiteralPath (Join-Path $worktreeA ".godot")) -and -not (Test-Path -LiteralPath (Join-Path $worktreeB ".godot"))) -Message "Runner polluted a linked source worktree with .godot."

    $worktreeAAfter = Get-WorktreeState -WorktreeRoot $worktreeA
    $worktreeBAfter = Get-WorktreeState -WorktreeRoot $worktreeB
    Assert-WorktreeStateUnchanged -Before $worktreeABefore -After $worktreeAAfter -Label "Linked worktree A"
    Assert-WorktreeStateUnchanged -Before $worktreeBBefore -After $worktreeBAfter -Label "Linked worktree B"
    Assert-AcceptanceInvariant -Condition ([string]::Equals($worktreeAAfter.CommonDir, $worktreeBAfter.CommonDir, [StringComparison]::OrdinalIgnoreCase)) -Message "Linked worktrees stopped sharing their temporary common-dir."

    $acceptanceData = [ordered]@{
        schema_version = 1
        status = "PASS"
        acceptance_id = $acceptanceId
        source_kind = "temporary_commit_from_git_closed_working_snapshot"
        real_source_head_observed = $sourceAuditBefore.Head
        real_source_tree_observed = $sourceAuditBefore.Tree
        real_source_snapshot = $sourceAuditBefore.Closure.Digest
        temporary_commit = $temporaryCommit
        temporary_tree = $temporaryTree
        linked_common_dir = $worktreeAAfter.CommonDir
        shared_runner_source_snapshot = $receiptA.Scalars["source_snapshot"]
        concurrent_overlap_ms = [Math]::Round($overlapMilliseconds, 3)
        evidence_root = $evidenceRunRoot
        retained_runner_workspaces = @($workspaceEvidenceA.WorkspacePath, $workspaceEvidenceB.WorkspacePath)
        retained_user_directories = @($workspaceEvidenceA.UserPath, $workspaceEvidenceB.UserPath)
        lanes = @(
            [ordered]@{
                lane = "A"
                target = $targetAResolved
                receipt = $receiptA.Path
                receipt_sha256 = $receiptA.Digest
                run_id = $metadataA.RunId
                debug_port = $metadataA.Ports[0]
                dap_port = $metadataA.Ports[1]
                lsp_port = $metadataA.Ports[2]
                workspace = $workspaceEvidenceA.WorkspacePath
                user_directory = $workspaceEvidenceA.UserPath
                cache = $workspaceEvidenceA.CachePath
                import_cache = $workspaceEvidenceA.ImportCachePath
                stdout_log = $stdoutAPath
                stderr_log = $stderrAPath
            },
            [ordered]@{
                lane = "B"
                target = $targetBResolved
                receipt = $receiptB.Path
                receipt_sha256 = $receiptB.Digest
                run_id = $metadataB.RunId
                debug_port = $metadataB.Ports[0]
                dap_port = $metadataB.Ports[1]
                lsp_port = $metadataB.Ports[2]
                workspace = $workspaceEvidenceB.WorkspacePath
                user_directory = $workspaceEvidenceB.UserPath
                cache = $workspaceEvidenceB.CachePath
                import_cache = $workspaceEvidenceB.ImportCachePath
                stdout_log = $stdoutBPath
                stderr_log = $stderrBPath
            }
        )
    }
}
catch {
    $primaryException = $_.Exception
}
finally {
    foreach ($lane in @($activeLanes)) {
        try {
            Stop-AcceptanceProcessTree -Process $lane.Process
            $lane.Process.Dispose()
        }
        catch {
            # The primary failure remains authoritative; cleanup is still bounded.
        }
    }
    if ($null -ne $sourceAuditBefore) {
        try {
            $sourceAuditAfter = Get-GitRepositoryAudit -RepositoryRoot $sourceProjectRoot
            Assert-RepositoryAuditUnchanged -Before $sourceAuditBefore -After $sourceAuditAfter -Label "Real repository"
        }
        catch {
            $auditException = $_.Exception
        }
    }
    try {
        Remove-VerifiedFixtureRoot -FixtureRoot $fixtureRoot -FixtureToken $fixtureToken
    }
    catch {
        $cleanupException = $_.Exception
    }
}

$failureMessages = [System.Collections.Generic.List[string]]::new()
if ($null -ne $primaryException) {
    $failureMessages.Add("acceptance: $($primaryException.Message)")
}
if ($null -ne $auditException) {
    $failureMessages.Add("real repository audit: $($auditException.Message)")
}
if ($null -ne $cleanupException) {
    $failureMessages.Add("verified temp cleanup: $($cleanupException.Message)")
}
if ($failureMessages.Count -gt 0) {
    throw ("parallel_worktree_godot_test FAIL: " + ($failureMessages -join " | ") + ". Evidence: '$evidenceRunRoot'.")
}

$acceptanceData["real_repository_unchanged"] = $true
$acceptanceData["real_refs_unchanged"] = $true
$acceptanceData["temporary_fixture_removed"] = $true
$summaryPath = Join-Path $evidenceRunRoot "parallel_worktree_acceptance.json"
$summaryJson = $acceptanceData | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($summaryPath, $summaryJson + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host "parallel_worktree_godot_test PASS: two linked worktrees ran distinct explicit targets concurrently from one immutable temporary SHA."
Write-Host ("  temporary HEAD/tree: {0} / {1}" -f $acceptanceData.temporary_commit, $acceptanceData.temporary_tree)
Write-Host ("  shared snapshot:      {0}" -f $acceptanceData.shared_runner_source_snapshot)
Write-Host ("  concurrent overlap:   {0} ms" -f $acceptanceData.concurrent_overlap_ms)
Write-Host ("  evidence:             {0}" -f $summaryPath)
