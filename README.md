# xclaude

macOS Seatbelt sandbox for Claude Code. Wraps the `claude` binary in `sandbox-exec` with a strict SBPL profile that restricts filesystem access to an explicit allowlist.

## Why

Claude Code's built-in sandbox (`sandbox.enabled` in settings) has [known issues](https://github.com/anthropics/claude-code/issues/31473) on macOS — `denyRead` is ineffective, `allowRead` doesn't exist in the schema, and the generated SBPL profiles can crash silently. This project replaces it with a hand-tuned Seatbelt profile that actually works.

## What it does

- **Reads**: `file-read-data` allowlist only. System runtime paths, Claude config, project directory, and declared toolchains. Everything else in `$HOME` is blocked.
- **Writes**: project directory, Claude state files, tmp directories. Nothing else unless declared.
- **Non-filesystem**: network, IPC, Mach ports are open (the goal is filesystem isolation).
- **Exec**: system binaries, Homebrew, Claude binary, project scripts, and declared toolchains.

### Blocked by default

`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.docker`, `~/Desktop`, `~/Downloads`, `~/Documents`, `~/Library` (except Keychains for auth), `~/.zsh_history`, and anything else not explicitly listed.

### Write-protected inside the project

Even though the project directory is writable, these files are protected by deny-after-allow rules (SBPL last-match-wins):

- `.xclaude` — sandbox config, prevents privilege escalation
- `.env`, `.env.local`, `.env.production` — secrets and API keys
- `.git/hooks/` — prevents injection of code that runs on git operations

### Trust gate

When a project has a `.xclaude` config, xclaude computes its sha256 hash and checks `~/.config/xclaude/trusted`. If the config is new or changed, xclaude shows its contents and prompts for approval before applying it. This prevents a malicious commit from silently widening sandbox access.

### Verified escape vectors

Symlink traversal, hardlinks, /tmp script execution, child process inheritance (python, node, bash), fd redirects, and curl exfiltration of blocked files — all blocked by Seatbelt's kernel-level enforcement.

## Setup

1. Source the wrapper in your shell:

```bash
source /path/to/xclaude.zsh
```

2. Use `xclaude` instead of `claude`:

```bash
cd /path/to/your/project
xclaude
```

The wrapper assembles a sandbox profile from the base policy, any declared toolchains, and project-specific config, then launches Claude under `sandbox-exec`. Claude's internal permissions are bypassed (`--dangerously-skip-permissions`) since the OS sandbox enforces the real boundaries.

## Project configuration

Create a `.xclaude` file in your project root to declare toolchains and extra paths.

### DSL reference

```sh
# Toolchains — predefined sandbox profiles
tool node
tool uv

# Extra paths
allow-read ~/.config/special       # read-only access
allow-write ./local/.share          # read + write access
allow-exec ~/.local/bin/custom      # read + exec access
```

**Directives:**

| Directive | Effect | Use case |
|---|---|---|
| `tool <name>` | Activates a bundled toolchain | Language runtimes, package managers |
| `allow-read <path>` | Adds `file-read-data` | Config files, shared libraries |
| `allow-write <path>` | Adds `file-read-data` + `file-write*` | Build caches, data directories |
| `allow-exec <path>` | Adds `file-read-data` + `process-exec` | Custom binaries, scripts |

**Path expansion:**

| Prefix | Expands to | Example |
|---|---|---|
| `~/` | `$HOME` | `~/.cargo` → `/Users/you/.cargo` |
| `./` | `$PROJECT_DIR` | `./local/.share` → `/path/to/project/local/.share` |
| `/` | absolute | `/opt/custom` → `/opt/custom` |

**Safety constraints** — the DSL is intentionally limited:

- No `deny` — you can only widen access, never narrow it
- No raw SBPL — all rules are generated from validated directives
- No system paths — `/System`, `/usr`, `/bin`, `/Library`, `/opt/homebrew` are already in the base profile
- No bare `~` — you must specify a subdirectory
- No targeting `.xclaude` — the sandbox config file is protected

### Available toolchains

| Name | What it allows |
|---|---|
| `node` | NVM (`~/.nvm`), npm/npx cache (`~/.npm`) |
| `pnpm` | pnpm binary (`~/.local/share/pnpm`), global store (`~/.pnpm-store`), dlx |
| `bun` | Bun runtime, install cache (`~/.bun`) |
| `uv` | uv/uvx, `uv tool install`, cache (`~/Library/Caches/uv`, `~/.local/share/uv`) |
| `python` | pyenv (`~/.pyenv`) |
| `rust` | Cargo (`~/.cargo`), rustup (`~/.rustup`) |
| `go` | Go toolchain (`/usr/local/go`, `~/go`), build cache (`~/.cache/go-build`) |
| `deno` | Deno runtime and cache (`~/.deno`) |
| `gh` | GitHub CLI auth tokens (`~/.config/gh`, read-only) |
| `huggingface` | Model cache, auth tokens, assets (`~/.cache/huggingface`) |

### User-level config

For personal paths that apply to all projects (e.g., shell config symlink targets), create `~/.config/xclaude/config` using the same DSL:

```sh
# Personal tools available in all projects
allow-read ~/Documents/GitHub/codewithcheese/macos-setup
allow-read ~/.config/auto-chat
allow-write ~/.config/auto-chat
```

### Load order

```
base.sb                          # core Claude needs (always)
+ ~/.config/xclaude/config       # user-level (if exists)
+ .xclaude                       # project-level (if exists, trust-gated)
```

All layers are additive. The base profile provides `(deny default)` and cannot be weakened by config files.

## Files

| File | Purpose |
|---|---|
| `xclaude.zsh` | Shell wrapper — DSL parser, validator, SBPL generator, assembler, trust gate |
| `base.sb` | Core Seatbelt/SBPL profile (deny default + Claude Code needs) |
| `toolchains/*.sb` | Bundled toolchain SBPL fragments |
| `toolchains/*.test.zsh` | Sandbox tests for each toolchain |
| `toolchains/test_helpers.zsh` | Shared test helpers (`tc_setup`, `tc_sandboxed`, etc.) |
| `test_xclaude.bash` | DSL pipeline unit tests (bash, any platform) |
| `test_sandbox.zsh` | Sandbox integration test runner (zsh, macOS only) |
| `CLAUDE.md` | Development guide |
| `DEBUGGING.md` | Guide for diagnosing sandbox issues |

### SBPL parameter reference

| Parameter | Set by | Example |
|---|---|---|
| `HOME` | `xclaude.zsh` | `/Users/tom` |
| `PROJECT_DIR` | `xclaude.zsh` (resolved via `readlink -f`) | `/Users/tom/myproject` |
| `TMPDIR` | `xclaude.zsh` (resolved via `readlink -f`) | `/private/var/folders/.../T` |
| `CACHE_DIR` | `xclaude.zsh` (derived from TMPDIR) | `/private/var/folders/.../C` |

## Testing

**DSL pipeline tests** (any platform, bash 4+):

```bash
bash test_xclaude.bash
```

Tests parser, validator, generator, and assembler — no macOS or sandbox required.

**Sandbox integration tests** (macOS only):

```bash
# All tests (base + all toolchains)
zsh test_sandbox.zsh

# Base profile only
zsh test_sandbox.zsh --toolchain none

# Specific toolchain(s)
zsh test_sandbox.zsh --toolchain node
zsh test_sandbox.zsh --toolchain node,uv

# Custom project config
zsh test_sandbox.zsh --with-config my-project/.xclaude
```

Each toolchain is tested in its own parallel CI job with the tool installed. Tests verify:
- Read/write/exec access to declared paths
- Tool usability (real operations: npm install, cargo build, uv pip install, etc.)
- Isolation (sensitive paths remain blocked)
- Write protection (`.xclaude`, `.env`, `.git/hooks`)
- Escape vectors (symlinks, path traversal, child processes)

When a test fails unexpectedly, stderr and recent sandbox denial logs are displayed automatically.

## Compatibility

- macOS 14+ (Apple Silicon and Intel)
- Claude Code 2.1.x+
- Works with cmux wrapper
- `sandbox-exec` is deprecated by Apple but still functional (Chromium uses the same approach)
