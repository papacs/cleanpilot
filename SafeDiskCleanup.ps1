[CmdletBinding()]
param(
    [switch] $Aggressive,
    [switch] $DryRun,    
    [ValidateRange(0, 3650)]
    [int] $MinAgeDays = 7,
    [string] $LogPath = '',
    [switch] $OpenWizTree,
    [string] $WizTreePath = '',
    [string] $ScanPath = $env:SystemDrive,
    [switch] $IncludeDism
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$Script:CleanupLogPath = $null
$Script:ReclaimedBytes = 0L
$Script:SkippedCount = 0
$Script:RemovedCount = 0

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-LogPath {
    param([string] $RequestedLogPath)

    if ([string]::IsNullOrWhiteSpace($RequestedLogPath)) {
        $root = if (Test-IsAdministrator) {
            Join-Path $env:ProgramData 'SafeDiskCleanup\Logs'
        } else {
            Join-Path $env:LOCALAPPDATA 'SafeDiskCleanup\Logs'
        }

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $RequestedLogPath = Join-Path $root "cleanup-$stamp-pid$PID.log"
    }

    $parent = Split-Path -Parent $RequestedLogPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Script:CleanupLogPath = $RequestedLogPath
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string] $Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line

    if (-not [string]::IsNullOrWhiteSpace($Script:CleanupLogPath)) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Add-Content -LiteralPath $Script:CleanupLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
                break
            } catch {
                if ($attempt -ge 3) {
                    Write-Host ("{0} [WARN] Unable to write log file: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
                } else {
                    Start-Sleep -Milliseconds 100
                }
            }
        }
    }
}

function Convert-ByteSize {
    param([Int64] $Bytes)

    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Resolve-WizTreeExecutable {
    param([string] $RequestedPath = '')

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates.Add([Environment]::ExpandEnvironmentVariables($RequestedPath)) | Out-Null
    }

    $candidates.Add((Join-Path $PSScriptRoot 'tools\WizTree\WizTree64.exe')) | Out-Null
    $candidates.Add((Join-Path $PSScriptRoot 'WizTree64.exe')) | Out-Null
    $candidates.Add((Join-Path $PSScriptRoot 'WizTree.exe')) | Out-Null

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return ''
}

function Start-WizTreeScan {
    param(
        [string] $ExecutablePath,
        [string] $ScanPath,
        [bool] $IsAdmin
    )

    $expectedPath = Join-Path $PSScriptRoot 'tools\WizTree\WizTree64.exe'
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        Write-Log "WizTree not found. Place portable WizTree at $expectedPath or pass -WizTreePath." 'WARN'
        return
    }

    $targetPath = [Environment]::ExpandEnvironmentVariables($ScanPath)
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        $targetPath = $env:SystemDrive
    }

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    $arguments.Add(('"{0}"' -f $targetPath)) | Out-Null
    if ($IsAdmin) {
        $arguments.Add('/admin=1') | Out-Null
    }

    try {
        Write-Log "Opening WizTree for $targetPath using $ExecutablePath."
        Start-Process -FilePath $ExecutablePath -ArgumentList $arguments.ToArray() -ErrorAction Stop | Out-Null
    } catch {
        Write-Log "Could not open WizTree: $($_.Exception.Message)" 'WARN'
    }
}

function Get-DirectorySize {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0L
    }

    try {
        $measure = Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($null -eq $measure.Sum) {
            return 0L
        }
        return [Int64] $measure.Sum
    } catch {
        Write-Log "Could not measure $Path : $($_.Exception.Message)" 'WARN'
        return 0L
    }
}

function Test-SafeCleanupPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path.TrimEnd('\'))
    } catch {
        return $false
    }

    $rootPath = [System.IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    if ($fullPath.TrimEnd('\') -ieq $rootPath) {
        return $false
    }

    $blockedExactPaths = @(
        $env:SystemDrive,
        $env:windir,
        $env:SystemRoot,
        $env:ProgramData,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:USERPROFILE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { [System.IO.Path]::GetFullPath($_.TrimEnd('\')) }

    foreach ($blocked in $blockedExactPaths) {
        if ($fullPath -ieq $blocked) {
            return $false
        }
    }

    return $true
}

function New-CleanupTarget {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Path,
        [switch] $RequiresAdmin,
        [switch] $AggressiveOnly,
        [int] $MinimumAgeDays = 7
    )

    [PSCustomObject]@{
        Name           = $Name
        Path           = [Environment]::ExpandEnvironmentVariables($Path)
        RequiresAdmin  = [bool] $RequiresAdmin
        AggressiveOnly = [bool] $AggressiveOnly
        MinimumAgeDays = $MinimumAgeDays
    }
}

function Add-CleanupTarget {
    param(
        [System.Collections.Generic.List[object]] $Targets,
        [System.Collections.Generic.HashSet[string]] $Seen,
        [object] $Target
    )

    if ([string]::IsNullOrWhiteSpace($Target.Path)) {
        return
    }

    try {
        $normalized = [System.IO.Path]::GetFullPath($Target.Path.TrimEnd('\'))
    } catch {
        return
    }

    if ($Seen.Add($normalized.ToLowerInvariant())) {
        $Targets.Add($Target) | Out-Null
    }
}

function Add-ProfileCacheTargets {
    param(
        [System.Collections.Generic.List[object]] $Targets,
        [System.Collections.Generic.HashSet[string]] $Seen,
        [string] $BasePath,
        [string[]] $RelativeCachePaths,
        [string] $NamePrefix,
        [int] $MinimumAgeDays,
        [string] $ProfileMarkerFile = ''
    )

    if (-not (Test-Path -LiteralPath $BasePath)) {
        return
    }

    Get-ChildItem -LiteralPath $BasePath -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($ProfileMarkerFile)) {
            $markerPath = Join-Path $_.FullName $ProfileMarkerFile
            if (-not (Test-Path -LiteralPath $markerPath)) {
                return
            }
        }

        foreach ($relative in $RelativeCachePaths) {
            $cachePath = Join-Path $_.FullName $relative
            Add-CleanupTarget -Targets $Targets -Seen $Seen -Target (
                New-CleanupTarget -Name "$NamePrefix $($_.Name) $relative" -Path $cachePath -MinimumAgeDays $MinimumAgeDays
            )
        }
    }
}

function Get-CleanupTargets {
    param(
        [int] $MinimumAgeDays,
        [switch] $IncludeAggressive
    )

    $targets = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($path in @($env:TEMP, $env:TMP, [System.IO.Path]::GetTempPath())) {
        Add-CleanupTarget -Targets $targets -Seen $seen -Target (
            New-CleanupTarget -Name 'User temporary files' -Path $path -MinimumAgeDays $MinimumAgeDays
        )
    }

    $systemTargets = @(
        (New-CleanupTarget -Name 'Windows temporary files' -Path (Join-Path $env:windir 'Temp') -RequiresAdmin -MinimumAgeDays $MinimumAgeDays),
        (New-CleanupTarget -Name 'Windows Update download cache' -Path (Join-Path $env:windir 'SoftwareDistribution\Download') -RequiresAdmin -MinimumAgeDays $MinimumAgeDays),
        (New-CleanupTarget -Name 'Delivery Optimization cache' -Path (Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization\Cache') -RequiresAdmin -MinimumAgeDays $MinimumAgeDays),
        (New-CleanupTarget -Name 'Machine error reports' -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') -RequiresAdmin -MinimumAgeDays $MinimumAgeDays),
        (New-CleanupTarget -Name 'Queued machine error reports' -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') -RequiresAdmin -MinimumAgeDays $MinimumAgeDays),
        (New-CleanupTarget -Name 'CBS archived logs' -Path (Join-Path $env:windir 'Logs\CBS') -RequiresAdmin -MinimumAgeDays 30),
        (New-CleanupTarget -Name 'DISM archived logs' -Path (Join-Path $env:windir 'Logs\DISM') -RequiresAdmin -MinimumAgeDays 30)
    )

    foreach ($target in $systemTargets) {
        Add-CleanupTarget -Targets $targets -Seen $seen -Target $target
    }

    $userReportRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'
    foreach ($relative in @('ReportArchive', 'ReportQueue')) {
        Add-CleanupTarget -Targets $targets -Seen $seen -Target (
            New-CleanupTarget -Name "User error reports $relative" -Path (Join-Path $userReportRoot $relative) -MinimumAgeDays $MinimumAgeDays
        )
    }

    Add-ProfileCacheTargets -Targets $targets -Seen $seen `
        -BasePath (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') `
        -RelativeCachePaths @('Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') `
        -NamePrefix 'Chrome profile' `
        -MinimumAgeDays $MinimumAgeDays `
        -ProfileMarkerFile 'Preferences'

    Add-ProfileCacheTargets -Targets $targets -Seen $seen `
        -BasePath (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') `
        -RelativeCachePaths @('Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') `
        -NamePrefix 'Edge profile' `
        -MinimumAgeDays $MinimumAgeDays `
        -ProfileMarkerFile 'Preferences'

    Add-ProfileCacheTargets -Targets $targets -Seen $seen `
        -BasePath (Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles') `
        -RelativeCachePaths @('cache2', 'startupCache') `
        -NamePrefix 'Firefox profile' `
        -MinimumAgeDays $MinimumAgeDays `
        -ProfileMarkerFile 'prefs.js'

    if ($IncludeAggressive) {
        $aggressiveTargets = @(
            (New-CleanupTarget -Name 'Package cache npm' -Path (Join-Path $env:APPDATA 'npm-cache') -AggressiveOnly -MinimumAgeDays $MinimumAgeDays),
            (New-CleanupTarget -Name 'Package cache Yarn' -Path (Join-Path $env:LOCALAPPDATA 'Yarn\Cache') -AggressiveOnly -MinimumAgeDays $MinimumAgeDays),
            (New-CleanupTarget -Name 'Package cache pip' -Path (Join-Path $env:LOCALAPPDATA 'pip\Cache') -AggressiveOnly -MinimumAgeDays $MinimumAgeDays),
            (New-CleanupTarget -Name 'Package cache NuGet' -Path (Join-Path $env:LOCALAPPDATA 'NuGet\Cache') -AggressiveOnly -MinimumAgeDays $MinimumAgeDays),
            (New-CleanupTarget -Name 'Legacy upgrade folder Windows.old' -Path (Join-Path $env:SystemDrive 'Windows.old') -RequiresAdmin -AggressiveOnly -MinimumAgeDays 14),
            (New-CleanupTarget -Name 'Legacy upgrade folder BT' -Path (Join-Path $env:SystemDrive '$WINDOWS.~BT') -RequiresAdmin -AggressiveOnly -MinimumAgeDays 14)
        )

        foreach ($target in $aggressiveTargets) {
            Add-CleanupTarget -Targets $targets -Seen $seen -Target $target
        }
    }

    return $targets
}

function Get-CandidateFiles {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][datetime] $Cutoff
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    @(Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $Cutoff })
}

function Remove-EmptyDirectories {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][datetime] $Cutoff
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Force -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Where-Object { $_.LastWriteTime -lt $Cutoff } |
        ForEach-Object {
            $firstChild = Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $firstChild) {
                return
            }

            try {
                Remove-Item -LiteralPath $_.FullName -Force -Confirm:$false -ErrorAction Stop
            } catch {
                $Script:SkippedCount++
            }
        }
}

function Invoke-CleanupTarget {
    param(
        [Parameter(Mandatory = $true)] $Target,
        [switch] $DryRun,
        [bool] $IsAdmin
    )

    if ($Target.RequiresAdmin -and -not $IsAdmin) {
        Write-Log "Skip $($Target.Name): Administrator rights required." 'WARN'
        $Script:SkippedCount++
        return
    }

    if (-not (Test-Path -LiteralPath $Target.Path)) {
        Write-Log "Skip $($Target.Name): path not found."
        return
    }

    if (-not (Test-SafeCleanupPath -Path $Target.Path)) {
        Write-Log "Skip $($Target.Name): path failed safety validation." 'WARN'
        $Script:SkippedCount++
        return
    }

    $cutoff = (Get-Date).AddDays(-[int] $Target.MinimumAgeDays)
    $files = @(Get-CandidateFiles -Path $Target.Path -Cutoff $cutoff)
    $bytes = 0L
    foreach ($file in $files) {
        $bytes += [Int64] $file.Length
    }

    if ($files.Count -eq 0) {
        Write-Log "No eligible files in $($Target.Name)."
        return
    }

    if ($DryRun) {
        Write-Log ("DRY RUN: {0} would remove {1} files, estimated {2}, from {3}" -f $Target.Name, $files.Count, (Convert-ByteSize $bytes), $Target.Path)
        return
    }

    Write-Log ("Cleaning {0}: {1} files, estimated {2}" -f $Target.Name, $files.Count, (Convert-ByteSize $bytes))

    foreach ($file in $files) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $Script:RemovedCount++
            $Script:ReclaimedBytes += [Int64] $file.Length
        } catch {
            $Script:SkippedCount++
        }
    }

    Remove-EmptyDirectories -Path $Target.Path -Cutoff $cutoff
}

function Stop-CleanupServices {
    param([string[]] $Names)

    $stopped = New-Object 'System.Collections.Generic.List[string]'

    foreach ($name in $Names) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status -eq 'Running') {
            try {
                Write-Log "Stopping service $name."
                Stop-Service -Name $name -Force -WarningAction SilentlyContinue -ErrorAction Stop
                $stopped.Add($name) | Out-Null
            } catch {
                Write-Log "Could not stop service $name : $($_.Exception.Message)" 'WARN'
            }
        }
    }

    return $stopped
}

function Start-CleanupServices {
    param([string[]] $Names)

    foreach ($name in $Names) {
        try {
            Write-Log "Starting service $name."
            Start-Service -Name $name -ErrorAction Stop
        } catch {
            Write-Log "Could not start service $name : $($_.Exception.Message)" 'WARN'
        }
    }
}

function Invoke-RecycleBinCleanup {
    param([switch] $DryRun)

    if ($DryRun) {
        Write-Log 'DRY RUN: would run Clear-RecycleBin.'
        return
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log 'Recycle bin cleaned.'
    } catch {
        Write-Log "Recycle bin cleanup skipped: $($_.Exception.Message)" 'WARN'
        $Script:SkippedCount++
    }
}

function Invoke-DismComponentCleanup {
    param(
        [switch] $DryRun,
        [bool] $IsAdmin
    )

    if (-not $IsAdmin) {
        Write-Log 'Skip component cleanup: Administrator rights required.' 'WARN'
        return
    }

    if ($DryRun) {
        Write-Log 'DRY RUN: would run DISM StartComponentCleanup.'
        return
    }

    $dism = Join-Path $env:windir 'System32\dism.exe'
    if (-not (Test-Path -LiteralPath $dism)) {
        $dism = 'dism.exe'
    }

    try {
        Write-Log 'Starting DISM component cleanup. This may take several minutes.'
        $process = Start-Process -FilePath $dism -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log 'DISM component cleanup completed.'
        } else {
            Write-Log "DISM component cleanup exited with code $($process.ExitCode)." 'WARN'
        }
    } catch {
        Write-Log "DISM component cleanup failed: $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-SafeDiskCleanup {
    param(
        [switch] $DryRun,
        [switch] $Aggressive,
        [ValidateRange(0, 3650)]
        [int] $MinAgeDays = 7,
        [string] $LogPath = '',
        [switch] $OpenWizTree,
        [string] $WizTreePath = '',
        [string] $ScanPath = $env:SystemDrive,
        [switch] $IncludeDism
    )

    Initialize-LogPath -RequestedLogPath $LogPath

    $isAdmin = Test-IsAdministrator
    $mode = if ($DryRun) { 'dry-run' } else { 'cleanup' }
    $scope = if ($Aggressive) { 'aggressive' } else { 'conservative' }
    Write-Log "SafeDiskCleanup started. Mode=$mode Scope=$scope MinAgeDays=$MinAgeDays IsAdmin=$isAdmin"
    Write-Log "Log path: $Script:CleanupLogPath"

    if ($OpenWizTree) {
        $wizTreeExecutable = Resolve-WizTreeExecutable -RequestedPath $WizTreePath
        Start-WizTreeScan -ExecutablePath $wizTreeExecutable -ScanPath $ScanPath -IsAdmin:$isAdmin
    }

    $stoppedServices = @()
    if ($isAdmin -and -not $DryRun) {
        $stoppedServices = @(Stop-CleanupServices -Names @('wuauserv', 'bits', 'dosvc'))
    }

    try {
        $targets = Get-CleanupTargets -MinimumAgeDays $MinAgeDays -IncludeAggressive:$Aggressive
        foreach ($target in $targets) {
            Invoke-CleanupTarget -Target $target -DryRun:$DryRun -IsAdmin:$isAdmin
        }
    } finally {
        if ($stoppedServices.Count -gt 0) {
            Start-CleanupServices -Names $stoppedServices
        }
    }

    Invoke-RecycleBinCleanup -DryRun:$DryRun
    if ($IncludeDism) {
        Invoke-DismComponentCleanup -DryRun:$DryRun -IsAdmin:$isAdmin
    } else {
        Write-Log 'Skip DISM component cleanup by default. Pass -IncludeDism to run Windows component cleanup.'
    }

    if ($DryRun) {
        Write-Log 'Dry run completed. No files were deleted.'
    } else {
        Write-Log ("Cleanup completed. Removed files={0}, skipped={1}, estimated reclaimed={2}" -f $Script:RemovedCount, $Script:SkippedCount, (Convert-ByteSize $Script:ReclaimedBytes))
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SafeDiskCleanup @PSBoundParameters
}
