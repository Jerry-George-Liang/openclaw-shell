#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/install-windows.ps1"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

# This is a platform-neutral simulation of the Windows call boundary. It does
# not run Doctor or inspect a user's service; it verifies the wrapper keeps the
# child in the same console and treats ownership errors as a safe stop.
rg -Fq -- "Get-Command 'powershell.exe'" "$script" || fail "missing powershell.exe lookup"
rg -Fq -- '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command $isolatedCommand' "$script" || fail "Doctor is not launched in an isolated shell"
rg -Fq -- 'The child inherits this console, so Doctor prompts remain interactive.' "$script" || fail "interactive child-console contract is missing"
rg -Fq -- "Get-ScheduledTask -TaskName 'OpenClaw Gateway'" "$script" || fail "missing scheduled-task evidence check"
rg -Fq -- "Test-Path -LiteralPath \$gatewayCmdPath -PathType Leaf" "$script" || fail "missing gateway.cmd existence check"
rg -Fq -- 'gateway.cmd 启动器已缺失' "$script" || fail "missing missing-launcher diagnostic"
rg -Fq -- 'gateway install --force' "$script" || fail "missing official launcher repair command"
rg -Fq -- 'gateway\.(?:cmd|vbs)' "$script" || fail "missing vbs task-wrapper compatibility"
rg -Fq -- '$launcherRepaired' "$script" || fail "missing duplicate-install guard"
rg -Fq -- "Get-Command 'schtasks.exe'" "$script" || fail "missing schtasks fallback"
rg -Fq -- "schtasks.exe /Query /TN 'OpenClaw Gateway' /FO LIST /V" "$script" || fail "missing task action fallback"
rg -Fq -- '$runtimeNode = $status.service.runtime' "$script" || fail "missing nested runtime status compatibility"
rg -Fq -- 'Repair-MissingGatewayTask' "$script" || fail "missing broken-task repair path"
rg -Fq -- 'gateway-task-backup-' "$script" || fail "missing scheduled-task XML backup"
rg -Fq -- '/Delete /TN $Evidence.TaskName /F' "$script" || fail "missing explicit task deletion guard"
rg -Fq -- '[Console]::ReadKey($true)' "$script" || fail "API key input is not character-safe"
rg -Fq -- 'Write-Host '\''*'\'' -NoNewline' "$script" || fail "API key masking is missing"

launcher="$repo_root/install-windows.cmd"
rg -Fq -- 'curl.exe --fail --silent --show-error --location --retry 3' "$launcher" || fail "CMD launcher does not use curl retry path"
rg -Fq -- '--connect-timeout 15 --max-time 120' "$launcher" || fail "CMD launcher timeout is missing"
rg -Fq -- 'Invoke-RestMethod -Uri' "$launcher" || fail "CMD launcher lost PowerShell fallback"
rg -Fq -- 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OPENCLAW_INSTALLER_PATH%" %*' "$launcher" || fail "CMD launcher does not preserve arguments"

simulated_output=$'Gateway service ownership or shutdown could not be verified.\nSERVICE_DEFINITION_UNKNOWN'
if ! printf '%s\n' "$simulated_output" | rg -q '(Gateway service ownership or shutdown could not be verified|SERVICE_DEFINITION_UNKNOWN)'; then
    fail "ownership failure sample was not recognized"
fi

if printf '%s\n' 'Gateway service ownership verified.' | rg -q '(Gateway service ownership or shutdown could not be verified|SERVICE_DEFINITION_UNKNOWN)'; then
    fail "ownership success sample was misclassified"
fi

echo '[PASS] Windows Doctor isolated-shell simulation passed'
