#!/usr/bin/env bash
# xclaude test harness
# Tests the DSL parser, validator, and SBPL generator.
# No macOS sandbox required — runs anywhere with bash 4+.
#
# Usage: bash test_xclaude.bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Replicate the xclaude functions in bash ───────────────────
# The real xclaude.zsh uses zsh syntax. For testing, we re-source
# a bash-compatible shim of the core functions (parser, validator,
# generator). The SBPL output is identical regardless of shell.
__xclaude_dir="$SCRIPT_DIR"

__xclaude_parse() {
  local file="$1" line verb arg lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    # Strip inline comments (but not inside quotes — not needed for this DSL)
    line="${line%%#*}"
    # Trim whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue

    verb="${line%% *}"
    arg="${line#* }"
    [[ "$arg" = "$verb" ]] && arg=""

    case "$verb" in
      tool)
        [[ -z "$arg" ]] && { echo "xclaude: ${file}:${lineno}: 'tool' requires a name" >&2; return 1; }
        echo "tool ${arg}"
        ;;
      allow-read|allow-write|allow-exec)
        [[ -z "$arg" ]] && { echo "xclaude: ${file}:${lineno}: '${verb}' requires a path" >&2; return 1; }
        echo "${verb} ${arg}"
        ;;
      *)
        echo "xclaude: ${file}:${lineno}: unknown directive '${verb}'" >&2
        return 1
        ;;
    esac
  done < "$file"
}

__xclaude_validate() {
  local line verb arg toolchains_dir="${__xclaude_dir}/toolchains"
  while IFS= read -r line; do
    verb="${line%% *}"
    arg="${line#* }"

    case "$verb" in
      tool)
        if [[ ! -f "${toolchains_dir}/${arg}.sb" ]]; then
          echo "xclaude: unknown toolchain '${arg}'" >&2
          echo "xclaude: available: $(ls "${toolchains_dir}" | sed 's/\.sb$//' | tr '\n' ' ')" >&2
          return 1
        fi
        echo "$line"
        ;;
      allow-read|allow-write|allow-exec)
        # Validate path prefix using string prefix checks
        local prefix2="${arg:0:2}"
        if [[ "$arg" = "~" ]]; then
          echo "xclaude: bare '~' is too broad — use ~/specific/path" >&2
          return 1
        elif [[ "$prefix2" != "~/" && "$prefix2" != "./" && "${arg:0:1}" != "/" ]]; then
          echo "xclaude: invalid path '${arg}' — must start with ~/, ./, or /" >&2
          return 1
        fi
        # Block system paths already in base profile
        case "$arg" in
          /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
            echo "xclaude: system path '${arg}' is already allowed by base profile" >&2
            return 1
            ;;
        esac
        local basename="${arg##*/}"
        if [[ "$basename" = ".xclaude" ]]; then
          echo "xclaude: cannot target '.xclaude' — sandbox config is protected" >&2
          return 1
        fi
        echo "$line"
        ;;
    esac
  done
}

__xclaude_path_to_sbpl() {
  local p="$1"
  local prefix2="${p:0:2}"
  if [[ "$prefix2" = "~/" ]]; then
    local rest="${p:2}"
    echo "(string-append (param \"HOME\") \"/${rest}\")"
  elif [[ "$prefix2" = "./" ]]; then
    local rest="${p:2}"
    echo "(string-append (param \"PROJECT_DIR\") \"/${rest}\")"
  elif [[ "${p:0:1}" = "/" ]]; then
    echo "\"${p}\""
  fi
}

__xclaude_generate() {
  local line verb arg sbpl_path toolchains_dir="${__xclaude_dir}/toolchains"
  while IFS= read -r line; do
    verb="${line%% *}"
    arg="${line#* }"

    case "$verb" in
      tool)
        echo ""
        echo ";; ── toolchain: ${arg} ──"
        cat "${toolchains_dir}/${arg}.sb"
        ;;
      allow-read|allow-write|allow-exec)
        sbpl_path="$(__xclaude_path_to_sbpl "$arg")"
        echo ""
        echo ";; ── ${verb}: ${arg} ──"
        case "$verb" in
          allow-read)
            echo "(allow file-read-data (subpath ${sbpl_path}))"
            ;;
          allow-write)
            echo "(allow file-read-data (subpath ${sbpl_path}))"
            echo "(allow file-write* (subpath ${sbpl_path}))"
            ;;
          allow-exec)
            echo "(allow file-read-data (subpath ${sbpl_path}))"
            echo "(allow process-exec (subpath ${sbpl_path}))"
            ;;
        esac
        ;;
    esac
  done
}

__xclaude_assemble() {
  local project_dir="$1"
  local base_profile="${__xclaude_dir}/base.sb"
  local user_config="${HOME}/.config/xclaude/config"
  local project_config="${project_dir}/.xclaude"
  local assembled generated

  assembled="$(cat "$base_profile")"

  if [[ -f "$user_config" ]]; then
    generated="$(__xclaude_parse "$user_config" | __xclaude_validate | __xclaude_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; User config: ~/.config/xclaude/config'
      assembled+=$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  if [[ -f "$project_config" ]]; then
    generated="$(__xclaude_parse "$project_config" | __xclaude_validate | __xclaude_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; Project config: .xclaude'
      assembled+=$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  echo "$assembled"
}

# ── Test framework ────────────────────────────────────────────
__test_pass=0
__test_fail=0
__test_name=""

t() { __test_name="$1"; }

assert_eq() {
  local expected="$1" actual="$2"
  if [[ "$expected" = "$actual" ]]; then
    __test_pass=$((__test_pass + 1))
  else
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name}" >&2
    echo "  expected: $(echo "$expected" | head -3)" >&2
    echo "  actual:   $(echo "$actual" | head -3)" >&2
  fi
}

assert_contains() {
  local needle="$1" haystack="$2"
  if [[ "$haystack" = *"$needle"* ]]; then
    __test_pass=$((__test_pass + 1))
  else
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name}" >&2
    echo "  expected to contain: ${needle}" >&2
    echo "  actual: $(echo "$haystack" | head -3)" >&2
  fi
}

assert_not_contains() {
  local needle="$1" haystack="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    __test_pass=$((__test_pass + 1))
  else
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name}" >&2
    echo "  expected NOT to contain: ${needle}" >&2
  fi
}

assert_fails() {
  if eval "$@" >/dev/null 2>&1; then
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name}" >&2
    echo "  expected command to fail" >&2
  else
    __test_pass=$((__test_pass + 1))
  fi
}

assert_succeeds() {
  if eval "$@" >/dev/null 2>&1; then
    __test_pass=$((__test_pass + 1))
  else
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name}" >&2
    echo "  expected command to succeed" >&2
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap "rm -rf '${TMPDIR_TEST}'" EXIT

fixture() {
  local name="$1" content="$2"
  local path="${TMPDIR_TEST}/${name}"
  echo "$content" > "$path"
  echo "$path"
}

# ── Parser tests ──────────────────────────────────────────────
echo "=== Parser ==="

t "parses tool directive"
f="$(fixture p1 "tool node")"
assert_eq "tool node" "$(__xclaude_parse "$f")"

t "parses allow-read directive"
f="$(fixture p2 "allow-read ~/.config/foo")"
assert_eq "allow-read ~/.config/foo" "$(__xclaude_parse "$f")"

t "parses allow-write directive"
f="$(fixture p3 "allow-write ./local/.share")"
assert_eq "allow-write ./local/.share" "$(__xclaude_parse "$f")"

t "parses allow-exec directive"
f="$(fixture p4 "allow-exec ~/.local/bin/custom")"
assert_eq "allow-exec ~/.local/bin/custom" "$(__xclaude_parse "$f")"

t "strips comments"
f="$(fixture p5 $'# this is a comment\ntool node  # inline comment')"
assert_eq "tool node" "$(__xclaude_parse "$f")"

t "skips blank lines"
f="$(fixture p6 $'\ntool node\n\nallow-read ~/.config/foo\n')"
out="$(__xclaude_parse "$f")"
assert_contains "tool node" "$out"
assert_contains "allow-read ~/.config/foo" "$out"

t "multi-directive file"
f="$(fixture p7 $'tool node\ntool uv\nallow-read ~/.config/foo\nallow-write ./local/.share\nallow-exec ~/.local/bin/custom')"
out="$(__xclaude_parse "$f")"
count="$(echo "$out" | wc -l | tr -d ' ')"
assert_eq "5" "$count"

t "rejects unknown directive"
f="$(fixture p8 "deny-read ~/secrets")"
assert_fails __xclaude_parse "$f"

t "rejects tool without name"
f="$(fixture p9 "tool")"
assert_fails __xclaude_parse "$f"

t "rejects allow-read without path"
f="$(fixture p10 "allow-read")"
assert_fails __xclaude_parse "$f"

# ── Validator tests ───────────────────────────────────────────
echo "=== Validator ==="

t "accepts known toolchain"
assert_succeeds "echo 'tool node' | __xclaude_validate"

t "rejects unknown toolchain"
assert_fails "echo 'tool nonexistent' | __xclaude_validate"

t "accepts home-relative path"
assert_succeeds "echo 'allow-read ~/.config/foo' | __xclaude_validate"

t "accepts project-relative path"
assert_succeeds "echo 'allow-write ./local/.share' | __xclaude_validate"

t "accepts absolute path"
assert_succeeds "echo 'allow-read /opt/custom' | __xclaude_validate"

t "rejects bare tilde"
assert_fails "echo 'allow-read ~' | __xclaude_validate"

t "rejects relative path without ./"
assert_fails "echo 'allow-read local/.share' | __xclaude_validate"

t "rejects /System paths"
assert_fails "echo 'allow-read /System/Library' | __xclaude_validate"

t "rejects /usr paths"
assert_fails "echo 'allow-read /usr/local/lib' | __xclaude_validate"

t "rejects /Library paths"
assert_fails "echo 'allow-read /Library/Frameworks' | __xclaude_validate"

t "rejects /bin paths"
assert_fails "echo 'allow-exec /bin/sh' | __xclaude_validate"

t "rejects /opt/homebrew paths"
assert_fails "echo 'allow-read /opt/homebrew/lib' | __xclaude_validate"

t "rejects allow-write targeting .xclaude"
assert_fails "echo 'allow-write ./.xclaude' | __xclaude_validate"

t "rejects allow-read targeting .xclaude"
assert_fails "echo 'allow-read ./.xclaude' | __xclaude_validate"

t "rejects allow-exec targeting .xclaude"
assert_fails "echo 'allow-exec ./.xclaude' | __xclaude_validate"

t "rejects absolute path targeting .xclaude"
assert_fails "echo 'allow-write /some/project/.xclaude' | __xclaude_validate"

t "rejects home path targeting .xclaude"
assert_fails "echo 'allow-write ~/.xclaude' | __xclaude_validate"

t "allows paths containing xclaude as substring"
assert_succeeds "echo 'allow-read ~/.xclaude-backup' | __xclaude_validate"

t "passes through valid lines unchanged"
input="allow-read ~/.config/foo"
out="$(echo "$input" | __xclaude_validate)"
assert_eq "$input" "$out"

# ── .xclaude write-protect in base.sb ─────────────────────────
echo "=== Write protection ==="

t "base.sb denies writes to .xclaude using literal"
out="$(cat "${__xclaude_dir}/base.sb")"
assert_contains 'deny file-write' "$out"
assert_contains '.xclaude' "$out"

t "deny rule appears after allow for PROJECT_DIR"
base="$(cat "${__xclaude_dir}/base.sb")"
deny_line="$(echo "$base" | grep -n 'deny file-write' | head -1 | cut -d: -f1)"
allow_line="$(echo "$base" | grep -n 'allow file-write' | head -1 | cut -d: -f1)"
if [[ -n "$deny_line" && -n "$allow_line" && "$deny_line" -gt "$allow_line" ]]; then
  __test_pass=$((__test_pass + 1))
else
  __test_fail=$((__test_fail + 1))
  echo "FAIL: ${__test_name}" >&2
  echo "  deny on line ${deny_line:-?}, allow on line ${allow_line:-?} — deny must come AFTER allow" >&2
fi

# ── Path-to-SBPL tests ───────────────────────────────────────
echo "=== Path-to-SBPL ==="

t "home-relative path"
out="$(__xclaude_path_to_sbpl "~/.config/foo")"
assert_eq '(string-append (param "HOME") "/.config/foo")' "$out"

t "project-relative path"
out="$(__xclaude_path_to_sbpl "./local/.share")"
assert_eq '(string-append (param "PROJECT_DIR") "/local/.share")' "$out"

t "absolute path"
out="$(__xclaude_path_to_sbpl "/opt/custom/lib")"
assert_eq '"/opt/custom/lib"' "$out"

# ── Generator tests ───────────────────────────────────────────
echo "=== Generator ==="

t "tool directive emits toolchain contents"
out="$(echo 'tool node' | __xclaude_generate)"
assert_contains 'toolchain: node' "$out"
assert_contains '/.nvm' "$out"
assert_contains '/.npm' "$out"

t "allow-read emits file-read-data only"
out="$(echo 'allow-read ~/.config/foo' | __xclaude_generate)"
assert_contains 'file-read-data' "$out"
assert_not_contains 'file-write' "$out"
assert_not_contains 'process-exec' "$out"

t "allow-write emits read + write"
out="$(echo 'allow-write ./local/.share' | __xclaude_generate)"
assert_contains 'file-read-data' "$out"
assert_contains 'file-write*' "$out"
assert_not_contains 'process-exec' "$out"

t "allow-exec emits read + exec"
out="$(echo 'allow-exec ~/.local/bin/custom' | __xclaude_generate)"
assert_contains 'file-read-data' "$out"
assert_contains 'process-exec' "$out"
assert_not_contains 'file-write' "$out"

# ── Assembly tests ────────────────────────────────────────────
echo "=== Assembly ==="

t "assembly without config produces base only"
empty_dir="$(mktemp -d)"
out="$(__xclaude_assemble "$empty_dir")"
assert_contains '(deny default)' "$out"
assert_contains '(param "PROJECT_DIR")' "$out"
assert_not_contains 'toolchain:' "$out"
rmdir "$empty_dir"

t "assembly with project config includes toolchain"
proj_dir="$(mktemp -d)"
echo "tool node" > "${proj_dir}/.xclaude"
out="$(__xclaude_assemble "$proj_dir")"
assert_contains '(deny default)' "$out"
assert_contains 'toolchain: node' "$out"
assert_contains '/.nvm' "$out"
rm -rf "$proj_dir"

t "assembly with custom paths"
proj_dir="$(mktemp -d)"
echo "allow-write ./local/.share" > "${proj_dir}/.xclaude"
out="$(__xclaude_assemble "$proj_dir")"
assert_contains 'file-write*' "$out"
assert_contains '/local/.share' "$out"
rm -rf "$proj_dir"

t "assembly with multiple tools and paths"
proj_dir="$(mktemp -d)"
cat > "${proj_dir}/.xclaude" <<'EOF'
tool node
tool uv
allow-read ~/.config/special
allow-write ./data
EOF
out="$(__xclaude_assemble "$proj_dir")"
assert_contains 'toolchain: node' "$out"
assert_contains 'toolchain: uv' "$out"
assert_contains '/.config/special' "$out"
assert_contains '/data' "$out"
rm -rf "$proj_dir"

t "assembly fails on invalid config"
proj_dir="$(mktemp -d)"
echo "deny-read ~/secrets" > "${proj_dir}/.xclaude"
assert_fails "__xclaude_assemble '$proj_dir'"
rm -rf "$proj_dir"

t "assembly with user config"
proj_dir="$(mktemp -d)"
user_config_dir="${TMPDIR_TEST}/xclaude_home/.config/xclaude"
mkdir -p "$user_config_dir"
echo "allow-read ~/.config/personal-tool" > "${user_config_dir}/config"
HOME="${TMPDIR_TEST}/xclaude_home" out="$(__xclaude_assemble "$proj_dir")"
assert_contains 'User config' "$out"
assert_contains '/.config/personal-tool' "$out"
rm -rf "$proj_dir"

# ── SBPL well-formedness ─────────────────────────────────────
echo "=== SBPL well-formedness ==="

t "generated SBPL has balanced parens"
proj_dir="$(mktemp -d)"
cat > "${proj_dir}/.xclaude" <<'EOF'
tool node
tool rust
allow-read ~/.config/foo
allow-write ./build
allow-exec ~/.local/bin/bar
EOF
out="$(__xclaude_assemble "$proj_dir")"
opens="${out//[^(]/}"
closes="${out//[^)]/}"
assert_eq "${#opens}" "${#closes}"
rm -rf "$proj_dir"

t "all toolchain files produce valid SBPL fragments"
all_ok=true
for tc_file in "${__xclaude_dir}"/toolchains/*.sb; do
  tc_name="$(basename "$tc_file" .sb)"
  out="$(echo "tool ${tc_name}" | __xclaude_generate)"
  opens="${out//[^(]/}"
  closes="${out//[^)]/}"
  if [[ "${#opens}" != "${#closes}" ]]; then
    all_ok=false
    __test_fail=$((__test_fail + 1))
    echo "FAIL: toolchain ${tc_name} has unbalanced parens" >&2
  fi
done
if $all_ok; then
  __test_pass=$((__test_pass + 1))
fi

# ── Edge cases ────────────────────────────────────────────────
echo "=== Edge cases ==="

t "path with spaces in directory name"
out="$(__xclaude_path_to_sbpl "~/Library/Application Support/thing")"
assert_contains "Application Support/thing" "$out"

t "deeply nested project-relative path"
out="$(__xclaude_path_to_sbpl "./a/b/c/d/e")"
assert_contains "/a/b/c/d/e" "$out"

t "config with only comments and blanks"
f="$(fixture edge1 $'# just a comment\n\n# another comment\n')"
out="$(__xclaude_parse "$f")"
assert_eq "" "$out"

# ── Results ───────────────────────────────────────────────────
echo ""
echo "=== Results ==="
total=$((__test_pass + __test_fail))
echo "${__test_pass}/${total} passed"
if [[ $__test_fail -gt 0 ]]; then
  echo "${__test_fail} FAILED"
  exit 1
else
  echo "All tests passed."
  exit 0
fi
