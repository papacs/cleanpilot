@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%SafeDiskCleanup.ps1"

if not exist "%SCRIPT_PATH%" (
    echo SafeDiskCleanup.ps1 not found next to this launcher.
    pause
    exit /b 1
)

echo Starting SafeDiskCleanup with administrator rights...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%SCRIPT_PATH%""' -Verb RunAs"

endlocal
