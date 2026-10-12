@echo off
setlocal
cd /d "%~dp0"

set "MANAGER=%~dp0AVS_BUILD_MANAGER.ps1"

if not exist "%MANAGER%" (
    echo ERROR: AVS_BUILD_MANAGER.ps1 was not found next to this BAT file.
    echo Keep all files from the kit in the same folder.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%MANAGER%"

if errorlevel 1 (
    echo.
    echo The AVS Build Manager could not start.
    pause
)

endlocal
