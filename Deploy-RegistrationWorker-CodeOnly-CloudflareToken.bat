@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-RegistrationWorker.ps1" -UseCloudflareApiToken -DeployOnly
if errorlevel 1 (
  echo.
  echo Worker deploy failed.
  pause
  exit /b 1
)
echo.
echo Worker deploy finished.
pause
