# xclaude

A macOS Seatbelt sandbox for agent CLIs — [Claude Code](https://claude.com/claude-code) via `xclaude` and Codex CLI via `xcodex`. Each wrapper runs the underlying agent in `sandbox-exec` with a strict, layered SBPL profile so the agent can only read and write files you've explicitly allowed.

## Why

By default Claude Code can read and write anywhere your shell can — including `~/.ssh`, `~/.aws`, browser profiles, shell history, and any document on disk. Anthropic ships a built-in sandbox option (`sandbox.enabled` in settings) but it has [known issues](https://github.com/anthropics/claude-code/issues/31473) on macOS: `denyRead` is ineffective, `allowRead` doesn't exist in the schema, and the generated SBPL profiles can crash the process silently.

xclaude replaces it with a hand-tuned Seatbelt profile that **defaults to strict deny**, lets you opt in to extra access via a tiny safe DSL, and ships with a Claude Code plugin so the agent helps you fix denials instead of working around them.

## What it protects

The sandbox enforces **filesystem isolation only**. Network, IPC, and Mach ports are open — see [Known limitations](#known-limitations) for the trade-offs.

### Reads, writes, exec

| Operation | Default policy |
|---|---|
| `file-read-data` | Strict allowlist: system runtime, Claude config, project directory, declared toolchains |
| `file-write*` | Project directory, Claude state files, tmp directories, code-signing clones — nothing else without an explicit rule |
| `process-exec` | System binaries, Homebrew, Claude binary, project scripts, declared toolchains |
| `network*`, `mach*`, `ipc-posix*` | All allowed |

### Blocked by default

`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.docker`, `~/Desktop`, `~/Downloads`, `~/Documents`, `~/Library` (except `~/Library/Keychains` for OAuth), `~/.zsh_history`, and anything else not explicitly listed.

### Write-protected inside the project

The project directory is writable, but these paths are protected by deny-after-allow rules (SBPL last-match-wins) so the agent cannot tamper with them:

| Path | Why |
|---|---|
| `.xclaude` | Sandbox config — prevents privilege escalation on next launch |
| `.env`, `.env.local`, `.env.development`, `.env.staging`, `.env.test`, `.env.production` | Common locations for secrets and API keys |
| `.git/hooks/` | Prevents injection of code that runs on git operations |

### Verified escape vectors

These attack patterns are all blocked by Seatbelt's kernel-level enforcement and covered by the test suite: symlink traversal, hardlinks, `/tmp` script execution, child process inheritance (python, node, bash), file descriptor redirects, and `curl` exfiltration of locally blocked files.

## Quick start

1. Clone the repo and add it to your PATH:

   ```bash
   git clone https://github.com/codewithcheese/xclaude.git
   export PATH="$PWD/xclaude:$PATH"   # add to your shell rc
   ```

2. Run it from any project directory, using the wrapper for your agent:

   ```bash
   cd /path/to/your/project
   xclaude    # Claude Code
   xcodex     # Codex CLI
   ```

That's it. xclaude assembles a profile from `base.sb` (plus any user/project config), launches Claude Code under `sandbox-exec`, and bypasses Claude's internal permission prompts (`--dangerously-skip-permissions`) — the OS sandbox is the actual boundary.

If your project needs additional access (a runtime, a custom binary, a config file outside the project), add a `.xclaude` file. The bundled `/debug-sandbox` skill will draft it for you the first time something gets blocked.

## How it works

```
base.sb                       # core profile (always applied)
+ ~/.config/xclaude/config    # personal rules for all projects (optional)
+ ./.xclaude                  # project-specific rules (optional, trust-gated)
        │
        ▼
sandbox-exec -f <assembled>   --   claude --dangerously-skip-permissions --plugin-dir <xclaude>
```

All layers are **additive**. The base profile starts with `(deny default)` and the DSL has no `deny` verb, so config files can only widen access — never narrow what the base profile already grants.

The wrapper resolves all paths through `readlink -f` before passing them to `sandbox-exec` because Seatbelt resolves symlinks before matching rules.

### Trust gate

`.xclaude` files are security-sensitive — they control what the sandbox allows. xclaude treats them like direnv: explicit approval is required.

When a project has a `.xclaude` config, xclaude computes its sha256 hash and checks `~/.config/xclaude/trusted`. If the file is **new**, xclaude prints its full contents and prompts for approval. If it has **changed** since it was last approved, xclaude prints a unified diff against the stored copy and prompts again. This prevents a malicious commit from silently widening sandbox access when you `cd` into a cloned repo.

Approved hashes live in `~/.config/xclaude/trusted`; copies of approved configs in `~/.config/xclaude/trusted.d/` (used to render diffs).

The user-level config (`~/.config/xclaude/config`) is **not** trust-gated — you own that file and edits take effect on the next launch.

### xcodex

`xcodex` follows the same DSL and trust model, but uses Codex-specific defaults:

- Project config: `.xcodex`
- User config: `~/.config/xcodex/config`
- Trust ledger: `~/.config/xcodex/trusted`
- Base fragments: `base-common.sb` + `base-codex.sb`

Its base profile grants Codex access to `~/.codex` state and its current CLI install location under `~/.nvm`, instead of Claude-specific paths like `~/.claude` and `~/.local/share/claude`.

## Project configuration

Create a `.xclaude` file in your project root to declare toolchains and extra paths.

### DSL

```sh
# Toolchains — predefined sandbox profiles
tool node
tool uv

# Extra paths
allow-read  ~/.config/special      # read-only access
allow-write ./local/.share         # read + write access
allow-exec  ~/.local/bin/custom    # read + exec access
```

**Directives:**

| Directive | Effect | Use case |
|---|---|---|
| `tool <name>` | Activates a bundled toolchain | Language runtimes, package managers |
| `allow-read <path>` | Adds `file-read-data` (subpath) | Config files, shared libraries, datasets |
| `allow-write <path>` | Adds `file-read-data` + `file-write*` (subpath) | Build caches, data directories |
| `allow-exec <path>` | Adds `file-read-data` + `process-exec` (subpath) | Custom binaries, scripts |

**Path expansion:**

| Prefix | Expands to | Example |
|---|---|---|
| `~/` | `$HOME` | `~/.cargo` → `/Users/you/.cargo` |
| `./` | `$PROJECT_DIR` | `./local/.share` → `/path/to/project/local/.share` |
| `/` | absolute | `/opt/custom` → `/opt/custom` |

**Safety constraints** — the DSL is intentionally narrow:

- **No `deny`** — you can only widen access, never narrow it
- **No raw SBPL** — every rule comes from a validated directive
- **No system paths** — `/System`, `/usr`, `/bin`, `/sbin`, `/Library`, `/opt/homebrew` are already in the base profile and rejected by the validator
- **No bare `~`, `~/`, `.`, or `./`** — you must specify a subdirectory
- **No targeting `.xclaude`** — the sandbox config file is protected from being widened to writable or executable

### Available toolchains

| Name | What it grants |
|---|---|
| `node` | NVM (`~/.nvm` read+exec), npm/npx cache (`~/.npm`), corepack (`~/.cache/node`), pnpm via corepack, global pnpm store (`~/.pnpm-store`), pnpm config (`~/.config/pnpm`) |
| `bun` | Bun runtime and install cache (`~/.bun`) |
| `uv` | uv/uvx, cache (`~/Library/Caches/uv`, `~/.local/share/uv`). `~/.local/bin` is read+exec only — `uv tool install` symlinks are redirected to `~/.local/share/uv/bin/` via `UV_TOOL_BIN_DIR` to prevent binary overwrite attacks |
| `python` | pyenv (`~/.pyenv`) |
| `rust` | Cargo (`~/.cargo`), rustup (`~/.rustup`) |
| `go` | Go toolchain (`/usr/local/go`, `~/go`), build cache (`~/.cache/go-build`) |
| `deno` | Deno runtime and cache (`~/.deno`) |
| `gh` | GitHub CLI auth tokens (`~/.config/gh`, read-only) |
| `huggingface` | Model cache, auth tokens, assets (`~/.cache/huggingface`) |
| `seshi` | Claude Code session indexer hook. Venv (`~/.local/share/uv/tools/seshi`), uv-managed cpython (`~/.local/share/uv/python`), and data dir (`~/.local/share/seshi`). Pair with `huggingface` for embedding model downloads. Does not grant `~/.local/bin` — use the uv-managed binary path directly |
| `cmux` | cmux app bundle (`/Applications/cmux.app`), runtime state (`~/Library/Application Support/cmux`), caches (`~/Library/Caches/cmux`) |
| `playwright` | Browser downloads and binaries (`~/Library/Caches/ms-playwright`) |
| `playwright-chromium` | Chromium-specific macOS integration: locale, input methods, spelling, crash reporter. Requires `tool playwright` |
| `chrome` | Google Chrome.app (read+exec), macOS integration paths, GoogleUpdater. Use with `--no-sandbox --user-data-dir=./profile` |

Adding a new toolchain is a five-file change (SBPL fragment, sandbox test, README row, debug-sandbox skill row, CI job). See [`CLAUDE.md`](CLAUDE.md#adding-a-toolchain) for the full guide.

### User-level config

For personal paths that apply to all projects (e.g., shell config symlink targets, always-on tools), create `~/.config/xclaude/config` using the same DSL:

```sh
# Personal tools available in all projects
tool cmux
allow-read  ~/Documents/GitHub/codewithcheese/macos-setup
allow-read  ~/.config/auto-chat
allow-write ~/.config/auto-chat
```

This layer is applied before the project config, is not trust-gated, and edits take effect on the next launch.

## Bundled plugin

xclaude ships with a Claude Code plugin that's loaded automatically — `xclaude` always launches `claude` with `--plugin-dir <xclaude-install-dir>`. You don't install or enable it separately.

It provides three things:

### Denial hook

`plugin/hooks/sandbox-denial-hook.sh` is registered as a `PostToolUseFailure` hook. When a tool inside the sandbox fails with "Operation not permitted" or "Permission denied", the hook:

1. Tails the sandbox denial log that `xclaude` streams from `/usr/bin/log` (kept outside the sandbox because `log` refuses to run inside one).
2. Filters denials from the last 5 seconds matching `file-read-data`, `file-write`, `process-exec`, or `forbidden-exec`.
3. Injects an `additionalContext` system reminder back to Claude with the specific denials and instructions to invoke `/debug-sandbox` rather than try to bypass the sandbox.

The hook is gated on `XCLAUDE_ACTIVE=1`, so it's a no-op when running plain `claude`.

### `/debug-sandbox` skill

A configuration assistant that drafts `.xclaude` changes. It:

- Considers alternatives to widening permissions first (local installs over global, project-local paths over `~/`)
- Reads `~/.config/xclaude/config` so it doesn't suggest rules you already have
- Identifies your tech stack and matches it to a bundled toolchain when possible
- Picks the narrowest path and the minimum operation (`allow-read` over `allow-write` whenever the tool only needs to read)
- Refuses to suggest workarounds that bypass the sandbox

You can invoke it manually with `/debug-sandbox`, but typically the denial hook will direct Claude to invoke it automatically when something gets blocked.

### `/reload-sandbox` skill — hot reload

`.xclaude` is write-protected inside the sandbox (deny-after-allow), so configuration changes have to happen on disk before the sandbox restarts. The reload skill bridges this gap:

1. The skill `touch`es a sentinel file (`$XCLAUDE_RELOAD_SENTINEL`) and tells you to `/exit`.
2. `xclaude` runs in a `while true` loop. When `claude` exits, it checks for the sentinel.
3. If the sentinel exists, xclaude re-runs the assembler, regenerates the profile, and starts a new `claude --continue` so your conversation resumes seamlessly.
4. If the new `.xclaude` differs from the previously trusted version, the trust gate shows a diff and re-prompts before activating it.

In practice the workflow is: a tool fails → hook injects denial context → Claude invokes `/debug-sandbox` → you approve the proposed `.xclaude` → Claude invokes `/reload-sandbox` → you `/exit` → sandbox restarts with the new rules → conversation continues.

## Detecting the sandbox

xclaude sets `XCLAUDE_ACTIVE=1` for every process inside the sandbox. CLI tools that should only run within the sandbox can check for it:

```bash
# Shell
if [[ "${XCLAUDE_ACTIVE:-}" != "1" ]]; then
  echo "error: must run inside xclaude sandbox" >&2
  exit 1
fi
```

```python
# Python
import os, sys
if os.environ.get("XCLAUDE_ACTIVE") != "1":
    print("error: must run inside xclaude sandbox", file=sys.stderr)
    sys.exit(1)
```

```javascript
// Node.js
if (process.env.XCLAUDE_ACTIVE !== "1") {
  console.error("error: must run inside xclaude sandbox");
  process.exit(1);
}
```

`XCLAUDE_ACTIVE` is the **stable, public** API for sandbox detection — it's inherited by all child processes and won't change. Other `XCLAUDE_*` environment variables (`XCLAUDE_DENIAL_LOG`, `XCLAUDE_RELOAD_SENTINEL`) are internal and may change without notice.

## Reference

### SBPL parameters

`xclaude` passes these to `sandbox-exec` via `-D KEY=value`. Use `(param "NAME")` in SBPL — never hardcode paths.

| Parameter | Resolves to |
|---|---|
| `HOME` | `/Users/<you>` |
| `PROJECT_DIR` | Absolute path of the project (resolved with `readlink -f`) |
| `TMPDIR` | `/private/var/folders/<...>/T/` |
| `CACHE_DIR` | `/private/var/folders/<...>/C/` (sibling of TMPDIR — Spotlight/mds, keychain) |
| `VOLATILE_DIR` | `/private/var/folders/<...>/X/` (sibling of TMPDIR — code-signing clones, Metal shader cache) |
| `XCLAUDE_DIR` | Absolute path of the xclaude installation (used to allow the bundled plugin) |

### Environment variables

| Variable | Value | Stability |
|---|---|---|
| `XCLAUDE_ACTIVE` | `1` | **Stable** — public API for sandbox detection |
| `XCLAUDE_DENIAL_LOG` | Path to streaming denial log | Internal — do not rely on |
| `XCLAUDE_RELOAD_SENTINEL` | Path to reload sentinel file | Internal — do not rely on |

### Files

| File | Purpose |
|---|---|
| `xclaude` | Executable entry point — sources library, runs sandboxed Claude (reload loop) |
| `xcodex` | Executable entry point — sources library, runs sandboxed Codex CLI |
| `xsandbox.lib.zsh` | Shared DSL parser, validator, SBPL generator, assembler, trust gate |
| `xclaude.lib.zsh` | Claude-specific wrapper over the shared library |
| `xcodex.lib.zsh` | Codex-specific wrapper over the shared library |
| `base-common.sb` | Shared SBPL base (`deny default` + common rules) |
| `base.sb` | Claude-specific SBPL fragment layered on top of `base-common.sb` |
| `base-codex.sb` | Codex-specific SBPL fragment layered on top of `base-common.sb` |
| `toolchains/<name>.sb` | Bundled toolchain SBPL fragments |
| `toolchains/<name>.test.zsh` | Sandbox tests for each toolchain |
| `toolchains/test_helpers.zsh` | Shared test helpers (`tc_setup`, `tc_sandboxed`, ...) |
| `.claude-plugin/plugin.json` | Plugin manifest (loaded via `--plugin-dir`) |
| `plugin/hooks/hooks.json` | Hook registration (`PostToolUseFailure`) |
| `plugin/hooks/sandbox-denial-hook.sh` | Denial detection + context injection |
| `plugin/skills/debug-sandbox/SKILL.md` | `/debug-sandbox` configuration assistant |
| `plugin/skills/reload-sandbox/SKILL.md` | `/reload-sandbox` hot reload trigger |
| `test_xclaude.bash` | DSL pipeline unit tests (any platform, bash 4+) |
| `test_sandbox.zsh` | Sandbox integration test runner (macOS only) |
| [`CLAUDE.md`](CLAUDE.md) | Development guide — architecture, adding toolchains, base profile changes |
| [`DEBUGGING.md`](DEBUGGING.md) | Diagnosing sandbox issues, SBPL gotchas, denial categories |

## Testing

**DSL pipeline tests** (any platform, bash 4+):

```bash
bash test_xclaude.bash
```

Tests parser, validator, generator, assembler, and trust gate — no macOS or sandbox required.

**Sandbox integration tests** (macOS only):

```bash
# All tests (base + every discovered toolchain)
zsh test_sandbox.zsh

# Base profile only (no toolchains)
zsh test_sandbox.zsh --toolchain none

# Specific toolchain(s)
zsh test_sandbox.zsh --toolchain node
zsh test_sandbox.zsh --toolchain node,uv

# With a custom project config
zsh test_sandbox.zsh --with-config path/to/.xclaude
```

Each tested toolchain runs in its own parallel CI job with the tool installed at its canonical path. Tests verify:

- Read/write/exec access to declared paths
- Real tool operations (`npm install`, `cargo build`, `uv pip install`, etc.) — not just `--version`
- Isolation (sensitive paths like `~/.ssh` remain blocked)
- Write protection (`.xclaude`, `.env*`, `.git/hooks`)
- Escape vectors (symlinks, path traversal, child processes, fd redirects)

When a test fails unexpectedly, stderr and the recent sandbox denial log are displayed automatically.

## Known limitations

The sandbox enforces filesystem isolation only. These are accepted trade-offs and known gaps in the base profile.

### No network isolation

All network access is allowed (`(allow network*)`). The sandboxed process can make arbitrary HTTP requests, which means data exfiltration of anything it *can* read (project files, history, etc.) is possible via `curl` or any network client. SBPL may support filtering by host/IP/port — this hasn't been explored yet.

### Clipboard readable

`pbpaste` (in `/usr/bin`) can read the system clipboard. If you've copied a password or secret, it's accessible inside the sandbox. There is no SBPL operation to block this — clipboard access goes through Mach IPC, which must be globally allowed for Claude Code to function.

### Keychain metadata exposed

`security dump-keychain` reveals service names and account names for all keychain entries (e.g. "Chrome Safe Storage", "Arc", "1Password"). Actual password extraction triggers a macOS authorization UI prompt, so secrets are protected by a second layer. Removing `~/Library/Keychains` from the read allowlist would fix this but break OAuth login.

### File metadata globally visible

`file-read-metadata` is globally allowed (required for path resolution). This means `stat` and `test -e` work on any path — file existence, size, timestamps, and permissions are visible even for denied files. File **contents** are still blocked.

### JIT / dynamic code generation allowed

`dynamic-code-generation` is permitted because Bun, V8, and WASM runtimes need it. This weakens in-process exploit hardening (an attacker can inject shellcode instead of needing ROP/JOP), but in our threat model — an AI agent that can already exec bash, node, and python — the marginal risk is low. JIT code is still subject to the syscall sandbox.

## Compatibility

- macOS 14+ (Apple Silicon and Intel)
- Claude Code 2.1.x+
- Works alongside the cmux wrapper (`tool cmux`)
- `sandbox-exec` is officially deprecated by Apple but remains functional and is used by Chromium with the same approach
