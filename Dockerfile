# ============================================================
# OpenClaw Docker 镜像
# 
# 构建: docker build -t openclaw .
# 运行: docker run -d --name openclaw -v ~/.openclaw:/home/node/.openclaw openclaw
# ============================================================

ARG NODE_VERSION=22-bookworm-slim
FROM node:${NODE_VERSION}

LABEL maintainer="OpenClaw Community"
LABEL description="OpenClaw - Your Personal AI Assistant"
LABEL version="1.0.0"

# Debian slim 与 OpenClaw 官方容器基线一致，覆盖 amd64/arm64 并兼容原生模块。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl git jq tini tzdata \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建工作目录
WORKDIR /app

# 安装 OpenClaw
ARG OPENCLAW_VERSION=2026.9.2
RUN set -eux; \
    if node -e 'const [major, minor] = process.argv[1].split(".").map(Number); process.exit(major > 11 || (major === 11 && minor >= 16) ? 0 : 1)' "$(npm --version)"; then \
      npm install -g "openclaw@${OPENCLAW_VERSION}" --allow-scripts=openclaw; \
    else \
      npm install -g "openclaw@${OPENCLAW_VERSION}"; \
    fi

# 创建非 root 状态目录
RUN mkdir -p /home/node/.openclaw/logs \
    /home/node/.openclaw/data \
    /home/node/.openclaw/skills \
    /home/node/.openclaw/backups \
    && chown -R node:node /home/node/.openclaw

# 复制技能；配置由入口脚本按环境变量生成
COPY --chown=node:node examples/skills/ /home/node/.openclaw/skills/

# 设置卷挂载点
VOLUME ["/home/node/.openclaw"]

# 暴露端口
EXPOSE 18789

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD openclaw health || exit 1

# 入口脚本
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER node

ENTRYPOINT ["tini", "--", "docker-entrypoint.sh"]
CMD ["openclaw", "gateway", "run", "--bind", "lan", "--port", "18789"]
