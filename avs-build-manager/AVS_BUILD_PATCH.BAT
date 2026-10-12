@echo off
cd /d "%~dp0"
rem Builds a patch with the settings saved by the new manager.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AVS_BUILD_FROM_CONFIG.ps1" -Mode Patch
