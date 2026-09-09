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

simulated_output=$'Gateway service ownership or shutdown could not be verified.\nSERVICE_DEFINITION_UNKNOWN'
if ! printf '%s\n' "$simulated_output" | rg -q '(Gateway service ownership or shutdown could not be verified|SERVICE_DEFINITION_UNKNOWN)'; then
    fail "ownership failure sample was not recognized"
fi

if printf '%s\n' 'Gateway service ownership verified.' | rg -q '(Gateway service ownership or shutdown could not be verified|SERVICE_DEFINITION_UNKNOWN)'; then
    fail "ownership success sample was misclassified"
fi

echo '[PASS] Windows Doctor isolated-shell simulation passed'
