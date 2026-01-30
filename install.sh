#!/bin/bash
#
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                                                                           ║
# ║   🦞 ClawdBot 一键部署脚本 v1.0.0                                          ║
# ║   智能 AI 助手部署工具 - 支持多平台多模型                                    ║
# ║                                                                           ║
# ║   GitHub: https://github.com/miaoxworld/ClawdBotInstaller                 ║
# ║   官方文档: https://clawd.bot/docs                                         ║
# ║                                                                           ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# 使用方法:
#   curl -fsSL https://raw.githubusercontent.com/miaoxworld/ClawdBotInstaller/main/install.sh | bash
#   或本地执行: chmod +x install.sh && ./install.sh
#

set -e

# ================================ TTY 检测 ================================
# 当通过 curl | bash 运行时，stdin 是管道，需要从 /dev/tty 读取用户输入
if [ -t 0 ]; then
    # stdin 是终端
    TTY_INPUT="/dev/stdin"
else
    # stdin 是管道，使用 /dev/tty
    TTY_INPUT="/dev/tty"
fi

# ================================ 颜色定义 ================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # 无颜色

# ================================ 配置变量 ================================
CLAWDBOT_VERSION="latest"
CONFIG_DIR="$HOME/.clawdbot"
MIN_NODE_VERSION=22
GITHUB_REPO="miaoxworld/ClawdBotInstaller"
GITHUB_RAW_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main"

# ================================ 工具函数 ================================

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    
     ██████╗██╗      █████╗ ██╗    ██╗██████╗ ██████╗  ██████╗ ████████╗
    ██╔════╝██║     ██╔══██╗██║    ██║██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝
    ██║     ██║     ███████║██║ █╗ ██║██║  ██║██████╔╝██║   ██║   ██║   
    ██║     ██║     ██╔══██║██║███╗██║██║  ██║██╔══██╗██║   ██║   ██║   
    ╚██████╗███████╗██║  ██║╚███╔███╔╝██████╔╝██████╔╝╚██████╔╝   ██║   
     ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═════╝ ╚═════╝  ╚═════╝    ╚═╝   
                                                                         
              🦞 智能 AI 助手一键部署工具 v1.0.0 🦞
    
EOF
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 从 TTY 读取用户输入（支持 curl | bash 模式）
read_input() {
    local prompt="$1"
    local var_name="$2"
    echo -en "$prompt"
    read $var_name < "$TTY_INPUT"
}

confirm() {
    local message="$1"
    local default="${2:-y}"
    
    if [ "$default" = "y" ]; then
        local prompt="[Y/n]"
    else
        local prompt="[y/N]"
    fi
    
    echo -en "${YELLOW}$message $prompt: ${NC}"
    read response < "$TTY_INPUT"
    response=${response:-$default}
    
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# ================================ 系统检测 ================================

detect_os() {
    log_step "检测操作系统..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            OS_VERSION=$VERSION_ID
        fi
        PACKAGE_MANAGER=""
        if command -v apt-get &> /dev/null; then
            PACKAGE_MANAGER="apt"
        elif command -v yum &> /dev/null; then
            PACKAGE_MANAGER="yum"
        elif command -v dnf &> /dev/null; then
            PACKAGE_MANAGER="dnf"
        elif command -v pacman &> /dev/null; then
            PACKAGE_MANAGER="pacman"
        fi
        log_info "检测到 Linux 系统: $OS $OS_VERSION (包管理器: $PACKAGE_MANAGER)"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        OS_VERSION=$(sw_vers -productVersion)
        PACKAGE_MANAGER="brew"
        log_info "检测到 macOS 系统: $OS_VERSION"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        OS="windows"
        log_info "检测到 Windows 系统 (Git Bash/Cygwin)"
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
}

check_root() {
    if [[ "$OS" != "macos" ]] && [[ $EUID -eq 0 ]]; then
        log_warn "检测到以 root 用户运行"
        if ! confirm "建议使用普通用户运行，是否继续？" "n"; then
            exit 1
        fi
    fi
}

# ================================ 依赖检查与安装 ================================

check_command() {
    command -v "$1" &> /dev/null
}

install_homebrew() {
    if ! check_command brew; then
        log_step "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # 添加到 PATH
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
}

install_nodejs() {
    log_step "检查 Node.js..."
    
    if check_command node; then
        local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$node_version" -ge "$MIN_NODE_VERSION" ]; then
            log_info "Node.js 版本满足要求: $(node -v)"
            return 0
        else
            log_warn "Node.js 版本过低: $(node -v)，需要 v$MIN_NODE_VERSION+"
        fi
    fi
    
    log_step "安装 Node.js $MIN_NODE_VERSION..."
    
    case "$OS" in
        macos)
            install_homebrew
            brew install node@22
            brew link --overwrite node@22
            ;;
        ubuntu|debian)
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
        centos|rhel|fedora)
            curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
            sudo yum install -y nodejs
            ;;
        arch|manjaro)
            sudo pacman -S nodejs npm --noconfirm
            ;;
        *)
            log_error "无法自动安装 Node.js，请手动安装 v$MIN_NODE_VERSION+"
            exit 1
            ;;
    esac
    
    log_info "Node.js 安装完成: $(node -v)"
}

install_git() {
    if ! check_command git; then
        log_step "安装 Git..."
        case "$OS" in
            macos)
                install_homebrew
                brew install git
                ;;
            ubuntu|debian)
                sudo apt-get update && sudo apt-get install -y git
                ;;
            centos|rhel|fedora)
                sudo yum install -y git
                ;;
            arch|manjaro)
                sudo pacman -S git --noconfirm
                ;;
        esac
    fi
    log_info "Git 版本: $(git --version)"
}

install_dependencies() {
    log_step "检查并安装依赖..."
    
    # 安装基础依赖
    case "$OS" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y curl wget jq
            ;;
        centos|rhel|fedora)
            sudo yum install -y curl wget jq
            ;;
        macos)
            install_homebrew
            brew install curl wget jq
            ;;
    esac
    
    install_git
    install_nodejs
}

# ================================ ClawdBot 安装 ================================

create_directories() {
    log_step "创建配置目录..."
    
    mkdir -p "$CONFIG_DIR"
    
    log_info "配置目录: $CONFIG_DIR"
}

install_clawdbot() {
    log_step "安装 ClawdBot..."
    
    # 检查是否已安装
    if check_command clawdbot; then
        local current_version=$(clawdbot --version 2>/dev/null || echo "unknown")
        log_warn "ClawdBot 已安装 (版本: $current_version)"
        if ! confirm "是否重新安装/更新？"; then
            init_clawdbot_config
            return 0
        fi
    fi
    
    # 使用 npm 全局安装
    log_info "正在从 npm 安装 ClawdBot..."
    npm install -g clawdbot@$CLAWDBOT_VERSION
    
    # 验证安装
    if check_command clawdbot; then
        log_info "ClawdBot 安装成功: $(clawdbot --version 2>/dev/null || echo 'installed')"
        init_clawdbot_config
    else
        log_error "ClawdBot 安装失败"
        exit 1
    fi
}

# 初始化 ClawdBot 配置
init_clawdbot_config() {
    log_step "初始化 ClawdBot 配置..."
    
    local CLAWDBOT_DIR="$HOME/.clawdbot"
    
    # 创建必要的目录
    mkdir -p "$CLAWDBOT_DIR/agents/main/sessions"
    mkdir -p "$CLAWDBOT_DIR/agents/main/agent"
    mkdir -p "$CLAWDBOT_DIR/credentials"
    
    # 修复权限
    chmod 700 "$CLAWDBOT_DIR" 2>/dev/null || true
    
    # 设置 gateway.mode 为 local
    if check_command clawdbot; then
        clawdbot config set gateway.mode local 2>/dev/null || true
        log_info "Gateway 模式已设置为 local"
    fi
}

# 配置 ClawdBot 使用的 AI 模型和 API Key
configure_clawdbot_model() {
    log_step "配置 ClawdBot AI 模型..."
    
    local env_file="$HOME/.clawdbot/env"
    local clawdbot_json="$HOME/.clawdbot/clawdbot.json"
    
    # 创建环境变量文件
    cat > "$env_file" << EOF
# ClawdBot 环境变量配置
# 由安装脚本自动生成: $(date '+%Y-%m-%d %H:%M:%S')
EOF

    # 根据 AI_PROVIDER 设置对应的环境变量
    case "$AI_PROVIDER" in
        anthropic)
            echo "export ANTHROPIC_API_KEY=$AI_KEY" >> "$env_file"
            [ -n "$BASE_URL" ] && echo "export ANTHROPIC_BASE_URL=$BASE_URL" >> "$env_file"
            ;;
        openai)
            echo "export OPENAI_API_KEY=$AI_KEY" >> "$env_file"
            [ -n "$BASE_URL" ] && echo "export OPENAI_BASE_URL=$BASE_URL" >> "$env_file"
            ;;
        google)
            echo "export GOOGLE_API_KEY=$AI_KEY" >> "$env_file"
            [ -n "$BASE_URL" ] && echo "export GOOGLE_BASE_URL=$BASE_URL" >> "$env_file"
            ;;
        groq)
            echo "export OPENAI_API_KEY=$AI_KEY" >> "$env_file"
            echo "export OPENAI_BASE_URL=${BASE_URL:-https://api.groq.com/openai/v1}" >> "$env_file"
            ;;
        mistral)
            echo "export OPENAI_API_KEY=$AI_KEY" >> "$env_file"
            echo "export OPENAI_BASE_URL=${BASE_URL:-https://api.mistral.ai/v1}" >> "$env_file"
            ;;
        openrouter)
            echo "export OPENAI_API_KEY=$AI_KEY" >> "$env_file"
            echo "export OPENAI_BASE_URL=${BASE_URL:-https://openrouter.ai/api/v1}" >> "$env_file"
            ;;
        ollama)
            echo "export OLLAMA_HOST=${BASE_URL:-http://localhost:11434}" >> "$env_file"
            ;;
    esac
    
    chmod 600 "$env_file"
    log_info "环境变量配置已保存到: $env_file"
    
    # 设置默认模型
    if check_command clawdbot; then
        local clawdbot_model=""
        local use_custom_provider=false
        
        # 如果使用自定义 BASE_URL，需要配置自定义 provider
        if [ -n "$BASE_URL" ] && [ "$AI_PROVIDER" = "anthropic" ]; then
            use_custom_provider=true
            configure_custom_provider "$AI_PROVIDER" "$AI_KEY" "$AI_MODEL" "$BASE_URL" "$clawdbot_json"
            clawdbot_model="anthropic-custom/$AI_MODEL"
        elif [ -n "$BASE_URL" ] && [ "$AI_PROVIDER" = "openai" ]; then
            use_custom_provider=true
            configure_custom_provider "$AI_PROVIDER" "$AI_KEY" "$AI_MODEL" "$BASE_URL" "$clawdbot_json"
            clawdbot_model="openai-custom/$AI_MODEL"
        else
            case "$AI_PROVIDER" in
                anthropic)
                    clawdbot_model="anthropic/$AI_MODEL"
                    ;;
                openai|groq|mistral)
                    clawdbot_model="openai/$AI_MODEL"
                    ;;
                openrouter)
                    clawdbot_model="openrouter/$AI_MODEL"
                    ;;
                google)
                    clawdbot_model="google/$AI_MODEL"
                    ;;
                ollama)
                    clawdbot_model="ollama/$AI_MODEL"
                    ;;
            esac
        fi
        
        if [ -n "$clawdbot_model" ]; then
            # 加载环境变量
            source "$env_file"
            
            # 设置默认模型（显示错误信息以便调试）
            # 添加 || true 防止 set -e 导致脚本退出
            local set_result
            set_result=$(clawdbot models set "$clawdbot_model" 2>&1) || true
            local set_exit=$?
            
            if [ $set_exit -eq 0 ]; then
                log_info "默认模型已设置为: $clawdbot_model"
            else
                log_warn "模型设置可能失败: $clawdbot_model"
                echo -e "  ${GRAY}$set_result${NC}" | head -3
                
                # 尝试直接使用 config set
                log_info "尝试使用 config set 设置模型..."
                clawdbot config set models.default "$clawdbot_model" 2>/dev/null || true
            fi
        fi
    fi
    
    # 添加到 shell 配置文件
    add_env_to_shell "$env_file"
}

# 配置自定义 provider（用于支持自定义 API 地址）
configure_custom_provider() {
    local provider="$1"
    local api_key="$2"
    local model="$3"
    local base_url="$4"
    local config_file="$5"
    
    # 参数校验
    if [ -z "$model" ]; then
        log_error "模型名称不能为空"
        return 0  # 返回 0 防止 set -e 退出
    fi
    
    if [ -z "$api_key" ]; then
        log_error "API Key 不能为空"
        return 0
    fi
    
    if [ -z "$base_url" ]; then
        log_error "API 地址不能为空"
        return 0
    fi
    
    log_step "配置自定义 Provider..."
    
    # 确保配置目录存在
    local config_dir=$(dirname "$config_file")
    mkdir -p "$config_dir" 2>/dev/null || true
    
    # 确定 API 类型
    local api_type="openai-chat"
    if [ "$provider" = "anthropic" ]; then
        api_type="anthropic-messages"
    fi
    local provider_id="${provider}-custom"
    
    # 先检查是否存在旧的自定义配置，并询问是否清理
    local do_cleanup="false"
    if [ -f "$config_file" ]; then
        # 检查是否有旧的自定义 provider 配置
        local has_old_config="false"
        if grep -q '"anthropic-custom"' "$config_file" 2>/dev/null || \
           grep -q '"openai-custom"' "$config_file" 2>/dev/null; then
            has_old_config="true"
        fi
        
        if [ "$has_old_config" = "true" ]; then
            echo ""
            echo -e "${CYAN}当前已有自定义 Provider 配置:${NC}"
            # 显示当前配置的 provider 和模型
            if command -v node &> /dev/null; then
                node -e "
const fs = require('fs');
try {
    const config = JSON.parse(fs.readFileSync('$config_file', 'utf8'));
    const providers = config.models?.providers || {};
    for (const [id, p] of Object.entries(providers)) {
        if (id.includes('-custom')) {
            console.log('  - Provider: ' + id);
            console.log('    API 地址: ' + p.baseUrl);
            if (p.models?.length) {
                console.log('    模型: ' + p.models.map(m => m.id).join(', '));
            }
        }
    }
} catch (e) {}
" 2>/dev/null
            fi
            echo ""
            echo -e "${YELLOW}是否清理旧的自定义配置？${NC}"
            echo -e "${GRAY}(清理可避免配置累积，推荐选择 Y)${NC}"
            if confirm "清理旧配置？" "y"; then
                do_cleanup="true"
            fi
        fi
    fi
    
    # 读取现有配置或创建新配置
    local config_json="{}"
    if [ -f "$config_file" ]; then
        config_json=$(cat "$config_file")
    fi
    
    # 使用 node 或 python 来处理 JSON
    if command -v node &> /dev/null; then
        node -e "
const fs = require('fs');
let config = {};
try {
    config = JSON.parse(fs.readFileSync('$config_file', 'utf8'));
} catch (e) {
    config = {};
}

// 确保 models.providers 结构存在
if (!config.models) config.models = {};
if (!config.models.providers) config.models.providers = {};

// 根据用户选择决定是否清理旧配置
if ('$do_cleanup' === 'true') {
    // 清理旧的自定义 provider（避免累积）
    delete config.models.providers['anthropic-custom'];
    delete config.models.providers['openai-custom'];

    // 清理旧的错误配置模型（如 openai/claude-* 等）
    if (config.models.configured) {
        config.models.configured = config.models.configured.filter(m => {
            if (m.startsWith('openai/claude')) return false;
            if (m.startsWith('openrouter/claude') && !m.includes('openrouter.ai')) return false;
            return true;
        });
    }

    // 清理旧的别名
    if (config.models.aliases) {
        delete config.models.aliases['claude-custom'];
    }
    console.log('Old configurations cleaned up');
}

// 添加自定义 provider
config.models.providers['$provider_id'] = {
    baseUrl: '$base_url',
    apiKey: '$api_key',
    models: [
        {
            id: '$model',
            name: '$model',
            api: '$api_type',
            input: ['text','image'],
            contextWindow: 200000,
            maxTokens: 8192
        }
    ]
};

fs.writeFileSync('$config_file', JSON.stringify(config, null, 2));
console.log('Custom provider configured: $provider_id');
"
        local node_exit=$?
        if [ $node_exit -eq 0 ]; then
            log_info "自定义 Provider 已配置: $provider_id"
        else
            log_warn "node 配置可能失败，尝试使用 python3..."
        fi
    elif command -v python3 &> /dev/null; then
        python3 -c "
import json
import os

config = {}
config_file = '$config_file'
if os.path.exists(config_file):
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
    except:
        config = {}

if 'models' not in config:
    config['models'] = {}
if 'providers' not in config['models']:
    config['models']['providers'] = {}

# 根据用户选择决定是否清理旧配置
if '$do_cleanup' == 'true':
    # 清理旧的自定义 provider（避免累积）
    config['models']['providers'].pop('anthropic-custom', None)
    config['models']['providers'].pop('openai-custom', None)

    # 清理旧的错误配置模型
    if 'configured' in config['models']:
        config['models']['configured'] = [
            m for m in config['models']['configured']
            if not (m.startswith('openai/claude') or 
                    (m.startswith('openrouter/claude') and 'openrouter.ai' not in m))
        ]

    # 清理旧的别名
    if 'aliases' in config['models']:
        config['models']['aliases'].pop('claude-custom', None)
    
    print('Old configurations cleaned up')

config['models']['providers']['$provider_id'] = {
    'baseUrl': '$base_url',
    'apiKey': '$api_key',
    'models': [
        {
            'id': '$model',
            'name': '$model',
            'api': '$api_type',
            'input': ['text','image'],
            'contextWindow': 200000,
            'maxTokens': 8192
        }
    ]
}

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print('Custom provider configured: $provider_id')
"
        local py_exit=$?
        if [ $py_exit -eq 0 ]; then
            log_info "自定义 Provider 已配置: $provider_id"
        else
            log_warn "python3 配置失败"
        fi
    else
        log_warn "无法配置自定义 Provider（需要 node 或 python3）"
    fi
    
    # 验证配置文件是否正确写入
    if [ -f "$config_file" ]; then
        if grep -q "$provider_id" "$config_file" 2>/dev/null; then
            log_info "配置文件验证通过: $config_file"
        else
            log_warn "配置文件可能未正确写入，请检查: $config_file"
        fi
    fi
}

# 添加环境变量到 shell 配置
add_env_to_shell() {
    local env_file="$1"
    local shell_rc=""
    
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        shell_rc="$HOME/.bash_profile"
    fi
    
    if [ -n "$shell_rc" ]; then
        # 检查是否已添加
        if ! grep -q "source.*clawdbot/env" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# ClawdBot 环境变量" >> "$shell_rc"
            echo "[ -f \"$env_file\" ] && source \"$env_file\"" >> "$shell_rc"
            log_info "环境变量已添加到: $shell_rc"
        fi
    fi
}

# ================================ 配置向导 ================================

# create_default_config 已移除 - ClawdBot 使用 clawdbot.json 和环境变量

run_onboard_wizard() {
    log_step "运行配置向导..."
    
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}           🧙 ClawdBot 核心配置向导${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 检查是否已有配置
    local skip_ai_config=false
    local skip_identity_config=false
    local env_file="$HOME/.clawdbot/env"
    
    if [ -f "$env_file" ]; then
        echo -e "${YELLOW}检测到已有配置！${NC}"
        echo ""
        
        # 显示当前模型配置
        if check_command clawdbot; then
            echo -e "${CYAN}当前 ClawdBot 配置:${NC}"
            clawdbot models status 2>/dev/null | head -10 || true
            echo ""
        fi
        
        # 询问是否重新配置 AI
        if ! confirm "是否重新配置 AI 模型提供商？" "n"; then
            skip_ai_config=true
            log_info "使用现有 AI 配置"
            
            if confirm "是否测试现有 API 连接？" "y"; then
                # 从 env 文件读取配置进行测试
                source "$env_file"
                # 获取当前模型
                AI_MODEL=$(clawdbot config get models.default 2>/dev/null | sed 's|.*/||')
                if [ -n "$ANTHROPIC_API_KEY" ]; then
                    AI_PROVIDER="anthropic"
                    AI_KEY="$ANTHROPIC_API_KEY"
                    BASE_URL="$ANTHROPIC_BASE_URL"
                elif [ -n "$OPENAI_API_KEY" ]; then
                    AI_PROVIDER="openai"
                    AI_KEY="$OPENAI_API_KEY"
                    BASE_URL="$OPENAI_BASE_URL"
                elif [ -n "$GOOGLE_API_KEY" ]; then
                    AI_PROVIDER="google"
                    AI_KEY="$GOOGLE_API_KEY"
                fi
                test_api_connection
            fi
        fi
        
        echo ""
    else
        echo -e "${CYAN}接下来将引导你完成核心配置，包括:${NC}"
        echo "  1. 选择 AI 模型提供商"
        echo "  2. 配置 API 连接"
        echo "  3. 测试 API 连接"
        echo "  4. 设置基本身份信息"
        echo ""
    fi
    
    # AI 配置
    if [ "$skip_ai_config" = false ]; then
        setup_ai_provider
        test_api_connection
    else
        # 即使跳过配置，也可选择测试连接
        if confirm "是否测试现有 API 连接？" "y"; then
            test_api_connection
        fi
    fi
    
    # 身份配置
    if [ "$skip_identity_config" = false ]; then
        setup_identity
    else
        # 初始化渠道配置变量
        TELEGRAM_ENABLED="false"
        DISCORD_ENABLED="false"
        SHELL_ENABLED="false"
        FILE_ACCESS="false"
    fi
    # 配置 ClawdBot（使用 clawdbot 命令和环境变量）
    configure_clawdbot_model
    
    log_info "核心配置完成！"
}

# ================================ AI Provider 配置 ================================

setup_ai_provider() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  第 1 步: 选择 AI 模型提供商${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  1) 🟣 Anthropic Claude"
    echo "  2) 🟢 OpenAI GPT"
    echo "  3) 🟠 Ollama (本地模型)"
    echo "  4) 🔵 OpenRouter (多模型网关)"
    echo "  5) 🔴 Google Gemini"
    echo "  6) ⚡ Groq (超快推理)"
    echo "  7) 🌬️ Mistral AI"
    echo ""
    echo -e "${GRAY}提示: Anthropic 支持自定义 API 地址（通过 clawdbot.json 配置自定义 Provider）${NC}"
    echo ""
    echo -en "${YELLOW}请选择 AI 提供商 [1-7] (默认: 1): ${NC}"; read ai_choice < "$TTY_INPUT"
    ai_choice=${ai_choice:-1}
    
    case $ai_choice in
        1)
            AI_PROVIDER="anthropic"
            echo ""
            echo -e "${CYAN}配置 Anthropic Claude${NC}"
            echo -e "${GRAY}官方 API: https://console.anthropic.com/${NC}"
            echo ""
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方 API): ${NC}"; read BASE_URL < "$TTY_INPUT"
            echo ""
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            echo ""
            echo "选择模型:"
            echo "  1) claude-sonnet-4-5-20250929 (推荐)"
            echo "  2) claude-opus-4-5-20251101 (最强)"
            echo "  3) claude-haiku-4-5-20251001 (快速)"
            echo "  4) claude-sonnet-4-20250514 (上一代)"
            echo "  5) 自定义模型名称"
            echo -en "${YELLOW}选择模型 [1-5] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="claude-opus-4-5-20251101" ;;
                3) AI_MODEL="claude-haiku-4-5-20251001" ;;
                4) AI_MODEL="claude-sonnet-4-20250514" ;;
                5) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="claude-sonnet-4-5-20250929" ;;
            esac
            ;;
        2)
            AI_PROVIDER="openai"
            echo ""
            echo -e "${CYAN}配置 OpenAI GPT${NC}"
            echo -e "${GRAY}官方 API: https://platform.openai.com/${NC}"
            echo ""
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方 API): ${NC}"; read BASE_URL < "$TTY_INPUT"
            echo ""
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            echo ""
            echo "选择模型:"
            echo "  1) gpt-4o (推荐)"
            echo "  2) gpt-4o-mini (经济)"
            echo "  3) gpt-4-turbo"
            echo "  4) 自定义模型名称"
            echo -en "${YELLOW}选择模型 [1-4] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="gpt-4o-mini" ;;
                3) AI_MODEL="gpt-4-turbo" ;;
                4) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="gpt-4o" ;;
            esac
            ;;
        3)
            AI_PROVIDER="ollama"
            AI_KEY=""
            echo ""
            echo -e "${CYAN}配置 Ollama 本地模型${NC}"
            echo ""
            echo -en "${YELLOW}Ollama 地址 (默认: http://localhost:11434): ${NC}"; read BASE_URL < "$TTY_INPUT"
            BASE_URL=${BASE_URL:-"http://localhost:11434"}
            echo ""
            echo "选择模型:"
            echo "  1) llama3"
            echo "  2) llama3:70b"
            echo "  3) mistral"
            echo "  4) 自定义"
            echo -en "${YELLOW}选择模型 [1-4] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="llama3:70b" ;;
                3) AI_MODEL="mistral" ;;
                4) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="llama3" ;;
            esac
            ;;
        4)
            AI_PROVIDER="openrouter"
            echo ""
            echo -e "${CYAN}配置 OpenRouter${NC}"
            echo -e "${GRAY}获取 API Key: https://openrouter.ai/${NC}"
            echo ""
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            echo ""
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方): ${NC}"; read BASE_URL < "$TTY_INPUT"
            BASE_URL=${BASE_URL:-"https://openrouter.ai/api/v1"}
            echo ""
            echo "选择模型:"
            echo "  1) anthropic/claude-sonnet-4 (推荐)"
            echo "  2) openai/gpt-4o"
            echo "  3) google/gemini-pro-1.5"
            echo "  4) 自定义"
            echo -en "${YELLOW}选择模型 [1-4] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="openai/gpt-4o" ;;
                3) AI_MODEL="google/gemini-pro-1.5" ;;
                4) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="anthropic/claude-sonnet-4" ;;
            esac
            ;;
        5)
            AI_PROVIDER="google"
            echo ""
            echo -e "${CYAN}配置 Google Gemini${NC}"
            echo -e "${GRAY}获取 API Key: https://makersuite.google.com/app/apikey${NC}"
            echo ""
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            echo ""
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方): ${NC}"; read BASE_URL < "$TTY_INPUT"
            echo ""
            echo "选择模型:"
            echo "  1) gemini-2.0-flash (推荐)"
            echo "  2) gemini-1.5-pro"
            echo "  3) gemini-1.5-flash"
            echo "  4) 自定义"
            echo -en "${YELLOW}选择模型 [1-4] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="gemini-1.5-pro" ;;
                3) AI_MODEL="gemini-1.5-flash" ;;
                4) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="gemini-2.0-flash" ;;
            esac
            ;;
        6)
            AI_PROVIDER="groq"
            echo ""
            echo -e "${CYAN}配置 Groq${NC}"
            echo -e "${GRAY}获取 API Key: https://console.groq.com/${NC}"
            echo ""
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            echo ""
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方): ${NC}"; read BASE_URL < "$TTY_INPUT"
            BASE_URL=${BASE_URL:-"https://api.groq.com/openai/v1"}
            echo ""
            echo "选择模型:"
            echo "  1) llama-3.3-70b-versatile (推荐)"
            echo "  2) llama-3.1-8b-instant"
            echo "  3) mixtral-8x7b-32768"
            echo "  4) 自定义"
            echo -en "${YELLOW}选择模型 [1-4] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="llama-3.1-8b-instant" ;;
                3) AI_MODEL="mixtral-8x7b-32768" ;;
                4) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="llama-3.3-70b-versatile" ;;
            esac
            ;;
        7)
            AI_PROVIDER="mistral"
            echo ""
            echo -e "${CYAN}配置 Mistral AI${NC}"
            echo -e "${GRAY}获取 API Key: https://console.mistral.ai/${NC}"
            echo ""
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            echo ""
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方): ${NC}"; read BASE_URL < "$TTY_INPUT"
            BASE_URL=${BASE_URL:-"https://api.mistral.ai/v1"}
            echo ""
            echo "选择模型:"
            echo "  1) mistral-large-latest (推荐)"
            echo "  2) mistral-small-latest"
            echo "  3) codestral-latest"
            echo "  4) 自定义"
            echo -en "${YELLOW}选择模型 [1-4] (默认: 1): ${NC}"; read model_choice < "$TTY_INPUT"
            case $model_choice in
                2) AI_MODEL="mistral-small-latest" ;;
                3) AI_MODEL="codestral-latest" ;;
                4) echo -en "${YELLOW}输入模型名称: ${NC}"; read AI_MODEL < "$TTY_INPUT" ;;
                *) AI_MODEL="mistral-large-latest" ;;
            esac
            ;;
        *)
            # 默认使用 Anthropic
            AI_PROVIDER="anthropic"
            echo ""
            echo -e "${CYAN}配置 Anthropic Claude${NC}"
            echo -en "${YELLOW}自定义 API 地址 (留空使用官方): ${NC}"; read BASE_URL < "$TTY_INPUT"
            echo -en "${YELLOW}输入 API Key: ${NC}"; read AI_KEY < "$TTY_INPUT"
            AI_MODEL="claude-sonnet-4-20250514"
            ;;
    esac
    
    echo ""
    log_info "AI Provider 配置完成"
    echo -e "  提供商: ${WHITE}$AI_PROVIDER${NC}"
    echo -e "  模型: ${WHITE}$AI_MODEL${NC}"
    [ -n "$BASE_URL" ] && echo -e "  API 地址: ${WHITE}$BASE_URL${NC}"
}

# ================================ API 连接测试 ================================

test_api_connection() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  第 2 步: 测试 API 连接${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local test_passed=false
    local max_retries=3
    local retry_count=0
    
    # 确保环境变量已加载
    local env_file="$HOME/.clawdbot/env"
    [ -f "$env_file" ] && source "$env_file"
    
    if ! check_command clawdbot; then
        echo -e "${YELLOW}ClawdBot 未安装，跳过测试${NC}"
        return 0
    fi
    
    # 显示当前模型配置
    echo -e "${CYAN}当前模型配置:${NC}"
    clawdbot models status 2>&1 | grep -E "Default|Auth|effective" | head -5
    echo ""
    
    while [ "$test_passed" = false ] && [ $retry_count -lt $max_retries ]; do
        echo -e "${YELLOW}运行 clawdbot agent --local 测试...${NC}"
        echo ""
        
        # 使用 clawdbot agent --local 测试（添加超时）
        local result
        local exit_code
        
        # 使用 timeout 命令（如果可用），否则直接运行
        # 注意：添加 || true 防止 set -e 导致脚本退出
        if command -v timeout &> /dev/null; then
            result=$(timeout 30 clawdbot agent --local --to "+1234567890" --message "回复 OK" 2>&1) || true
            exit_code=${PIPESTATUS[0]}
            # 如果 exit_code 为空，从 $? 获取（兼容不同 shell）
            [ -z "$exit_code" ] && exit_code=$?
            if [ "$exit_code" = "124" ]; then
                result="测试超时（30秒）"
            fi
        else
            result=$(clawdbot agent --local --to "+1234567890" --message "回复 OK" 2>&1) || true
            exit_code=$?
        fi
        
        # 检查结果是否为空
        if [ -z "$result" ]; then
            result="(无输出 - 命令可能立即退出)"
            exit_code=1
        fi
        
        if [ $exit_code -eq 0 ] && ! echo "$result" | grep -qiE "error|failed|401|403|Unknown model|超时"; then
            test_passed=true
            echo -e "${GREEN}✓ ClawdBot AI 测试成功！${NC}"
            echo ""
            echo -e "  ${CYAN}AI 响应:${NC}"
            echo "$result" | head -3 | sed 's/^/    /'
        else
            retry_count=$((retry_count + 1))
            echo -e "${RED}✗ ClawdBot AI 测试失败 (退出码: $exit_code)${NC}"
            echo ""
            echo -e "  ${RED}错误:${NC}"
            echo "$result" | head -5 | sed 's/^/    /'
            echo ""
            
            if [ $retry_count -lt $max_retries ]; then
                echo -e "${YELLOW}剩余 $((max_retries - retry_count)) 次机会${NC}"
                echo ""
                
                # 提供修复建议
                if echo "$result" | grep -q "Unknown model"; then
                    echo -e "${YELLOW}提示: 模型不被识别，建议运行: clawdbot configure --section model${NC}"
                elif echo "$result" | grep -q "401\|Incorrect API key"; then
                    echo -e "${YELLOW}提示: API 配置可能不正确${NC}"
                fi
                echo ""
                
                if confirm "是否重新配置 AI Provider？" "y"; then
                    setup_ai_provider
                    configure_clawdbot_model
                else
                    echo -e "${YELLOW}继续使用当前配置...${NC}"
                    test_passed=true  # 允许跳过
                fi
            fi
        fi
    done
    
    if [ "$test_passed" = false ]; then
        echo -e "${RED}API 连接测试失败${NC}"
        echo ""
        echo "建议运行以下命令手动配置:"
        echo "  clawdbot configure --section model"
        echo "  clawdbot doctor"
        echo ""
        if confirm "是否仍然继续安装？" "y"; then
            log_warn "跳过连接测试，继续安装..."
            return 0
        else
            echo "安装已取消"
            exit 1
        fi
    fi
    
    return 0
}

# HTTP 直接测试 (备用，用于安装前验证 API Key)
test_api_connection_http() {
    echo ""
    echo -e "${YELLOW}正在验证 API Key...${NC}"
    echo ""
    
    local test_url=""
    local RESPONSE=""
    
    case "$AI_PROVIDER" in
        anthropic)
            if [ -n "$BASE_URL" ]; then
                test_url="${BASE_URL}/v1/chat/completions"
                [[ "$BASE_URL" == */v1 ]] && test_url="${BASE_URL}/chat/completions"
                RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$test_url" \
                    -H "Content-Type: application/json" -H "Authorization: Bearer $AI_KEY" \
                    -d "{\"model\": \"$AI_MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"OK\"}], \"max_tokens\": 10}" 2>/dev/null)
            else
                test_url="https://api.anthropic.com/v1/messages"
                RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$test_url" \
                    -H "Content-Type: application/json" -H "x-api-key: $AI_KEY" -H "anthropic-version: 2023-06-01" \
                    -d "{\"model\": \"$AI_MODEL\", \"max_tokens\": 10, \"messages\": [{\"role\": \"user\", \"content\": \"OK\"}]}" 2>/dev/null)
            fi
            ;;
        google)
            test_url="https://generativelanguage.googleapis.com/v1beta/models/$AI_MODEL:generateContent?key=$AI_KEY"
            RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$test_url" \
                -H "Content-Type: application/json" -d "{\"contents\": [{\"parts\":[{\"text\": \"OK\"}]}]}" 2>/dev/null)
            ;;
        *)
            test_url="${BASE_URL:-https://api.openai.com/v1}/chat/completions"
            RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$test_url" \
                -H "Content-Type: application/json" -H "Authorization: Bearer $AI_KEY" \
                -d "{\"model\": \"$AI_MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"OK\"}], \"max_tokens\": 10}" 2>/dev/null)
            ;;
    esac
    
    local HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    local RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ API Key 验证成功！${NC}"
        return 0
    else
        echo -e "${RED}✗ API Key 验证失败 (HTTP $HTTP_CODE)${NC}"
        if command -v python3 &> /dev/null; then
            local error_msg=$(echo "$RESPONSE_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'error' in d:
        err = d['error']
        if isinstance(err, dict): print(err.get('message', str(err))[:200])
        else: print(str(err)[:200])
except: print('')
" 2>/dev/null)
            [ -n "$error_msg" ] && echo -e "  错误: $error_msg"
        fi
        return 1
    fi
}


# ================================ 身份配置 ================================

setup_identity() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  第 3 步: 设置身份信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -en "${YELLOW}给你的 AI 助手起个名字 (默认: Clawd): ${NC}"; read BOT_NAME < "$TTY_INPUT"
    BOT_NAME=${BOT_NAME:-"Clawd"}
    
    echo -en "${YELLOW}AI 如何称呼你 (默认: 主人): ${NC}"; read USER_NAME < "$TTY_INPUT"
    USER_NAME=${USER_NAME:-"主人"}
    
    echo -en "${YELLOW}你的时区 (默认: Asia/Shanghai): ${NC}"; read TIMEZONE < "$TTY_INPUT"
    TIMEZONE=${TIMEZONE:-"Asia/Shanghai"}
    
    echo ""
    log_info "身份配置完成"
    echo -e "  助手名称: ${WHITE}$BOT_NAME${NC}"
    echo -e "  你的称呼: ${WHITE}$USER_NAME${NC}"
    echo -e "  时区: ${WHITE}$TIMEZONE${NC}"
    
    # 初始化渠道配置变量
    TELEGRAM_ENABLED="false"
    DISCORD_ENABLED="false"
    SHELL_ENABLED="false"
    FILE_ACCESS="false"
}


# ================================ 服务管理 ================================

setup_daemon() {
    if confirm "是否设置开机自启动？" "y"; then
        log_step "配置系统服务..."
        
        case "$OS" in
            macos)
                setup_launchd
                ;;
            *)
                setup_systemd
                ;;
        esac
    fi
}

setup_systemd() {
    cat > /tmp/clawdbot.service << EOF
[Unit]
Description=ClawdBot AI Assistant
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$(which clawdbot) start --daemon
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/clawdbot.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable clawdbot
    
    log_info "Systemd 服务已配置"
}

setup_launchd() {
    mkdir -p "$HOME/Library/LaunchAgents"
    
    cat > "$HOME/Library/LaunchAgents/com.clawdbot.agent.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clawdbot.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which clawdbot)</string>
        <string>start</string>
        <string>--daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/stderr.log</string>
</dict>
</plist>
EOF

    launchctl load "$HOME/Library/LaunchAgents/com.clawdbot.agent.plist" 2>/dev/null || true
    
    log_info "LaunchAgent 已配置"
}

# ================================ 完成安装 ================================

print_success() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    🎉 安装完成！🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}配置目录:${NC}"
    echo "  ClawdBot 配置: ~/.clawdbot/"
    echo "  环境变量配置: ~/.clawdbot/env"
    echo ""
    echo -e "${CYAN}常用命令:${NC}"
    echo "  clawdbot gateway start   # 后台启动服务"
    echo "  clawdbot gateway stop    # 停止服务"
    echo "  clawdbot gateway status  # 查看状态"
    echo "  clawdbot models status   # 查看模型配置"
    echo "  clawdbot channels list   # 查看渠道列表"
    echo "  clawdbot doctor          # 诊断问题"
    echo ""
    echo -e "${PURPLE}📚 官方文档: https://clawd.bot/docs${NC}"
    echo -e "${PURPLE}💬 社区支持: https://github.com/$GITHUB_REPO/discussions${NC}"
    echo ""
}

# 启动 ClawdBot Gateway 服务
start_clawdbot_service() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}           🚀 启动 ClawdBot 服务${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 加载环境变量
    local env_file="$HOME/.clawdbot/env"
    if [ -f "$env_file" ]; then
        source "$env_file"
        log_info "已加载环境变量"
    fi
    
    # 检查是否已有服务在运行
    if pgrep -f "clawdbot.*gateway" > /dev/null 2>&1; then
        log_warn "ClawdBot Gateway 已在运行"
        echo ""
        if confirm "是否重启服务？" "y"; then
            clawdbot gateway stop 2>/dev/null || true
            pkill -f "clawdbot.*gateway" 2>/dev/null || true
            sleep 2
        else
            return 0
        fi
    fi
    
    # 后台启动 Gateway
    log_step "正在后台启动 Gateway..."
    
    if [ -f "$env_file" ]; then
        nohup bash -c "source $env_file && clawdbot gateway --port 18789" > /tmp/clawdbot-gateway.log 2>&1 &
    else
        nohup clawdbot gateway --port 18789 > /tmp/clawdbot-gateway.log 2>&1 &
    fi
    
    sleep 3
    
    # 检查启动状态
    if pgrep -f "clawdbot.*gateway" > /dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}           ✓ ClawdBot Gateway 已启动！${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${CYAN}日志文件:${NC} /tmp/clawdbot-gateway.log"
        echo -e "  ${CYAN}查看日志:${NC} tail -f /tmp/clawdbot-gateway.log"
        echo -e "  ${CYAN}停止服务:${NC} clawdbot gateway stop"
        echo ""
        log_info "ClawdBot 现在可以接收消息了！"
    else
        log_error "Gateway 启动失败"
        echo ""
        echo -e "${YELLOW}请查看日志: tail -f /tmp/clawdbot-gateway.log${NC}"
        echo -e "${YELLOW}或手动启动: source ~/.clawdbot/env && clawdbot gateway${NC}"
    fi
}

# 下载并运行配置菜单
run_config_menu() {
    local config_menu_path="$CONFIG_DIR/config-menu.sh"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_config_menu="$script_dir/config-menu.sh"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}           🔧 启动配置菜单${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 优先使用本地的 config-menu.sh
    if [ -f "$local_config_menu" ]; then
        log_info "使用本地配置菜单: $local_config_menu"
        chmod +x "$local_config_menu"
        bash "$local_config_menu"
        return $?
    fi
    
    # 检查配置目录中是否已有
    if [ -f "$config_menu_path" ]; then
        log_info "使用已下载的配置菜单"
        chmod +x "$config_menu_path"
        bash "$config_menu_path"
        return $?
    fi
    
    # 从 GitHub 下载
    log_step "从 GitHub 下载配置菜单..."
    if curl -fsSL "$GITHUB_RAW_URL/config-menu.sh" -o "$config_menu_path"; then
        chmod +x "$config_menu_path"
        log_info "配置菜单下载成功"
        bash "$config_menu_path"
        return $?
    else
        log_error "配置菜单下载失败"
        echo -e "${YELLOW}你可以稍后手动下载运行:${NC}"
        echo "  curl -fsSL $GITHUB_RAW_URL/config-menu.sh | bash"
        return 1
    fi
}

# ================================ 主函数 ================================

main() {
    print_banner
    
    echo -e "${YELLOW}⚠️  警告: ClawdBot 需要完全的计算机权限${NC}"
    echo -e "${YELLOW}    不建议在主要工作电脑上安装，建议使用专用服务器或虚拟机${NC}"
    echo ""
    
    if ! confirm "是否继续安装？"; then
        echo "安装已取消"
        exit 0
    fi
    
    echo ""
    detect_os
    check_root
    install_dependencies
    create_directories
    install_clawdbot
    run_onboard_wizard
    setup_daemon
    print_success
    
    # 询问是否启动服务
    if confirm "是否现在启动 ClawdBot 服务？" "y"; then
        start_clawdbot_service
    else
        echo ""
        echo -e "${CYAN}稍后可以通过以下命令启动服务:${NC}"
        echo "  source ~/.clawdbot/env && clawdbot gateway"
        echo ""
    fi
    
    # 询问是否打开配置菜单进行详细配置
    echo ""
    if confirm "是否打开配置菜单进行详细配置（渠道配置等）？" "n"; then
        run_config_menu
    else
        echo ""
        echo -e "${CYAN}稍后可以通过以下命令打开配置菜单:${NC}"
        echo "  bash $CONFIG_DIR/config-menu.sh"
        echo "  # 或从 GitHub 下载运行:"
        echo "  curl -fsSL $GITHUB_RAW_URL/config-menu.sh | bash"
        echo ""
    fi
    
    echo ""
    echo -e "${GREEN}🦞 ClawdBot 安装完成！祝你使用愉快！${NC}"
    echo ""
}

# 执行主函数
main "$@"
