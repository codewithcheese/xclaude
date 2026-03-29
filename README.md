# claude-strict

macOS Seatbelt sandbox for Claude Code. Wraps the `claude` binary in `sandbox-exec` with a strict SBPL profile that restricts filesystem access to an explicit allowlist.

## Why

Claude Code's built-in sandbox (`sandbox.enabled` in settings) has [known issues](https://github.com/anthropics/claude-code/issues/31473) on macOS — `denyRead` is ineffective, `allowRead` doesn't exist in the schema, and the generated SBPL profiles can crash silently. This project replaces it with a hand-tuned Seatbelt profile that actually works.

## What it does

- **Reads**: `file-read-data` allowlist only. System runtime paths, Claude config, project directory, and specific tool configs. Everything else in `$HOME` is blocked.
- **Writes**: project directory, Claude state files, tmp directories. Nothing else.
- **Non-filesystem**: network, IPC, Mach ports are open (the goal is filesystem isolation).
- **Exec**: system binaries, Homebrew, Claude binary, NVM, project scripts.

### Blocked by default

`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.docker`, `~/Desktop`, `~/Downloads`, `~/Documents` (except the project), `~/Library` (except Keychains for auth), `~/.zsh_history`, and anything else not explicitly listed.

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

The wrapper resolves paths, passes them as SBPL parameters, and launches Claude under `sandbox-exec`. Claude's internal permissions are bypassed (`--dangerously-skip-permissions`) since the OS sandbox enforces the real boundaries.

## Customization

Edit `xclaude.sb` to add paths for your tools. Common additions:

```scheme
;; Example: allow reading a language runtime
(allow file-read-data
  (subpath (string-append (param "HOME") "/.cargo")))

;; Example: allow writing to a build cache
(allow file-write*
  (subpath (string-append (param "HOME") "/.cache/turbo")))
```

### Symlink-aware

Seatbelt resolves symlinks before checking rules. If `~/.zshrc` symlinks to `~/Documents/GitHub/.../macos-setup/.zshrc`, you must allow the **target** path, not the symlink.

### SBPL parameter reference

| Parameter | Set by | Example |
|---|---|---|
| `HOME` | `xclaude.zsh` | `/Users/tom` |
| `PROJECT_DIR` | `xclaude.zsh` (from `$PWD`) | `/Users/tom/myproject` |
| `TMPDIR` | `xclaude.zsh` (resolved) | `/private/var/folders/.../T` |
| `CACHE_DIR` | `xclaude.zsh` (derived from TMPDIR) | `/private/var/folders/.../C` |

## Files

| File | Purpose |
|---|---|
| `xclaude.zsh` | Shell wrapper function |
| `xclaude.sb` | Seatbelt/SBPL sandbox profile |
| `DEBUGGING.md` | Guide for diagnosing sandbox issues |

## Compatibility

- macOS 14+ (Apple Silicon and Intel)
- Claude Code 2.1.x
- Works with cmux wrapper
- `sandbox-exec` is deprecated by Apple but still functional (Chromium uses the same approach)
