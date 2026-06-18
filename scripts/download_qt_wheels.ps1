[CmdletBinding()]
param(
    [string] $Python = 'python',
    [string] $WheelDir = 'tools\wheels'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$wheelPath = Join-Path $repoRoot $WheelDir
New-Item -ItemType Directory -Path $wheelPath -Force | Out-Null

$versionText = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ([version]$versionText -lt [version]'3.10') {
    throw "Python 3.10 or newer is required. Found $versionText."
}

$packages = @(
    'PySide6==6.7.3',
    'shiboken6==6.7.3',
    'PyInstaller==6.10.0'
)

& $Python -m pip download --only-binary=:all: --dest $wheelPath @packages

Write-Host "Downloaded Qt desktop dependency wheels to $wheelPath"
