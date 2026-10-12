@echo off
setlocal
echo Installs Node.js LTS and cloudflared using Windows Package Manager.
echo An installer may ask for elevation. Reopen AVS afterwards to refresh PATH.
where winget >nul 2>&1
if errorlevel 1 (
  echo winget is missing. Install App Installer from Microsoft Store.
  echo Node: https://nodejs.org/en/download
  echo cloudflared: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
  pause
  exit /b 1
)
winget install --id OpenJS.NodeJS.LTS --exact --source winget --accept-package-agreements --accept-source-agreements
winget install --id Cloudflare.cloudflared --exact --source winget --accept-package-agreements --accept-source-agreements
echo Check installer results above. Close and reopen the AVS manager.
pause
