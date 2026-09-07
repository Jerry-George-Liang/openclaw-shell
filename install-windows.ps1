param(
    [switch]$SkipOfficialInstall,
    [switch]$NoOnboard
)

$ErrorActionPreference = 'Stop'

# Keep Chinese and interactive prompts readable in Windows PowerShell 5.1.
try { chcp 65001 | Out-Null } catch {}
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

function Fail([string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Fail "Required command not found: $Name"
    }
}

Write-Host "OpenClaw Windows installer" -ForegroundColor Cyan
Write-Host "This is the native PowerShell entry point. Do not run install.sh from cmd.exe or Git Bash."
Write-Host ""

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Fail "PowerShell 5.1 or newer is required."
}

if (-not $SkipOfficialInstall) {
    Write-Host "Installing/updating OpenClaw with the official installer..." -ForegroundColor Yellow
    Require-Command 'Invoke-RestMethod'
    $official = Invoke-RestMethod -Uri 'https://openclaw.ai/install.ps1'
    # Keep onboarding in this wrapper so the prompt is rendered by the UTF-8
    # console configured above and is shown only once.
    & ([scriptblock]::Create([string]$official)) -NoOnboard
}

Require-Command 'openclaw'
$version = (& openclaw --version 2>$null | Select-Object -First 1)
Write-Host "OpenClaw detected: $version" -ForegroundColor Green

if (-not $NoOnboard) {
    $answer = Read-Host 'Run the OpenClaw onboarding wizard now? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(y|yes)$') {
        & openclaw onboard
        if ($LASTEXITCODE -ne 0) { Fail 'OpenClaw onboarding failed.' }
    }
}

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Start the Gateway: openclaw gateway start"
Write-Host "Open the terminal UI: openclaw tui"
Write-Host "Configure later: openclaw onboard"
