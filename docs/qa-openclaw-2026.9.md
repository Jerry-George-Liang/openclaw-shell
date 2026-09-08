# OpenClaw 2026.9.2 Compatibility QA

Date: 2026-09-08

## Scope

- Installer Node.js compatibility gates (22.22.3+, 24.15.0+, 25.9.0+, or 26+) and stable Node.js 22 LTS installation commands.
- Official Gateway service lifecycle and update commands.
- Isolated one-shot `agent exec` validation without writing to `session main`.
- Docker authenticated startup configuration.
- Native Windows PowerShell entry point with UTF-8 console setup and first-party Tuzi configuration.
- Native `cmd.exe` launcher delegating to PowerShell.
- Tuzi/GAC provider writes, model selection, and Feishu setup path.
- macOS Intel/Apple Silicon, Linux, root/no-sudo, and Windows/WSL2 branching.

## Executed Checks

| Check | Expected result | Result |
| --- | --- | --- |
| `bash -n install.sh config-menu.sh docker-entrypoint.sh scripts/preflight-check.sh` | Shell syntax is valid | Passed |
| `scripts/preflight-check.sh` | Legacy commands/config paths are absent; supported Node versions are accepted | Passed |
| `OPENCLAW_GATEWAY_TOKEN=test docker compose config` | Compose variables and localhost port binding render correctly | Passed; binds `127.0.0.1:18789` |
| Entrypoint with no Gateway credential | Container exits before starting an unauthenticated LAN Gateway | Passed; exits 1 before filesystem/runtime setup |
| Isolated `openclaw@2026.9.2` `config validate` against `examples/openclaw.example.json5` | Current CLI accepts the generated JSON5 shape | Passed; `Config valid` |
| Isolated Tuzi Codex provider write | `models.providers`, `agents.defaults.model`, and `auth.profiles` are written with current keys | Passed; two models and `tuzi-codex/gpt-5.4` validated |
| Isolated GAC provider write | Claude/Codex providers and auth profiles are written with current keys | Passed; both providers and `gac-claude/claude-opus-4-6` validated |
| Isolated configuration-menu save | Existing environment variables survive a Tuzi save and resulting config validates | Passed |
| `set_env_kv` isolated shell test | Updating one provider preserves unrelated environment variables | Passed |
| Node version boundary and platform branch checks | Reject unsupported Node 23/old minors and direct Windows to PowerShell/WSL2 | Passed |
| Installer AI test command | Uses `openclaw agent exec` with temporary isolated state instead of a Gateway session | Passed by static review |
| Architecture branch inspection | Recognize amd64/arm64 families and warn on unknown values | Passed by static review |
| Windows native installer | Uses PowerShell and the official installer, then enters Tuzi setup instead of OpenAI onboarding | Passed by static review |
| Windows cmd launcher | Delegates from `cmd.exe` to PowerShell and avoids Bash parsing | Passed by static review |
| Windows Tuzi providers | Writes `tuzi-claude-code` or `tuzi-codex`; GACCode writes both `gac-claude` and `gac-codex` | Passed by static review |
| Windows configuration safety | Creates the config directory, backs up an existing config, writes via a temporary file, and keeps the API Key out of process arguments | Passed by static review |
| Windows AI test and Gateway flow | Uses isolated `agent exec`, then offers service installation and startup | Passed by static review |
| Windows failed post-install migration | Continues only for the exact installed + `SERVICE_DEFINITION_UNKNOWN` + migration-failed signature and a usable `openclaw --version`; skips automatic Gateway mutation | Passed by static review |
| PowerShell parser | PowerShell 7.4 parses `install-windows.ps1` without syntax errors | Passed in a read-only Linux PowerShell container |
| Windows embedded config writer | Fake-key writes produce the expected Claude-Code, Codex, and dual GAC providers | Passed in three isolated temporary directories |
| New Node.js installation line | Installs Node.js 22 LTS on Homebrew/NodeSource while retaining supported newer existing versions | Passed by static review |
| Linux stale Node path recovery | Selects a supported `/usr/bin/node` after package installation when nvm/asdf still resolves an older runtime | Passed by static review |

## Not Executed

- A real installation/update was not run on the host, so no global npm package or user configuration was changed.
- Gateway, Tuzi/GAC API, and Feishu wizard end-to-end tests require isolated credentials and a real OpenClaw runtime.
- Docker `linux/arm64` image build was attempted but could not fetch the anonymous Docker Hub token before the network deadline; Dockerfile syntax and Compose rendering passed, but image build remains unverified. The default base is pinned to Node 22 LTS (`node:22-bookworm-slim`).
- Native Windows, Linux distributions other than the current host, and both macOS CPU variants were not booted in this environment; those paths are covered by static branch checks only. Windows PowerShell 5.1/CMD input, service installation, atomic replacement behavior, and full Tuzi/GAC calls still need validation on a Windows host.
- The reported Windows `SERVICE_DEFINITION_UNKNOWN` upgrade path was reproduced from the official installer source, but not against the affected Windows service. The wrapper now preserves that service and requires owner-aware manual repair.

## Residual Risk

- Existing user JSON5 files with comments are not rewritten through OpenClaw CLI patch commands; the provider writers still require strict JSON parsing. A failed parse must be treated as a configuration error and corrected before rerunning.
- The Windows native installer aligns the core install, Tuzi model, isolated test, and Gateway lifecycle. The full Bash channel configuration menu remains available only through WSL2.
- OpenClaw commands are version-sensitive. The installer delegates normal installation and update behavior to the official CLI/installer, then performs local static checks.
- A direct npm fallback install may not carry the package-manager ownership metadata required by `openclaw update`; the configuration menu now reports this case and points to reinstalling through the official installer.
- Docker uses the official Debian slim multi-architecture Node base image, `tini`, and non-root `node` user; actual image pulls and native-module builds still need CI coverage on `linux/amd64` and `linux/arm64`.
- Docker bind mounts can fail on Linux when the host directory is not writable by container UID 1000; the entrypoint now reports this explicitly and the README documents the `chown` or named-volume options.
- System utilities (`curl`, `wget`, `jq`, `git`, `openssl`) intentionally follow the host distribution's stable repositories rather than a single global version because package availability and ABI compatibility vary across supported distributions.
