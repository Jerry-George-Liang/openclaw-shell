#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

require_text() {
    local text="$1"
    shift
    rg -Fq -- "$text" "$@" || fail "missing expected text: $text"
}

for script_file in install.sh config-menu.sh docker-entrypoint.sh scripts/preflight-check.sh; do
    bash -n "$script_file" || fail "shell syntax check failed: $script_file"
done

test -f install-windows.ps1 || fail "missing native Windows installer"
rg -Fq -- "openclaw.ai/install.ps1" install-windows.ps1 || fail "Windows installer does not use official installer"
rg -Fq -- "openclaw onboard" install-windows.ps1 || fail "Windows onboarding path is missing"
rg -Fq -- "Do not run install.sh from cmd.exe or Git Bash" install-windows.ps1 || fail "Windows terminal guidance is missing"

for forbidden in \
    'models.default' \
    '@m1heng-clawd/feishu' \
    'cwj526/OpenClawInstaller' \
    'tuziapi/OpenClawInstaller' \
    'clawd.bot' \
    'npm update -g openclaw' \
    'start --daemon' \
    'config.yaml'; do
    if rg -Fq -- "$forbidden" install.sh config-menu.sh Dockerfile docker-compose.yml docker-entrypoint.sh README.md docs examples; then
        fail "obsolete OpenClaw reference remains: $forbidden"
    fi
done

require_text 'openclaw gateway install' install.sh config-menu.sh
require_text 'openclaw agent exec' install.sh config-menu.sh
require_text '不写入会话历史' install.sh config-menu.sh
require_text 'GITHUB_REPO="Jerry-George-Liang/openclaw-shell"' install.sh
require_text 'openclaw update --dry-run' config-menu.sh
require_text 'package manager owner is unknown' config-menu.sh
require_text '重新运行官方安装器建立 npm/pnpm/Bun 的安装关联' config-menu.sh
require_text 'openclaw channels login --channel feishu' config-menu.sh
require_text '@openclaw/feishu' config-menu.sh
require_text '--allow-scripts=openclaw' install.sh Dockerfile
require_text 'gateway run' Dockerfile README.md
require_text 'OPENCLAW_GATEWAY_TOKEN' docker-entrypoint.sh docker-compose.yml README.md
require_text '22-bookworm-slim' Dockerfile docker-compose.yml
require_text 'tini' Dockerfile
require_text 'USER node' Dockerfile
require_text '/home/node/.openclaw' Dockerfile docker-entrypoint.sh docker-compose.yml
require_text '只更新当前提供商变量' config-menu.sh
require_text 'gateway.auth.mode' install.sh config-menu.sh
require_text 'Windows 请在 PowerShell' install.sh
require_text 'NODE_INSTALL_MAJOR="22"' install.sh
require_text 'setup_${NODE_INSTALL_MAJOR}.x' install.sh
require_text 'node@22' install.sh
require_text 'OSTYPE" == mingw*' install.sh config-menu.sh
require_text 'run_privileged' install.sh
require_text 'CPU 架构' install.sh
require_text 'run_privileged dnf install' install.sh
if ! awk '/PACKAGE_MANAGER=/{print NR ":" $0}' install.sh | head -3 | grep -q 'dnf'; then
    fail "dnf detection branch is missing"
fi
require_text '显式禁用了 Gateway 认证' docker-entrypoint.sh

OPENCLAW_INSTALLER_LIB_ONLY=1 bash -c '
    source ./install.sh
    is_supported_node_version 22.22.2 && exit 1
    is_supported_node_version 22.22.3
    is_supported_node_version 23.9.0 && exit 1
    is_supported_node_version 24.14.9 && exit 1
    is_supported_node_version 24.15.0
    is_supported_node_version 25.8.9 && exit 1
    is_supported_node_version 25.9.0
    is_supported_node_version 26.0.0
'

test_home="$(mktemp -d)"
HOME="$test_home" OPENCLAW_CONFIG_MENU_LIB_ONLY=1 bash -c '
    set -eu
    source ./config-menu.sh
    mkdir -p "$HOME/.openclaw"
    printf "%s\n" "export OPENAI_API_KEY=old-key" "export CUSTOM_KEEP=keep-me" > "$OPENCLAW_ENV"
    set_env_kv "$OPENCLAW_ENV" ANTHROPIC_API_KEY "new key with spaces"
    grep -Fq "export OPENAI_API_KEY=old-key" "$OPENCLAW_ENV"
    grep -Fq "export CUSTOM_KEEP=keep-me" "$OPENCLAW_ENV"
    grep -Fq "export ANTHROPIC_API_KEY=new\\ key\\ with\\ spaces" "$OPENCLAW_ENV"
    write_tuzi_env_file "tuzi-key" "tuzi-model" "tuzi-model" "" "" "" "" "" "" "" ""
    grep -Fq "export ANTHROPIC_API_KEY=new\\ key\\ with\\ spaces" "$OPENCLAW_ENV"
    grep -Fq "export OPENAI_API_KEY=old-key" "$OPENCLAW_ENV"
'
rm -rf "$test_home"

rollback_home="$(mktemp -d)"
HOME="$rollback_home" OPENCLAW_CONFIG_MENU_LIB_ONLY=1 bash -c '
    set -eu
    source ./config-menu.sh
    mkdir -p "$HOME/.openclaw"
    printf "%s\n" "export CUSTOM_KEEP=keep-me" > "$OPENCLAW_ENV"
    env_backup=$(begin_config_transaction "$OPENCLAW_ENV")
    set_env_kv "$OPENCLAW_ENV" ANTHROPIC_API_KEY "temporary"
    rollback_config_transaction "$OPENCLAW_ENV" "$env_backup"
    grep -Fq "export CUSTOM_KEEP=keep-me" "$OPENCLAW_ENV"
    ! grep -Fq "ANTHROPIC_API_KEY" "$OPENCLAW_ENV"
'
rm -rf "$rollback_home"

invalid_config_home="$(mktemp -d)"
HOME="$invalid_config_home" OPENCLAW_INSTALLER_LIB_ONLY=1 bash -c '
    set -eu
    source ./install.sh
    mkdir -p "$HOME/.openclaw"
    printf "%s\n" "{ invalid configuration" > "$HOME/.openclaw/openclaw.json"
    if ensure_json_config_parseable "$HOME/.openclaw/openclaw.json"; then
        exit 1
    fi
    grep -Fq "{ invalid configuration" "$HOME/.openclaw/openclaw.json"
'
rm -rf "$invalid_config_home"

echo '[PASS] OpenClaw compatibility preflight passed'
