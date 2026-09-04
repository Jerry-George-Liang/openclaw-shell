#!/bin/bash
set -e

CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ] && [ -z "${OPENCLAW_GATEWAY_PASSWORD:-}" ]; then
    echo "[ERROR] 必须设置 OPENCLAW_GATEWAY_TOKEN 或 OPENCLAW_GATEWAY_PASSWORD，拒绝无认证启动。" >&2
    exit 1
fi

if ! mkdir -p "$CONFIG_DIR/logs" "$CONFIG_DIR/data" "$CONFIG_DIR/skills" "$CONFIG_DIR/backups"; then
    echo "[ERROR] 无法写入 $CONFIG_DIR；Linux 请将宿主目录属主设为容器 node 用户 UID 1000，或改用 Docker named volume。" >&2
    exit 1
fi
if ! chmod 700 "$CONFIG_DIR"; then
    echo "[ERROR] 无法设置 $CONFIG_DIR 权限；请检查宿主目录挂载权限（容器以非 root node 用户运行）。" >&2
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    auth_mode=token
    [ -n "${OPENCLAW_GATEWAY_PASSWORD:-}" ] && [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ] && auth_mode=password
    printf '{\n  "gateway": {\n    "mode": "local",\n    "bind": "lan",\n    "auth": {"mode": "%s"}\n  }\n}\n' "$auth_mode" > "$CONFIG_FILE"
fi
chmod 600 "$CONFIG_FILE"

# 拒绝挂载了显式无认证配置的状态目录，避免 LAN Gateway 意外裸奔。
auth_mode=$(openclaw config get gateway.auth.mode 2>/dev/null || true)
if [ "$auth_mode" = "none" ]; then
    echo "[ERROR] 配置显式禁用了 Gateway 认证；请改用 token/password 后再启动。" >&2
    exit 1
fi

if ! openclaw config validate >/dev/null 2>&1; then
    echo "[ERROR] OpenClaw 配置校验失败: $CONFIG_FILE" >&2
    exit 1
fi

# 打印启动信息
echo ""
echo "🦞 OpenClaw Docker Container"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "配置目录: $CONFIG_DIR"
echo "日志目录: $CONFIG_DIR/logs"
echo "技能目录: $CONFIG_DIR/skills"
echo "网关端口: 18789"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 执行传入的命令
exec "$@"
