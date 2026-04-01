# Development Guide

## Architecture

```
xclaude.zsh              # Shell wrapper: DSL parser → validator → SBPL generator → assembler
base.sb                  # Core SBPL profile (deny default + Claude Code needs)
toolchains/
  <name>.sb              # SBPL fragment for a toolchain
  <name>.test.zsh        # Sandbox tests for that toolchain
  test_helpers.zsh       # Shared test helpers (tc_setup, tc_sandboxed, etc.)
test_xclaude.bash        # DSL pipeline unit tests (bash, any platform)
test_sandbox.zsh         # Sandbox integration tests (zsh, macOS only)
```

The DSL (`.xclaude` files) is the safety boundary between user/project config and the kernel sandbox. Raw SBPL is only in `base.sb` and `toolchains/*.sb` — both are bundled and vetted.

## SBPL rules to know

- `(deny default)` is in base.sb. Everything else is `(allow ...)`.
- **Last-match-wins**: a `(deny)` placed AFTER an `(allow)` overrides it. This is how we protect files inside writable directories.
- Use `(literal)` for exact file paths, `(subpath)` for directories.
- `(path)` allows CANNOT override `(subpath)` denies. But `(literal)` denies CAN override `(subpath)` allows (when the deny comes after).
- Seatbelt resolves symlinks before matching. All paths passed to `sandbox-exec` must be resolved with `readlink -f`.
- Use `(param "HOME")`, `(param "PROJECT_DIR")`, etc. — never hardcode user paths.

## Adding a toolchain

Create two files:

### 1. `toolchains/<name>.sb`

SBPL fragment granting read, write, and exec access for the tool. Use `(param "HOME")` for home-relative paths.

**Every rule MUST have a comment explaining its intent** — why this path is needed and what operation requires it. The `.sb` file should start with a header comment describing what the toolchain provides and how the tool's filesystem layout works.

```scheme
;; Example toolchain
;;
;; tool installs to ~/.tool/bin/ and caches data at ~/.tool/cache/.
;; Config at ~/.tool/config (read-only).

;; Exec — tool binaries
(allow process-exec
  (subpath (string-append (param "HOME") "/.tool/bin")))

;; Read — binaries, cache, and config
(allow file-read-data
  (subpath (string-append (param "HOME") "/.tool")))

(allow file-write*
  (subpath (string-append (param "HOME") "/.tool/cache")))
```

Principle of least privilege: only allow writes to cache/state directories, not the entire tool directory. Keep exec to `bin/` directories.

### 2. `toolchains/<name>.test.zsh`

Sandbox tests using the shared helpers. Follow this pattern:

```zsh
# <Tool name> toolchain sandbox tests
tc_setup <name>

# Create fixture directories and files
tc_fixture_dir "${HOME}/.tool/bin"
tc_fixture_dir "${HOME}/.tool/cache"
tc_fixture_file "${HOME}/.tool/config"

# Test read access
t "<name>: read ~/.tool"
expect_success "allowed" tc_sandboxed cat "${HOME}/.tool/config"

# Test write access
t "<name>: write ~/.tool/cache"
expect_success "allowed" tc_sandboxed touch "${HOME}/.tool/cache/test-write"
rm -f "${HOME}/.tool/cache/test-write"

# Test write is blocked where it should be
t "<name>: ~/.tool/bin not writable"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.tool/bin/test-write"

# Test usability — use full binary paths, not bare names
# (sandbox-exec doesn't search PATH)
__tool_bin="${HOME}/.tool/bin/tool"
[[ -x "$__tool_bin" ]] || __tool_bin="$(command -v tool 2>/dev/null || echo "")"

t "<name>: tool --version"
expect_success "runs" tc_sandboxed "$__tool_bin" --version

# Test real operations, not just --version
t "<name>: tool init project"
expect_success "init" tc_sandboxed "$__tool_bin" init "${PROJECT_DIR}/test-proj"

# Test isolation
t "<name>: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
```

The test runner auto-discovers `toolchains/*.test.zsh` — no registration needed.

**Important CI practices:**
- Use full binary paths (`"$__tool_bin"`) — `sandbox-exec` doesn't search PATH
- `tc_sandboxed` automatically `cd`s to PROJECT_DIR — tools need a readable CWD
- For `/bin/sh -c` wrappers, include `cd '${PROJECT_DIR}' &&` at the start
- Test real operations (install, build, run) not just `--version`
- When a test fails, stderr and sandbox denial logs are shown automatically

### 3. Update README.md

Add the toolchain to the "Available toolchains" table.

### 4. Add a CI job

Each toolchain gets its own parallel CI job in `.github/workflows/test.yml`. The job installs the tool at its canonical path and runs `zsh test_sandbox.zsh --toolchain <name>`.

## Modifying the base policy (base.sb)

### Adding read access

```scheme
(allow file-read-data
  (subpath (string-append (param "HOME") "/.new-config")))
```

### Adding write access

```scheme
(allow file-write*
  (subpath (string-append (param "HOME") "/.new-state")))
```

### Protecting a file inside a writable directory

Use deny-after-allow (last-match-wins). The deny MUST appear after the `(allow file-write* (subpath (param "PROJECT_DIR")))` block:

```scheme
(deny file-write*
  (literal (string-append (param "PROJECT_DIR") "/.secret-file")))
```

Use `(literal)` for files, `(subpath)` for directories. Add a corresponding sandbox test in `test_sandbox.zsh` under "Blocked writes" and a structural check in `test_xclaude.bash` under "Write protection".

## Running tests

```bash
# DSL pipeline (any platform, fast)
bash test_xclaude.bash

# Sandbox integration — all tests (macOS only)
zsh test_sandbox.zsh

# Base profile only (no toolchains)
zsh test_sandbox.zsh --toolchain none

# Specific toolchain(s)
zsh test_sandbox.zsh --toolchain node
zsh test_sandbox.zsh --toolchain node,uv

# With a custom project config
zsh test_sandbox.zsh --with-config path/to/.xclaude
```

### Test structure

- `test_xclaude.bash` — tests the DSL pipeline in pure bash. Duplicates the parser/validator/generator functions from `xclaude.zsh` since they use zsh syntax. If you change the DSL logic in `xclaude.zsh`, update the corresponding functions in `test_xclaude.bash` too.
- `test_sandbox.zsh` — tests real `sandbox-exec` enforcement. Runs base profile tests (reads, writes, exec, escape vectors), then auto-discovers and runs `toolchains/*.test.zsh`.
- `toolchains/*.test.zsh` — each file sources `test_helpers.zsh` and tests one toolchain. Creates fixture dirs, verifies access, checks tool usability if installed.

### Test helpers reference

| Helper | Purpose |
|---|---|
| `tc_setup <name>` | Assemble a profile with this toolchain enabled |
| `tc_sandboxed <cmd...>` | Run a command inside the toolchain's sandbox |
| `tc_fixture_dir <path>` | Create a directory (auto-cleaned) |
| `tc_fixture_file <path> [content]` | Create a file (auto-cleaned) |
| `tc_has_cmd <cmd>` | Check if a command exists on the host |
| `tc_cleanup` | Remove profile and fixtures (call at end of test) |
| `t <name>` | Set the current test name |
| `expect_success <desc> <cmd...>` | Assert command succeeds |
| `expect_fail <desc> <cmd...>` | Assert command fails (sandbox blocks it) |

## DSL safety rules

The validator in `xclaude.zsh` enforces:

- Only four verbs: `tool`, `allow-read`, `allow-write`, `allow-exec`
- Paths must start with `~/`, `./`, or `/`
- No bare `~` (too broad)
- System paths rejected (already in base profile)
- Paths targeting `.xclaude` as basename rejected (config is protected)
- Tool names must match a file in `toolchains/`

If you add a new validation rule, add it to both `xclaude.zsh` and the duplicate in `test_xclaude.bash`.
