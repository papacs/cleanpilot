$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw "ASSERT FAILED: $Message"
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$scriptPath = Join-Path $repoRoot 'SafeDiskCleanup.ps1'
$launcherPath = Join-Path $repoRoot 'Run-SafeDiskCleanup-AsAdmin.cmd'

Assert-True (Test-Path -LiteralPath $scriptPath) "Expected cleanup script at $scriptPath"
Assert-True (Test-Path -LiteralPath $launcherPath) "Expected manual launcher at $launcherPath"

$content = Get-Content -LiteralPath $scriptPath -Raw
$launcherContent = Get-Content -LiteralPath $launcherPath -Raw
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $tokens, [ref] $parseErrors)

Assert-True ($parseErrors.Count -eq 0) ("PowerShell parser errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
Assert-True ($null -ne $ast.ParamBlock) 'Script must define a top-level param block'

$paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($requiredParam in @('DryRun', 'Aggressive', 'MinAgeDays', 'LogPath', 'OpenWizTree', 'WizTreePath', 'ScanPath', 'IncludeDism')) {
    Assert-True ($paramNames -contains $requiredParam) "Missing parameter: $requiredParam"
}

foreach ($removedParam in @('InstallScheduledTask', 'UninstallScheduledTask')) {
    Assert-True ($paramNames -notcontains $removedParam) "Scheduling parameter should not exist: $removedParam"
}

$functionNames = @(
    $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true) | ForEach-Object { $_.Name }
)

foreach ($requiredFunction in @(
    'Test-IsAdministrator',
    'Write-Log',
    'Get-DirectorySize',
    'New-CleanupTarget',
    'Remove-EmptyDirectories',
    'Resolve-WizTreeExecutable',
    'Start-WizTreeScan',
    'Invoke-CleanupTarget',
    'Invoke-DismComponentCleanup',
    'Invoke-SafeDiskCleanup'
)) {
    Assert-True ($functionNames -contains $requiredFunction) "Missing function: $requiredFunction"
}

$removeEmptyFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Remove-EmptyDirectories'
}, $true)
Assert-True ($null -ne $removeEmptyFunction) 'Remove-EmptyDirectories function must exist'
Assert-True ($removeEmptyFunction.Extent.Text -match '(?s)Remove-Item.+-Confirm:\$false') 'Empty directory deletion must explicitly suppress confirmation prompts'

$stopServicesFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Stop-CleanupServices'
}, $true)
Assert-True ($null -ne $stopServicesFunction) 'Stop-CleanupServices function must exist'
Assert-True ($stopServicesFunction.Extent.Text -match '(?s)Stop-Service.+-WarningAction\s+SilentlyContinue') 'Service stop should suppress native waiting warnings and use script logs instead'

$initializeLogPathFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Initialize-LogPath'
}, $true)
Assert-True ($null -ne $initializeLogPathFunction) 'Initialize-LogPath function must exist'
Assert-True ($initializeLogPathFunction.Extent.Text -match '\$PID') 'Default log path should include the process id to avoid same-second collisions'

$writeLogFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Write-Log'
}, $true)
Assert-True ($null -ne $writeLogFunction) 'Write-Log function must exist'
Assert-True ($writeLogFunction.Extent.Text -match '(?s)for\s*\(.+Add-Content.+Start-Sleep') 'Log writes should retry briefly before warning about transient file locks'

$invokeSafeFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Invoke-SafeDiskCleanup'
}, $true)
Assert-True ($null -ne $invokeSafeFunction) 'Invoke-SafeDiskCleanup function must exist'
$invokeSafeText = $invokeSafeFunction.Extent.Text
Assert-True ($invokeSafeText -match '\[switch\]\s+\$IncludeDism') 'Invoke-SafeDiskCleanup must expose IncludeDism'
Assert-True ($invokeSafeText -match '(?s)if\s*\(\s*\$IncludeDism\s*\).+Invoke-DismComponentCleanup') 'DISM component cleanup must only run when IncludeDism is set'
Assert-True ($invokeSafeText -match 'Skip DISM component cleanup by default') 'Default run should log that DISM is skipped unless IncludeDism is set'

foreach ($removedFunction in @('Install-SafeCleanupTask', 'Uninstall-SafeCleanupTask')) {
    Assert-True ($functionNames -notcontains $removedFunction) "Scheduling function should not exist: $removedFunction"
}

foreach ($unsafePattern in @(
    '(?i)ResetBase',
    '(?i)vssadmin',
    '(?i)Delete\s+Shadows',
    '(?i)pnputil',
    '(?i)DriverStore',
    '(?i)\\Downloads\\',
    '(?i)\\Desktop\\',
    '(?i)\\Documents\\',
    '(?i)\\Pictures\\',
    '(?i)\\Videos\\',
    '(?i)\\Music\\',
    '(?i)Register-ScheduledTask',
    '(?i)Unregister-ScheduledTask',
    '(?i)New-ScheduledTask'
)) {
    Assert-True ($content -notmatch $unsafePattern) "Unsafe pattern found: $unsafePattern"
}

foreach ($requiredPattern in @(
    '\$DryRun',
    '\$Aggressive',
    '\$OpenWizTree',
    '\$IncludeDism',
    'tools\\WizTree\\WizTree64\.exe',
    '/admin=1',
    'StartComponentCleanup',
    'Clear-RecycleBin',
    'SoftwareDistribution\\Download',
    'DeliveryOptimization\\Cache',
    'Windows temporary files'
)) {
    Assert-True ($content -match $requiredPattern) "Required pattern missing: $requiredPattern"
}

foreach ($requiredLauncherPattern in @(
    'Start-Process',
    'RunAs',
    'SafeDiskCleanup\.ps1',
    '-ExecutionPolicy Bypass'
)) {
    Assert-True ($launcherContent -match $requiredLauncherPattern) "Launcher pattern missing: $requiredLauncherPattern"
}

. $scriptPath

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("SafeDiskCleanup-Test-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    $emptyOldDir = Join-Path $tempRoot 'empty-old'
    $nonEmptyOldDir = Join-Path $tempRoot 'nonempty-old'
    New-Item -ItemType Directory -Path $emptyOldDir -Force | Out-Null
    New-Item -ItemType Directory -Path $nonEmptyOldDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nonEmptyOldDir 'keep.txt') -Value 'keep'

    $oldTime = (Get-Date).AddDays(-10)
    (Get-Item -LiteralPath $emptyOldDir).LastWriteTime = $oldTime
    (Get-Item -LiteralPath $nonEmptyOldDir).LastWriteTime = $oldTime

    $Script:SkippedCount = 0
    Remove-EmptyDirectories -Path $tempRoot -Cutoff (Get-Date).AddDays(-7)

    Assert-True (-not (Test-Path -LiteralPath $emptyOldDir)) 'Stale empty directories should be removed'
    Assert-True (Test-Path -LiteralPath $nonEmptyOldDir) 'Stale non-empty directories should not be removed'
    Assert-True ($Script:SkippedCount -eq 0) 'Stale non-empty directories should not be counted as failed deletions'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'PASS: SafeDiskCleanup static validation succeeded.'
