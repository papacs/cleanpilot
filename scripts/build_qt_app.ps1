[CmdletBinding()]
param(
    [string] $Python = 'python',
    [string] $WheelDir = 'tools\wheels'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$venvPath = Join-Path $repoRoot '.venv-qt'
$wheelPath = Join-Path $repoRoot $WheelDir
$distPath = Join-Path $repoRoot 'dist\CleanPilot'

if (-not (Test-Path -LiteralPath $wheelPath)) {
    throw "Wheel cache not found at $wheelPath. Run scripts\download_qt_wheels.ps1 first."
}

if (-not (Test-Path -LiteralPath $venvPath)) {
    & $Python -m venv $venvPath
}

$venvPython = Join-Path $venvPath 'Scripts\python.exe'
& $venvPython -m pip install --no-index --find-links $wheelPath PySide6 shiboken6 PyInstaller

Push-Location $repoRoot
try {
    & $venvPython -m PyInstaller `
        --noconfirm `
        --clean `
        --name CleanPilot `
        --windowed `
        --add-data "SafeDiskCleanup.ps1;." `
        --add-data "Run-SafeDiskCleanup-AsAdmin.cmd;." `
        --add-data "src\cleanpilot_qt\resources\app.qss;src\cleanpilot_qt\resources" `
        "src\cleanpilot_qt\app.py"
} finally {
    Pop-Location
}

$exePath = Join-Path $distPath 'CleanPilot.exe'
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Build failed: CleanPilot.exe was not created at $exePath"
}

$scriptCopy = Join-Path $distPath 'SafeDiskCleanup.ps1'
if (-not (Test-Path -LiteralPath $scriptCopy -PathType Leaf)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'SafeDiskCleanup.ps1') -Destination $distPath -Force
}

$launcherCopy = Join-Path $distPath 'Run-SafeDiskCleanup-AsAdmin.cmd'
if (-not (Test-Path -LiteralPath $launcherCopy -PathType Leaf)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Run-SafeDiskCleanup-AsAdmin.cmd') -Destination $distPath -Force
}

Write-Host "Built CleanPilot desktop release at $distPath"
