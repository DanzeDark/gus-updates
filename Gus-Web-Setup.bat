@echo off
chcp 65001 >nul
set "BASE_URL=https://danzedark.github.io/gus-updates"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$base=$env:BASE_URL.TrimEnd('/');$url=$base+'/Install-Gus-Web.ps1';$tmp=Join-Path ([IO.Path]::GetTempPath()) ('Install-Gus-Web_'+[Guid]::NewGuid().ToString('N')+'.ps1');try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing;& $tmp -BaseUrl $base;$code=$LASTEXITCODE}catch{Write-Host $_ -ForegroundColor Red;$code=1}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue};exit $code"
if errorlevel 1 (
  echo.
  echo Installer failed.
  pause
)
