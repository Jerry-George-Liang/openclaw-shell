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

for script_file in install.sh config-menu.sh docker-entrypoint.sh scripts/preflight-check.sh scripts/test-windows-doctor-call.sh; do
    bash -n "$script_file" || fail "shell syntax check failed: $script_file"
done

test -f install-windows.ps1 || fail "missing native Windows installer"
test -f install-windows.cmd || fail "missing cmd.exe Windows launcher"
rg -Fq -- "openclaw.ai/install.ps1" install-windows.ps1 || fail "Windows installer does not use official installer"
rg -Fq -- "Do not run install.sh from cmd.exe or Git Bash" install-windows.ps1 || fail "Windows terminal guidance is missing"
rg -Fq -- "Invoke-RestMethod" install-windows.cmd || fail "cmd.exe launcher does not delegate to PowerShell"
require_text "[Guid]::NewGuid().ToString('N')" install-windows.cmd
require_text "'Cache-Control'='no-cache'" install-windows.cmd
require_text "Installer version: \$InstallerVersion" install-windows.ps1
require_text '2026.09.08.10' install-windows.ps1
require_text 'install-windows.ps1?cachebust=' install-windows.ps1
require_text 'Configure-Tuzi' install-windows.ps1
require_text 'https://api.tu-zi.com/v1/models' install-windows.ps1
require_text 'Get-TuziModelsViaNode' install-windows.ps1
require_text 'OPENCLAW_TUZI_KEY' install-windows.ps1
require_text 'PowerShell 获取 Tuzi 模型列表失败，改用 Node.js 网络兼容通道重试' install-windows.ps1
require_text '已通过 Node.js 兼容通道获取' install-windows.ps1
require_text "addProvider('gac-claude'" install-windows.ps1
require_text "addProvider('gac-codex'" install-windows.ps1
require_text 'openclaw agent exec' install-windows.ps1
require_text '不写入 session main' install-windows.ps1
require_text 'windowsCleanupOnly' install-windows.ps1
require_text 'provider-transport-fetch.*response.*status=200' install-windows.ps1
require_text 'Agent exec cleanup failed:.*EBUSY' install-windows.ps1
require_text '本次结果按连接成功处理' install-windows.ps1
require_text 'Remove-AgentExecTempState' install-windows.ps1
require_text "\$agentName -like 'openclaw-agent-exec-*'" install-windows.ps1
require_text '[StringComparison]::OrdinalIgnoreCase' install-windows.ps1
require_text '安装器已清除本次隔离测试目录' install-windows.ps1
require_text "\$ErrorActionPreference = 'Continue'" install-windows.ps1
require_text '$ErrorActionPreference = $previousErrorActionPreference' install-windows.ps1
require_text 'NativeCommandError' install-windows.ps1
require_text 'openclaw gateway install' install-windows.ps1
require_text 'openclaw gateway start' install-windows.ps1
require_text 'openclaw gateway status --deep' install-windows.ps1
require_text '官方安装器的服务迁移未完成' install-windows.ps1
require_text 'Resolve-OpenClawRuntime' install-windows.ps1
require_text "'openclaw.cmd'" install-windows.ps1
require_text "Join-Path \$env:APPDATA 'npm'" install-windows.ps1
require_text '当前终端尚未找到可运行的命令' install-windows.ps1
require_text '已跳过 AI 连接测试' install-windows.ps1
require_text 'SERVICE_DEFINITION_UNKNOWN' install-windows.ps1
require_text 'Gateway service ownership or shutdown could not be verified' install-windows.ps1
require_text 'gatewayOwnershipFailure' install-windows.ps1
require_text 'knownGatewayMigrationFailure' install-windows.ps1
require_text '-NoOnboard 2>&1 6>&1' install-windows.ps1
require_text 'Setup-Gateway $officialInstallerWarning $openclawRuntime.Path' install-windows.ps1
require_text 'Invoke-OpenClawStateRepair' install-windows.ps1
require_text "Get-Command 'powershell.exe'" install-windows.ps1
require_text '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command' install-windows.ps1
require_text 'The child inherits this console, so Doctor prompts remain interactive.' install-windows.ps1
require_text '独立 PowerShell 仍无法确认 Gateway 服务归属或停止状态' install-windows.ps1
require_text 'Left legacy agent dir at .*agent\.legacy-' install-windows.ps1
require_text '状态迁移修复成功' install-windows.ps1
require_text "\$installArgs += '--force'" install-windows.ps1
require_text 'Test-OpenClawGatewayReady' install-windows.ps1
require_text 'gateway status --deep --json' install-windows.ps1
require_text 'Gateway 已启动并通过连接检查' install-windows.ps1
require_text '计划任务可能立即退出' install-windows.ps1
require_text 'Setup-Gateway $officialInstallerWarning $openclawRuntime.Path $stateRepairCompleted' install-windows.ps1
require_text 'Inspect the existing service: openclaw gateway status --deep' install-windows.ps1
require_text 'Temporary foreground Gateway: openclaw gateway run' install-windows.ps1
require_text 'bak-' install-windows.ps1
bash scripts/test-windows-doctor-call.sh
if rg -Fq -- '& openclaw onboard' install-windows.ps1; then
    fail "Windows installer still launches the official provider onboarding"
fi

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
require_text 'brew unlink node' install.sh
require_text 'brew --prefix node@22' install.sh
require_text 'activate_system_node_runtime' install.sh
require_text '/usr/bin/node' install.sh
require_text 'prepare_npm_cache' install.sh
require_text 'NPM_CONFIG_CACHE' install.sh
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
