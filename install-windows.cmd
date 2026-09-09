@echo off
setlocal

rem Native cmd.exe launcher. The actual installer runs in PowerShell so that
rem UTF-8 input and interactive prompts work reliably on Windows.
chcp 65001 >nul
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Windows PowerShell 5.1 is required.
  exit /b 1
)

echo Starting OpenClaw Windows installer...
set "OPENCLAW_INSTALLER_PATH=%TEMP%\openclaw-installer-%RANDOM%-%RANDOM%.ps1"
set "OPENCLAW_INSTALLER_URL=https://raw.githubusercontent.com/Jerry-George-Liang/openclaw-shell/main/install-windows.ps1?cachebust=%RANDOM%%RANDOM%"
curl.exe --fail --silent --show-error --location --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 15 --max-time 120 -H "Cache-Control: no-cache" -o "%OPENCLAW_INSTALLER_PATH%" "%OPENCLAW_INSTALLER_URL%"
if errorlevel 1 (
  echo [WARN] curl.exe download failed; retrying with PowerShell HTTP client...
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop'; Invoke-RestMethod -Uri '%OPENCLAW_INSTALLER_URL%' -Headers @{'Cache-Control'='no-cache'} -OutFile '%OPENCLAW_INSTALLER_PATH%'"
)
if errorlevel 1 (
  echo [ERROR] Unable to download the Windows installer. Check network, proxy, or security software.
  del /q "%OPENCLAW_INSTALLER_PATH%" >nul 2>&1
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OPENCLAW_INSTALLER_PATH%" %*
set "OPENCLAW_INSTALLER_EXIT=%ERRORLEVEL%"
del /q "%OPENCLAW_INSTALLER_PATH%" >nul 2>&1
if not "%OPENCLAW_INSTALLER_EXIT%"=="0" (
  echo [ERROR] OpenClaw Windows installer failed.
  exit /b 1
)

endlocal
