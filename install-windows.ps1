param(
    [switch]$SkipOfficialInstall,
    [switch]$NoOnboard,
    [switch]$SkipTuziConfig
)

$ErrorActionPreference = 'Stop'

# Keep Chinese and interactive prompts readable in Windows PowerShell 5.1.
try { chcp 65001 | Out-Null } catch {}
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
} catch {}

function Fail([string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Fail "Required command not found: $Name"
    }
}

function Confirm-Choice([string]$Prompt, [bool]$DefaultYes = $true) {
    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = (Read-Host "$Prompt $suffix").Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return $answer -match '^(y|yes)$'
}

function Read-ApiKey([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Get-TuziModels([string]$ApiKey) {
    try {
        $response = Invoke-RestMethod -Uri 'https://api.tu-zi.com/v1/models' `
            -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec 30
        $items = if ($null -ne $response.data) { $response.data } else { $response }
        $models = @(
            $items |
                ForEach-Object { $_.id } |
                Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim() } |
                Select-Object -Unique
        )
        if ($models.Count -gt 0) {
            Write-Host "已从 Tuzi 接口获取 $($models.Count) 个模型。" -ForegroundColor Green
            return $models
        }
        Write-Host '[WARN] 当前 Key 没有返回可见模型，将改为手动输入。' -ForegroundColor Yellow
    } catch {
        $status = $null
        if ($null -ne $_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        }
        $detail = if ($null -ne $status) { "HTTP $status" } else { $_.Exception.Message }
        Write-Host "[WARN] Tuzi 模型列表获取失败 ($detail)，将改为手动输入。" -ForegroundColor Yellow
    }
    return @()
}

function Select-TuziModels([string[]]$Models, [string]$Group) {
    if ($Models.Count -gt 0) {
        Write-Host '可用模型（显示前 40 个）：' -ForegroundColor Cyan
        $limit = [Math]::Min(40, $Models.Count)
        for ($i = 0; $i -lt $limit; $i++) {
            Write-Host "  [$($i + 1)] $($Models[$i])"
        }
        Write-Host '第一个选择将作为主模型，其余模型作为 fallback。' -ForegroundColor DarkGray
        $raw = (Read-Host '输入编号或模型名，多个值用英文逗号分隔（默认 1）').Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return @($Models[0]) }

        $selected = @()
        foreach ($token in $raw.Split(',')) {
            $value = $token.Trim()
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $number = 0
            if ([int]::TryParse($value, [ref]$number) -and $number -ge 1 -and $number -le $limit) {
                $selected += $Models[$number - 1]
            } else {
                $selected += $value
            }
        }
        $selected = @($selected | Select-Object -Unique)
        if ($selected.Count -gt 0) { return $selected }
    }

    do {
        $raw = (Read-Host "手动输入 $Group 模型名称，多个值用英文逗号分隔").Trim()
        $selected = @(
            $raw.Split(',') |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
    } while ($selected.Count -eq 0)
    return $selected
}

function Write-TuziConfig(
    [string]$Group,
    [string]$ApiKey,
    [string]$PrimaryModel,
    [string[]]$Models,
    [bool]$UpdateDefault
) {
    $configDir = Join-Path $HOME '.openclaw'
    $configPath = Join-Path $configDir 'openclaw.json'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    $backupPath = $null
    if (Test-Path -LiteralPath $configPath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $backupPath = "$configPath.bak-$stamp"
        Copy-Item -LiteralPath $configPath -Destination $backupPath
    }

    $modelCsv = ($Models |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Select-Object -Unique) -join ','
    $envNames = @(
        'OPENCLAW_PS_CONFIG',
        'OPENCLAW_PS_GROUP',
        'OPENCLAW_PS_PRIMARY',
        'OPENCLAW_PS_MODELS',
        'OPENCLAW_PS_UPDATE',
        'OPENCLAW_PS_API_KEY'
    )
    $envBackup = @{}
    foreach ($name in $envNames) {
        $envBackup[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    try {
        $env:OPENCLAW_PS_CONFIG = $configPath
        $env:OPENCLAW_PS_GROUP = $Group
        $env:OPENCLAW_PS_PRIMARY = $PrimaryModel
        $env:OPENCLAW_PS_MODELS = $modelCsv
        $env:OPENCLAW_PS_UPDATE = if ($UpdateDefault) { '1' } else { '0' }
        $env:OPENCLAW_PS_API_KEY = $ApiKey
        $nodeScript = @'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const configPath = process.env.OPENCLAW_PS_CONFIG;
const group = process.env.OPENCLAW_PS_GROUP;
const apiKey = process.env.OPENCLAW_PS_API_KEY;
const updateDefault = process.env.OPENCLAW_PS_UPDATE === '1';
let config = {};

if (fs.existsSync(configPath)) {
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    console.error('现有 openclaw.json 不是严格 JSON，已停止写入；原文件和备份均已保留。');
    process.exit(2);
  }
}

const normalizeModelIds = (items) => Array.from(new Set(items
  .map((item) => typeof item === 'string' ? item.trim().replace(/[\\/]+$/g, '') : '')
  .filter(Boolean)));
const buildModels = (items, maxTokens) => normalizeModelIds(items).map((id) => ({
  id,
  name: id,
  reasoning: false,
  input: ['text'],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 200000,
  maxTokens
}));
const addProvider = (id, baseUrl, api, modelIds, maxTokens) => {
  config.auth.profiles[id + ':default'] = { provider: id, mode: 'api_key' };
  config.models.providers[id] = {
    baseUrl,
    apiKey,
    api,
    models: buildModels(modelIds, maxTokens)
  };
  for (const modelId of normalizeModelIds(modelIds)) {
    config.agents.defaults.models[id + '/' + modelId] = {};
  }
};

config.auth = config.auth || {};
config.auth.profiles = config.auth.profiles || {};
config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.models = config.agents.defaults.models || {};
config.gateway = config.gateway || {};
config.gateway.mode = 'local';
config.gateway.auth = config.gateway.auth || {};
if (!config.gateway.auth.mode) config.gateway.auth.mode = 'token';
if (config.gateway.auth.mode === 'token' && !config.gateway.auth.token) {
  config.gateway.auth.token = crypto.randomBytes(32).toString('hex');
}

let defaultPrimary;
let defaultFallbacks;
if (group === 'gaccode') {
  const claudeModels = ['claude-opus-4-6', 'claude-sonnet-4-6', 'claude-haiku-4-5-20251001'];
  const codexModels = ['gpt-5.4'];
  addProvider('gac-claude', 'https://gaccode.com/claudecode', 'anthropic-messages', claudeModels, 8192);
  addProvider('gac-codex', 'https://gaccode.com/codex/v1', 'openai-completions', codexModels, 8192);
  defaultPrimary = 'gac-claude/claude-opus-4-6';
  defaultFallbacks = [
    'gac-claude/claude-sonnet-4-6',
    'gac-claude/claude-haiku-4-5-20251001',
    'gac-codex/gpt-5.4'
  ];
} else {
  const provider = group === 'codex' ? 'tuzi-codex' : 'tuzi-claude-code';
  const baseUrl = group === 'codex' ? 'https://api.tu-zi.com/v1' : 'https://api.tu-zi.com';
  const api = group === 'codex' ? 'openai-completions' : 'anthropic-messages';
  const modelIds = normalizeModelIds((process.env.OPENCLAW_PS_MODELS || '').split(','));
  const primary = (process.env.OPENCLAW_PS_PRIMARY || '').trim();
  if (!modelIds.includes(primary)) modelIds.unshift(primary);
  addProvider(provider, baseUrl, api, modelIds, group === 'codex' ? 100000 : 8192);
  defaultPrimary = provider + '/' + primary;
  defaultFallbacks = modelIds.slice(1).map((modelId) => provider + '/' + modelId);
}

const currentPrimary = config.agents.defaults.model && config.agents.defaults.model.primary;
if (updateDefault || !currentPrimary) {
  config.agents.defaults.model = { primary: defaultPrimary, fallbacks: defaultFallbacks };
}

const tempPath = configPath + '.tmp-' + process.pid;
try {
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(tempPath, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
  try {
    fs.renameSync(tempPath, configPath);
  } catch (error) {
    // Windows may reject rename over an existing file (EPERM/EEXIST).
    // The verified temp file is still copied only after the backup exists.
    if (error.code !== 'EPERM' && error.code !== 'EEXIST') throw error;
    fs.copyFileSync(tempPath, configPath);
    fs.unlinkSync(tempPath);
  }
} catch (error) {
  try { fs.unlinkSync(tempPath); } catch (_) {}
  console.error('写入 OpenClaw 配置失败: ' + error.message);
  process.exit(3);
}
'@
        $nodeOutput = @(& node -e $nodeScript 2>&1)
        $nodeExit = $LASTEXITCODE
        if ($nodeExit -ne 0) {
            foreach ($line in $nodeOutput) { Write-Host $line -ForegroundColor Red }
            Fail 'Tuzi 配置写入失败，原配置未被覆盖。'
        }
    } finally {
        foreach ($name in $envNames) {
            if ($null -eq $envBackup[$name]) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "Env:$name" $envBackup[$name]
            }
        }
    }

    return [PSCustomObject]@{ ConfigPath = $configPath; BackupPath = $backupPath }
}

function Configure-Tuzi {
    Write-Host ''
    Write-Host '第 1 步: 配置 Tuzi API' -ForegroundColor Cyan
    Write-Host '  [1] Claude-Code'
    Write-Host '  [2] Codex'
    Write-Host '  [3] GACCode'
    $choice = (Read-Host '选择 Tuzi 分组 [1-3]（默认 1）').Trim()
    $group = if ($choice -eq '2') { 'codex' } elseif ($choice -eq '3') { 'gaccode' } else { 'claude-code' }
    Write-Host '获取 Key: https://api.tu-zi.com/token' -ForegroundColor DarkGray

    $apiKey = Read-ApiKey '输入 Tuzi API Key（不会回显）'
    if ([string]::IsNullOrWhiteSpace($apiKey)) { Fail 'API Key 不能为空。' }

    try {
        if ($group -eq 'gaccode') {
            $models = @('claude-opus-4-6', 'claude-sonnet-4-6', 'claude-haiku-4-5-20251001')
            $primary = 'claude-opus-4-6'
            Write-Host 'GAC Claude: claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5-20251001'
            Write-Host 'GAC Codex: gpt-5.4'
        } else {
            $availableModels = @(Get-TuziModels $apiKey)
            $models = @(Select-TuziModels $availableModels $group)
            $primary = $models[0]
        }

        $updateDefault = Confirm-Choice '是否将该模型设为默认模型？' $true
        $writeResult = Write-TuziConfig $group $apiKey $primary $models $updateDefault
    } finally {
        $apiKey = $null
    }

    Write-Host "配置已写入: $($writeResult.ConfigPath)" -ForegroundColor Green
    if ($null -ne $writeResult.BackupPath) {
        Write-Host "原配置备份: $($writeResult.BackupPath)" -ForegroundColor DarkGray
    }
    $provider = if ($group -eq 'codex') { 'tuzi-codex' } elseif ($group -eq 'gaccode') { 'gac-claude + gac-codex' } else { 'tuzi-claude-code' }
    Write-Host "Provider: $provider" -ForegroundColor Green
    Write-Host "主模型: $primary" -ForegroundColor Green

    return [PSCustomObject]@{
        Group = $group
        ConfigPath = $writeResult.ConfigPath
        Primary = $primary
    }
}

function Test-TuziConnection([string]$ConfigPath) {
    if (-not (Confirm-Choice '是否执行一次 AI 连接测试？' $true)) { return }

    Write-Host ''
    Write-Host '第 2 步: 测试 API 连接' -ForegroundColor Cyan
    Write-Host '使用隔离 openclaw agent exec 测试，不写入 session main。' -ForegroundColor DarkGray
    & openclaw agent exec --config $ConfigPath --timeout 25 '回复 OK'
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'OpenClaw AI 测试成功。' -ForegroundColor Green
    } else {
        Write-Host '[WARN] AI 测试失败，但已保存的配置未删除。上游过载时可稍后重试。' -ForegroundColor Yellow
        Write-Host "重试命令: openclaw agent exec --config `"$ConfigPath`" --timeout 25 '回复 OK'" -ForegroundColor DarkGray
    }
}

function Setup-Gateway {
    Write-Host ''
    Write-Host '第 3 步: 配置 Gateway' -ForegroundColor Cyan
    if (Confirm-Choice '是否安装 Gateway 系统服务并设置开机启动？' $true) {
        & openclaw gateway install
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Gateway 系统服务已安装。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] Gateway 系统服务安装失败，可稍后用管理员终端重试。' -ForegroundColor Yellow
        }
    }

    if (Confirm-Choice '是否现在启动 Gateway？' $true) {
        & openclaw gateway start
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Gateway 已启动。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] Gateway 启动失败，请运行 openclaw doctor 检查。' -ForegroundColor Yellow
        }
    }
}

Write-Host 'OpenClaw Windows installer' -ForegroundColor Cyan
Write-Host 'This is the native PowerShell entry point. Do not run install.sh from cmd.exe or Git Bash.'
Write-Host ''

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Fail 'PowerShell 5.1 or newer is required.'
}

if (-not $SkipOfficialInstall) {
    Write-Host 'Installing/updating OpenClaw with the official installer...' -ForegroundColor Yellow
    Require-Command 'Invoke-RestMethod'
    $official = Invoke-RestMethod -Uri 'https://openclaw.ai/install.ps1'
    & ([scriptblock]::Create([string]$official)) -NoOnboard
}

Require-Command 'openclaw'
Require-Command 'node'
$version = (& openclaw --version 2>$null | Select-Object -First 1)
Write-Host "OpenClaw detected: $version" -ForegroundColor Green

if ($NoOnboard) {
    Write-Host 'The -NoOnboard compatibility option is no longer needed; Tuzi setup is native to this installer.' -ForegroundColor DarkGray
}

if (-not $SkipTuziConfig) {
    $tuzi = Configure-Tuzi
    Test-TuziConnection $tuzi.ConfigPath
}

Setup-Gateway

Write-Host ''
Write-Host 'Installation complete.' -ForegroundColor Green
Write-Host 'Start the Gateway: openclaw gateway start'
Write-Host 'Open the terminal UI: openclaw tui'
Write-Host 'Configure Tuzi again: irm https://raw.githubusercontent.com/Jerry-George-Liang/openclaw-shell/main/install-windows.ps1 | iex'
Write-Host 'Configure another provider manually: openclaw onboard'
