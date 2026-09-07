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
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $script = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Jerry-George-Liang/openclaw-shell/main/install-windows.ps1'; & ([scriptblock]::Create([string]$script))"
if errorlevel 1 (
  echo [ERROR] OpenClaw Windows installer failed.
  exit /b 1
)

endlocal
