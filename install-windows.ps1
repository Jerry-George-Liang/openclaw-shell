param(
    [switch]$SkipOfficialInstall,
    [switch]$NoOnboard,
    [switch]$SkipTuziConfig
)

$ErrorActionPreference = 'Stop'
$InstallerVersion = '2026.09.08.9'

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

function Resolve-OpenClawRuntime {
    $candidates = @()
    foreach ($name in @('openclaw.cmd', 'openclaw')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
            $candidates += $command.Source
        }
    }

    $npmPrefix = $null
    foreach ($npmName in @('npm.cmd', 'npm.exe', 'npm')) {
        $npmCommand = Get-Command $npmName -ErrorAction SilentlyContinue
        if ($null -eq $npmCommand) { continue }
        try {
            $prefixOutput = @(& $npmCommand.Source config get prefix 2>$null)
            if ($LASTEXITCODE -eq 0 -and $prefixOutput.Count -gt 0) {
                $npmPrefix = $prefixOutput[-1].ToString().Trim()
            }
        } catch {}
        break
    }

    $candidateDirs = @()
    if (-not [string]::IsNullOrWhiteSpace($npmPrefix)) {
        $candidateDirs += $npmPrefix
        $candidateDirs += (Join-Path $npmPrefix 'bin')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidateDirs += (Join-Path $env:APPDATA 'npm')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidateDirs += (Join-Path $env:USERPROFILE '.local\bin')
    }
    foreach ($dir in @($candidateDirs | Select-Object -Unique)) {
        $candidates += (Join-Path $dir 'openclaw.cmd')
        $candidates += (Join-Path $dir 'openclaw.exe')
        $candidates += (Join-Path $dir 'openclaw')
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        try {
            $versionOutput = @(& $candidate --version 2>$null)
            $exitCode = $LASTEXITCODE
            $version = @($versionOutput | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) | Select-Object -First 1
            if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($version)) {
                $commandDir = Split-Path -Parent $candidate
                $pathParts = @($env:PATH -split ';')
                if ($pathParts -notcontains $commandDir) {
                    $env:PATH = "$commandDir;$env:PATH"
                }
                return [PSCustomObject]@{ Path = $candidate; Version = $version }
            }
        } catch {}
    }

    return $null
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

function Get-TuziModelIds($Response) {
    $items = if ($null -ne $Response.data) { $Response.data } else { $Response }
    return @(
        $items |
            ForEach-Object { $_.id } |
            Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Select-Object -Unique
    )
}

function Get-TuziModelsViaNode([string]$ApiKey) {
    $nodeScript = @'
const https = require('https');
const request = https.request('https://api.tu-zi.com/v1/models', {
  method: 'GET',
  headers: { Authorization: `Bearer ${process.env.OPENCLAW_TUZI_KEY}`, Accept: 'application/json' }
}, (response) => {
  let body = '';
  response.setEncoding('utf8');
  response.on('data', (chunk) => { body += chunk; });
  response.on('end', () => process.stdout.write(JSON.stringify({ status: response.statusCode, body })));
});
request.setTimeout(30000, () => request.destroy(new Error('request timeout')));
request.on('error', (error) => { console.error(error.message); process.exitCode = 1; });
    request.end();
'@
    $previousKey = $env:OPENCLAW_TUZI_KEY
    $previousErrorActionPreference = $ErrorActionPreference
    $raw = @()
    $exitCode = 1
    try {
        $env:OPENCLAW_TUZI_KEY = $ApiKey
        $ErrorActionPreference = 'Continue'
        $raw = @(& node -e $nodeScript 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($null -eq $previousKey) {
            Remove-Item Env:OPENCLAW_TUZI_KEY -ErrorAction SilentlyContinue
        } else {
            $env:OPENCLAW_TUZI_KEY = $previousKey
        }
    }
    if ($exitCode -ne 0 -or $raw.Count -eq 0) { return @() }
    try {
        $envelope = (($raw | ForEach-Object { $_.ToString() }) -join "`n") | ConvertFrom-Json
        if ([int]$envelope.status -lt 200 -or [int]$envelope.status -ge 300) { return @() }
        return @(Get-TuziModelIds (($envelope.body | ConvertFrom-Json)))
    } catch {
        return @()
    }
}

function Get-TuziModels([string]$ApiKey) {
    $powershellError = $null
    try {
        $response = Invoke-RestMethod -Uri 'https://api.tu-zi.com/v1/models' `
            -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec 30
        $models = @(Get-TuziModelIds $response)
        if ($models.Count -gt 0) {
            Write-Host "已从 Tuzi 接口获取 $($models.Count) 个模型。" -ForegroundColor Green
            return $models
        }
    } catch {
        $powershellError = $_.Exception.Message
    }

    Write-Host '[WARN] PowerShell 获取 Tuzi 模型列表失败，改用 Node.js 网络兼容通道重试。' -ForegroundColor Yellow
    $models = @(Get-TuziModelsViaNode $ApiKey)
    if ($models.Count -gt 0) {
        Write-Host "已通过 Node.js 兼容通道获取 $($models.Count) 个模型。" -ForegroundColor Green
        return $models
    }

    $detail = if ([string]::IsNullOrWhiteSpace($powershellError)) { 'Node.js 请求也未返回可用模型' } else { $powershellError }
    Write-Host "[WARN] Tuzi 模型列表获取失败 ($detail)，将改为手动输入。" -ForegroundColor Yellow
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

function Remove-AgentExecTempState([string]$AgentText) {
    $pathMatch = [regex]::Match(
        $AgentText,
        "(?im)Agent exec cleanup failed:.*?unlink\s+['`"](?<path>[^'`"`r`n]+openclaw\.sqlite)['`"]"
    )
    if (-not $pathMatch.Success) { return $false }

    try {
        $sqlitePath = [IO.Path]::GetFullPath($pathMatch.Groups['path'].Value)
        $stateDir = Split-Path -Parent $sqlitePath
        $agentDir = Split-Path -Parent $stateDir
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $agentParent = [IO.Path]::GetFullPath((Split-Path -Parent $agentDir)).TrimEnd('\', '/')
        $agentName = Split-Path -Leaf $agentDir

        $validTarget = (
            [string]::Equals($agentParent, $tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            $agentName -like 'openclaw-agent-exec-*' -and
            (Split-Path -Leaf $stateDir) -eq 'state' -and
            (Split-Path -Leaf $sqlitePath) -eq 'openclaw.sqlite'
        )
        if (-not $validTarget) { return $false }

        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                if (Test-Path -LiteralPath $agentDir) {
                    Remove-Item -LiteralPath $agentDir -Recurse -Force -ErrorAction Stop
                }
                if (-not (Test-Path -LiteralPath $agentDir)) { return $true }
            } catch {
                if ($attempt -lt 5) { Start-Sleep -Milliseconds 300 }
            }
        }
    } catch {}
    return $false
}

function Test-TuziConnection([string]$ConfigPath, [string]$OpenClawPath) {
    if ([string]::IsNullOrWhiteSpace($OpenClawPath)) {
        Write-Host '[WARN] 当前终端暂时找不到可运行的 openclaw 命令，已跳过 AI 连接测试。' -ForegroundColor Yellow
        Write-Host '请关闭并重新打开 PowerShell，再运行 openclaw --version 和 openclaw doctor。' -ForegroundColor Cyan
        return
    }
    if (-not (Confirm-Choice '是否执行一次 AI 连接测试？' $true)) { return }

    Write-Host ''
    Write-Host '第 2 步: 测试 API 连接' -ForegroundColor Cyan
    Write-Host '使用隔离 openclaw agent exec 测试，不写入 session main。' -ForegroundColor DarkGray
    $agentOutput = @()
    $agentExitCode = 1
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 wraps native stderr as NativeCommandError.
        $ErrorActionPreference = 'Continue'
        & $OpenClawPath agent exec --config $ConfigPath --timeout 25 '回复 OK' 2>&1 |
            ForEach-Object {
                $line = $_.ToString()
                $agentOutput += $line
                Write-Host $line
            }
        $agentExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $agentText = $agentOutput -join "`n"
    $windowsCleanupOnly = (
        $agentExitCode -ne 0 -and
        $agentText -match '(?i)provider-transport-fetch.*response.*status=200' -and
        $agentText -match '(?i)stopReason=stop' -and
        $agentText -match '(?i)Agent exec cleanup failed:.*EBUSY' -and
        $agentText -match '(?i)openclaw-agent-exec.*openclaw\.sqlite'
    )
    if ($agentExitCode -eq 0) {
        Write-Host 'OpenClaw AI 测试成功。' -ForegroundColor Green
    } elseif ($windowsCleanupOnly) {
        if (Remove-AgentExecTempState $agentText) {
            Write-Host '[WARN] AI 请求已成功；Windows 文件锁导致 OpenClaw 首次清理失败，安装器已清除本次隔离测试目录。' -ForegroundColor Yellow
        } else {
            Write-Host '[WARN] AI 请求已成功，但本次隔离测试的临时目录未能清理。' -ForegroundColor Yellow
        }
        Write-Host '本次结果按连接成功处理；未读取、删除或修改你的主配置和主会话数据。' -ForegroundColor DarkGray
    } else {
        Write-Host '[WARN] AI 测试失败，但已保存的配置未删除。上游过载时可稍后重试。' -ForegroundColor Yellow
        Write-Host "重试命令: openclaw agent exec --config `"$ConfigPath`" --timeout 25 '回复 OK'" -ForegroundColor DarkGray
    }
}

function Invoke-OpenClawStateRepair([string]$OpenClawPath) {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Write-Host ''
        Write-Host "运行 OpenClaw 状态修复 (第 $attempt 次)..." -ForegroundColor Cyan
        $repairOutput = @()
        $repairExitCode = 1
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # Windows PowerShell 5.1 can surface native stderr as a terminating record.
            $ErrorActionPreference = 'Continue'
            & $OpenClawPath doctor --fix 2>&1 |
                ForEach-Object {
                    $line = $_.ToString()
                    $repairOutput += $line
                    Write-Host $line
                }
            $repairExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($repairExitCode -eq 0) {
            Write-Host 'OpenClaw 状态迁移修复成功。' -ForegroundColor Green
            return $true
        }

        $repairText = $repairOutput -join "`n"
        $legacyAgentBackup = (
            $repairText -match '(?i)Left legacy agent dir at .*agent\.legacy-' -and
            $repairText -match '(?i)Doctor stopped because a state migration refused to continue'
        )
        if ($attempt -eq 1 -and $legacyAgentBackup) {
            Write-Host '[WARN] Doctor 已保留 agent.legacy-* 旧状态备份；将再运行一次以继续后续迁移。' -ForegroundColor Yellow
            continue
        }

        Write-Host '[WARN] OpenClaw 状态迁移仍未完成，保留现有配置和 legacy 备份目录。' -ForegroundColor Yellow
        return $false
    }
    return $false
}

function Test-OpenClawGatewayReady([string]$OpenClawPath) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($attempt -gt 1) { Start-Sleep -Seconds 2 }
        $statusOutput = @()
        $statusExitCode = 1
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $statusOutput = @(& $OpenClawPath gateway status --deep --json 2>&1)
            $statusExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($statusOutput.Count -eq 0) { continue }

        try {
            $statusText = ($statusOutput | ForEach-Object { $_.ToString() }) -join "`n"
            $status = $statusText | ConvertFrom-Json
            if ($status.rpc.ok -eq $true -and $status.service.runtime.status -eq 'running') {
                return $true
            }
        } catch {
            if ($statusExitCode -eq 0 -and $statusText -match '(?i)Connectivity probe:\s*ok') {
                return $true
            }
        }
    }
    return $false
}

function Setup-Gateway([bool]$NeedsManualRepair = $false, [string]$OpenClawPath, [bool]$ForceReinstall = $false) {
    Write-Host ''
    Write-Host '第 3 步: 配置 Gateway' -ForegroundColor Cyan
    if ($NeedsManualRepair) {
        Write-Host '[WARN] 官方安装器未能确认现有 Gateway 服务的归属。' -ForegroundColor Yellow
        Write-Host '为避免覆盖其他服务，本次不会自动安装、停止或重启 Gateway。' -ForegroundColor Yellow
        Write-Host '请先运行: openclaw gateway status --deep' -ForegroundColor Cyan
        Write-Host '根据输出停止对应服务后运行: openclaw doctor --fix' -ForegroundColor Cyan
        Write-Host '修复完成后运行: openclaw gateway install; openclaw gateway start' -ForegroundColor Cyan
        return
    }

    if ([string]::IsNullOrWhiteSpace($OpenClawPath)) {
        Write-Host '[WARN] 当前终端暂时找不到可运行的 openclaw 命令，已跳过 Gateway 操作。' -ForegroundColor Yellow
        Write-Host '重新打开 PowerShell 后运行: openclaw gateway install; openclaw gateway start' -ForegroundColor Cyan
        return
    }

    if (Confirm-Choice '是否安装 Gateway 系统服务并设置开机启动？' $true) {
        $installArgs = @('gateway', 'install')
        if ($ForceReinstall) { $installArgs += '--force' }
        & $OpenClawPath @installArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Gateway 系统服务已安装。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] Gateway 系统服务安装失败，可稍后用管理员终端重试。' -ForegroundColor Yellow
            return
        }
    }

    if (Confirm-Choice '是否现在启动 Gateway？' $true) {
        & $OpenClawPath gateway start
        if ($LASTEXITCODE -eq 0 -and (Test-OpenClawGatewayReady $OpenClawPath)) {
            Write-Host 'Gateway 已启动并通过连接检查。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] Gateway 启动后未通过连接检查，计划任务可能立即退出。' -ForegroundColor Yellow
            Write-Host '请运行 openclaw gateway status --deep 查看日志路径和退出状态。' -ForegroundColor Cyan
        }
    }
}

Write-Host 'OpenClaw Windows installer' -ForegroundColor Cyan
Write-Host "Installer version: $InstallerVersion" -ForegroundColor DarkGray
Write-Host 'This is the native PowerShell entry point. Do not run install.sh from cmd.exe or Git Bash.'
Write-Host ''

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Fail 'PowerShell 5.1 or newer is required.'
}

$officialInstallerWarning = $false
if (-not $SkipOfficialInstall) {
    Write-Host 'Installing/updating OpenClaw with the official installer...' -ForegroundColor Yellow
    Require-Command 'Invoke-RestMethod'
    $official = Invoke-RestMethod -Uri 'https://openclaw.ai/install.ps1'
    $officialOutput = @()
    try {
        & ([scriptblock]::Create([string]$official)) -NoOnboard 2>&1 6>&1 |
            ForEach-Object {
                $officialOutput += $_
                Write-Host $_
            }
    } catch {
        $officialText = @($officialOutput | ForEach-Object { $_.ToString() }) -join "`n"
        $gatewayOwnershipFailure = (
            $officialText -match 'SERVICE_DEFINITION_UNKNOWN' -or
            $officialText -match '(?i)Gateway service ownership or shutdown could not be verified'
        )
        $knownGatewayMigrationFailure = (
            $officialText -match '(?i)OpenClaw installed' -and
            $gatewayOwnershipFailure -and
            $officialText -match '(?i)Migration failed'
        )
        if (-not $knownGatewayMigrationFailure) {
            Fail "OpenClaw 官方安装失败: $($_.Exception.Message)"
        }

        $officialInstallerWarning = $true
        Write-Host ''
        Write-Host '[WARN] OpenClaw 已安装，但官方安装器的服务迁移未完成。' -ForegroundColor Yellow
        Write-Host '[WARN] 继续执行 Tuzi 配置，不会自动处理归属不明的旧 Gateway 服务。' -ForegroundColor Yellow
    }
}

Require-Command 'node'
$openclawRuntime = Resolve-OpenClawRuntime
if ($null -ne $openclawRuntime) {
    Write-Host "OpenClaw detected: $($openclawRuntime.Version)" -ForegroundColor Green
} else {
    Write-Host '[WARN] OpenClaw 已安装，但当前终端尚未找到可运行的命令。' -ForegroundColor Yellow
    Write-Host '[WARN] Tuzi 配置仍将完成；安装结束后请重新打开 PowerShell。' -ForegroundColor Yellow
}

if ($NoOnboard) {
    Write-Host 'The -NoOnboard compatibility option is no longer needed; Tuzi setup is native to this installer.' -ForegroundColor DarkGray
}

if (-not $SkipTuziConfig) {
    $tuzi = Configure-Tuzi
    Test-TuziConnection $tuzi.ConfigPath $openclawRuntime.Path
}

$stateRepairCompleted = $false
if ($officialInstallerWarning -and -not [string]::IsNullOrWhiteSpace($openclawRuntime.Path)) {
    $stateRepairCompleted = Invoke-OpenClawStateRepair $openclawRuntime.Path
    if ($stateRepairCompleted) { $officialInstallerWarning = $false }
}

Setup-Gateway $officialInstallerWarning $openclawRuntime.Path $stateRepairCompleted

Write-Host ''
if ($officialInstallerWarning) {
    Write-Host 'OpenClaw and Tuzi setup complete with a Gateway service warning.' -ForegroundColor Yellow
    Write-Host 'Inspect the existing service: openclaw gateway status --deep'
    Write-Host 'Temporary foreground Gateway: openclaw gateway run'
} else {
    Write-Host 'Installation complete.' -ForegroundColor Green
    Write-Host 'Start the Gateway: openclaw gateway start'
}
Write-Host 'Open the terminal UI: openclaw tui'
Write-Host "Configure Tuzi again: `$u='https://raw.githubusercontent.com/Jerry-George-Liang/openclaw-shell/main/install-windows.ps1?cachebust='+[guid]::NewGuid().ToString('N'); irm `$u | iex"
Write-Host 'Configure another provider manually: openclaw onboard'
