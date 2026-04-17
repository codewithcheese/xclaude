#!/usr/bin/env bash
# xclaude test harness
# Tests the DSL parser, validator, and SBPL generator.
# No macOS sandbox required — runs anywhere with bash 4+.
#
# Usage: bash test_xclaude.bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Replicate the xclaude functions in bash ───────────────────
# The real xclaude.lib.zsh uses zsh syntax. For testing, we re-source
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
          echo "xclaude: available: $(ls "${toolchains_dir}"/*.sb 2>/dev/null | xargs -I{} basename {} .sb | tr '\n' ' ')" >&2
          return 1
        fi
        echo "$line"
        ;;
      allow-read|allow-write|allow-exec)
        # Validate path prefix using string prefix checks
        local prefix2="${arg:0:2}"
        if [[ "$arg" = "~" || "$arg" = "~/" ]]; then
          echo "xclaude: bare '~' or '~/' is too broad — use ~/specific/path" >&2
          return 1
        elif [[ "$arg" = "./" || "$arg" = "." ]]; then
          echo "xclaude: bare './' is too broad — use ./specific/path" >&2
          return 1
        elif [[ "$prefix2" != "~/" && "$prefix2" != "./" && "${arg:0:1}" != "/" ]]; then
          echo "xclaude: invalid path '${arg}' — must start with ~/, ./, or /" >&2
          return 1
        fi
        # System-path restrictions are verb-specific:
        #   read  — all system roots already covered by base
        #   write — system paths must never be writable from config
        #   exec  — only the exec-covered base subpaths are redundant
        case "$verb" in
          allow-read)
            case "$arg" in
              /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
                echo "xclaude: system path '${arg}' is already readable via base profile" >&2
                return 1
                ;;
            esac
            ;;
          allow-write)
            case "$arg" in
              /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
                echo "xclaude: system path '${arg}' cannot be made writable from project config" >&2
                return 1
                ;;
            esac
            ;;
          allow-exec)
            case "$arg" in
              /bin/*|/usr/bin/*|/opt/homebrew/*)
                echo "xclaude: exec path '${arg}' is already allowed by base profile" >&2
                return 1
                ;;
            esac
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
  local base_common="${__xclaude_dir}/base-common.sb"
  local base_profile="${__xclaude_dir}/base.sb"
  local user_config="${HOME}/.config/xclaude/config"
  local project_config="${project_dir}/.xclaude"
  local assembled generated

  assembled="$(cat "$base_common" "$base_profile")"

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

__xcodex_validate() {
  local line verb arg toolchains_dir="${__xclaude_dir}/toolchains"
  while IFS= read -r line; do
    verb="${line%% *}"
    arg="${line#* }"

    case "$verb" in
      tool)
        if [[ ! -f "${toolchains_dir}/${arg}.sb" ]]; then
          echo "xcodex: unknown toolchain '${arg}'" >&2
          echo "xcodex: available: $(ls "${toolchains_dir}"/*.sb 2>/dev/null | xargs -I{} basename {} .sb | tr '\n' ' ')" >&2
          return 1
        fi
        echo "$line"
        ;;
      allow-read|allow-write|allow-exec)
        local prefix2="${arg:0:2}"
        if [[ "$arg" = "~" || "$arg" = "~/" ]]; then
          echo "xcodex: bare '~' or '~/' is too broad — use ~/specific/path" >&2
          return 1
        elif [[ "$arg" = "./" || "$arg" = "." ]]; then
          echo "xcodex: bare './' is too broad — use ./specific/path" >&2
          return 1
        elif [[ "$prefix2" != "~/" && "$prefix2" != "./" && "${arg:0:1}" != "/" ]]; then
          echo "xcodex: invalid path '${arg}' — must start with ~/, ./, or /" >&2
          return 1
        fi
        case "$verb" in
          allow-read)
            case "$arg" in
              /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
                echo "xcodex: system path '${arg}' is already readable via base profile" >&2
                return 1
                ;;
            esac
            ;;
          allow-write)
            case "$arg" in
              /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
                echo "xcodex: system path '${arg}' cannot be made writable from project config" >&2
                return 1
                ;;
            esac
            ;;
          allow-exec)
            case "$arg" in
              /bin/*|/usr/bin/*|/opt/homebrew/*)
                echo "xcodex: exec path '${arg}' is already allowed by base profile" >&2
                return 1
                ;;
            esac
            ;;
        esac
        local basename="${arg##*/}"
        if [[ "$basename" = ".xcodex" ]]; then
          echo "xcodex: cannot target '.xcodex' — sandbox config is protected" >&2
          return 1
        fi
        echo "$line"
        ;;
    esac
  done
}

__xcodex_assemble() {
  local project_dir="$1"
  local base_common="${__xclaude_dir}/base-common.sb"
  local base_profile="${__xclaude_dir}/base-codex.sb"
  local user_config="${HOME}/.config/xcodex/config"
  local project_config="${project_dir}/.xcodex"
  local assembled generated

  assembled="$(cat "$base_common" "$base_profile")"

  if [[ -f "$user_config" ]]; then
    generated="$(__xclaude_parse "$user_config" | __xcodex_validate | __xclaude_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; User config: ~/.config/xcodex/config'
      assembled+=$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  if [[ -f "$project_config" ]]; then
    generated="$(__xclaude_parse "$project_config" | __xcodex_validate | __xclaude_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; Project config: .xcodex'
      assembled+=$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  echo "$assembled"
}

# ── Trust-gate color helpers (duplicate of xsandbox.lib.zsh) ─
__xsandbox_color_enabled() {
  case "${XSANDBOX_COLOR:-auto}" in
    always) return 0 ;;
    never)  return 1 ;;
    auto)
      [[ -n "${NO_COLOR:-}" ]] && return 1
      [[ -t 2 ]] && return 0
      return 1
      ;;
    *) return 1 ;;
  esac
}

__xsandbox_colorize_diff() {
  if ! __xsandbox_color_enabled; then
    cat
    return
  fi
  local R=$'\e[31m' G=$'\e[32m' C=$'\e[36m' Y=$'\e[33m' M=$'\e[35m' D=$'\e[2m' Z=$'\e[0m' B=$'\e[1m'
  awk -v r="$R" -v g="$G" -v c="$C" -v y="$Y" -v m="$M" -v d="$D" -v z="$Z" -v b="$B" '
    /^(--- |\+\+\+ )/ { print c b $0 z; next }
    /^@@/             { print c $0 z;   next }
    /^[-+](tool|allow-read|allow-write|allow-exec)[[:space:]]/ {
      polarity = substr($0, 1, 1)
      pc = (polarity == "+") ? g : r
      body = substr($0, 2)
      match(body, /[[:space:]]/)
      if (RSTART > 0) {
        verb = substr(body, 1, RSTART - 1)
        rest = substr(body, RSTART)
      } else {
        verb = body
        rest = ""
      }
      vc = ""
      if      (verb == "tool")        vc = c
      else if (verb == "allow-read")  vc = g
      else if (verb == "allow-write") vc = y
      else if (verb == "allow-exec")  vc = m
      printf "%s%s%s%s%s%s%s%s%s%s\n", pc, polarity, z, vc, b, verb, z, pc, rest, z
      next
    }
    /^-/              { print r $0 z;   next }
    /^\+/             { print g $0 z;   next }
                      { print d $0 z }
  '
}

__xsandbox_summarize_diff() {
  local old="$1" new="$2"
  local tool_a=0 read_a=0 write_a=0 exec_a=0
  local tool_r=0 read_r=0 write_r=0 exec_r=0
  local line
  while IFS= read -r line; do
    case "$line" in
      '+tool '*)        tool_a=$((tool_a + 1)) ;;
      '+allow-read '*)  read_a=$((read_a + 1)) ;;
      '+allow-write '*) write_a=$((write_a + 1)) ;;
      '+allow-exec '*)  exec_a=$((exec_a + 1)) ;;
      '-tool '*)        tool_r=$((tool_r + 1)) ;;
      '-allow-read '*)  read_r=$((read_r + 1)) ;;
      '-allow-write '*) write_r=$((write_r + 1)) ;;
      '-allow-exec '*)  exec_r=$((exec_r + 1)) ;;
    esac
  done < <(diff -u "$old" "$new" 2>/dev/null || true)

  if (( tool_a + read_a + write_a + exec_a + tool_r + read_r + write_r + exec_r == 0 )); then
    return 0
  fi

  local C="" G="" Y="" M="" R="" Z="" B=""
  if __xsandbox_color_enabled; then
    C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; M=$'\e[35m'; R=$'\e[31m'; Z=$'\e[0m'; B=$'\e[1m'
  fi
  local segs=()
  (( exec_a > 0 ))  && segs+=("${G}+${exec_a}${Z} ${M}${B}exec${Z}")
  (( write_a > 0 )) && segs+=("${G}+${write_a}${Z} ${Y}${B}write${Z}")
  (( tool_a > 0 ))  && segs+=("${G}+${tool_a}${Z} ${C}${B}tool${Z}")
  (( read_a > 0 ))  && segs+=("${G}+${read_a}${Z} ${G}${B}read${Z}")
  (( exec_r > 0 ))  && segs+=("${R}-${exec_r}${Z} ${M}${B}exec${Z}")
  (( write_r > 0 )) && segs+=("${R}-${write_r}${Z} ${Y}${B}write${Z}")
  (( tool_r > 0 ))  && segs+=("${R}-${tool_r}${Z} ${C}${B}tool${Z}")
  (( read_r > 0 ))  && segs+=("${R}-${read_r}${Z} ${G}${B}read${Z}")

  local out="" s first=1
  for s in "${segs[@]}"; do
    if (( first )); then out="$s"; first=0; else out+="  $s"; fi
  done
  printf '  %s\n' "$out"
}

__xsandbox_summarize_new() {
  local file="$1"
  local tool_n=0 read_n=0 write_n=0 exec_n=0
  local line stripped
  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="${line%%#*}"
    [[ -z "$stripped" ]] && continue
    case "$stripped" in
      'tool '*)        tool_n=$((tool_n + 1)) ;;
      'allow-read '*)  read_n=$((read_n + 1)) ;;
      'allow-write '*) write_n=$((write_n + 1)) ;;
      'allow-exec '*)  exec_n=$((exec_n + 1)) ;;
    esac
  done < "$file"

  if (( tool_n + read_n + write_n + exec_n == 0 )); then
    return 0
  fi

  local C="" G="" Y="" M="" Z="" B=""
  if __xsandbox_color_enabled; then
    C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; M=$'\e[35m'; Z=$'\e[0m'; B=$'\e[1m'
  fi
  local segs=()
  (( exec_n > 0 ))  && segs+=("${exec_n} ${M}${B}exec${Z}")
  (( write_n > 0 )) && segs+=("${write_n} ${Y}${B}write${Z}")
  (( tool_n > 0 ))  && segs+=("${tool_n} ${C}${B}tool${Z}")
  (( read_n > 0 )) && segs+=("${read_n} ${G}${B}read${Z}")

  local out="" s first=1
  for s in "${segs[@]}"; do
    if (( first )); then out="$s"; first=0; else out+="  $s"; fi
  done
  printf '  %s\n' "$out"
}

__xsandbox_colorize_new() {
  if ! __xsandbox_color_enabled; then
    cat
    return
  fi
  local C=$'\e[36m' G=$'\e[32m' Y=$'\e[33m' M=$'\e[35m' D=$'\e[2m' Z=$'\e[0m' B=$'\e[1m'
  awk -v c="$C" -v g="$G" -v y="$Y" -v m="$M" -v d="$D" -v z="$Z" -v b="$B" '
    /^[[:space:]]*#/                { print d $0 z; next }
    /^[[:space:]]*tool[[:space:]]/  { sub(/tool/,       c b "&" z); print; next }
    /^[[:space:]]*allow-read[[:space:]]/  { sub(/allow-read/,  g b "&" z); print; next }
    /^[[:space:]]*allow-write[[:space:]]/ { sub(/allow-write/, y b "&" z); print; next }
    /^[[:space:]]*allow-exec[[:space:]]/  { sub(/allow-exec/,  m b "&" z); print; next }
                                    { print }
  '
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

t "rejects ~/ (entire home)"
assert_fails "echo 'allow-write ~/' | __xclaude_validate"

t "rejects ./ (entire project)"
assert_fails "echo 'allow-write ./' | __xclaude_validate"

t "rejects relative path without ./"
assert_fails "echo 'allow-read local/.share' | __xclaude_validate"

t "rejects /System paths"
assert_fails "echo 'allow-read /System/Library' | __xclaude_validate"

t "rejects /usr paths"
assert_fails "echo 'allow-read /usr/local/lib' | __xclaude_validate"

t "rejects /Library paths"
assert_fails "echo 'allow-read /Library/Frameworks' | __xclaude_validate"

t "rejects allow-exec on /bin (base-covered)"
assert_fails "echo 'allow-exec /bin/sh' | __xclaude_validate"

t "rejects allow-exec on /usr/bin (base-covered)"
assert_fails "echo 'allow-exec /usr/bin/python3' | __xclaude_validate"

t "rejects allow-exec on /opt/homebrew (base-covered)"
assert_fails "echo 'allow-exec /opt/homebrew/bin/node' | __xclaude_validate"

t "rejects /opt/homebrew paths"
assert_fails "echo 'allow-read /opt/homebrew/lib' | __xclaude_validate"

# Paths the base profile can read but cannot exec — valid allow-exec targets
t "accepts allow-exec on /Library (not base-execed)"
assert_succeeds "echo 'allow-exec /Library/Java/JavaVirtualMachines/temurin-26.jdk/Contents/Home/bin/java' | __xclaude_validate"

t "accepts allow-exec on /usr/libexec (not base-execed)"
assert_succeeds "echo 'allow-exec /usr/libexec/java_home' | __xclaude_validate"

t "accepts allow-exec on /usr/local (not base-execed)"
assert_succeeds "echo 'allow-exec /usr/local/bin/terraform' | __xclaude_validate"

t "accepts allow-exec on /sbin (not base-execed)"
assert_succeeds "echo 'allow-exec /sbin/ping' | __xclaude_validate"

# Writes to system paths must always be refused, even where reads are already covered
t "rejects allow-write on /Library"
assert_fails "echo 'allow-write /Library/Foo' | __xclaude_validate"

t "rejects allow-write on /usr/local"
assert_fails "echo 'allow-write /usr/local/bin' | __xclaude_validate"

t "rejects allow-write on /opt/homebrew"
assert_fails "echo 'allow-write /opt/homebrew/var' | __xclaude_validate"

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

# ── Base profile write protection ─────────────────────────────
echo "=== Write protection ==="

t "assembled Claude base denies writes to .xclaude using literal"
out="$(cat "${__xclaude_dir}/base-common.sb" "${__xclaude_dir}/base.sb")"
assert_contains 'deny file-write' "$out"
assert_contains '.xclaude' "$out"

t "shared base denies writes to .env files"
out="$(cat "${__xclaude_dir}/base-common.sb")"
assert_contains '/.env"' "$out"
assert_contains '/.env.local"' "$out"
assert_contains '/.env.development"' "$out"
assert_contains '/.env.staging"' "$out"
assert_contains '/.env.test"' "$out"
assert_contains '/.env.production"' "$out"

t "shared base denies writes to .git/hooks"
assert_contains '.git/hooks' "$out"

t "deny rule appears after allow for PROJECT_DIR"
base="$(cat "${__xclaude_dir}/base-common.sb" "${__xclaude_dir}/base.sb")"
deny_line="$(echo "$base" | grep -n 'deny file-write' | head -1 | cut -d: -f1)"
allow_line="$(echo "$base" | grep -n 'allow file-write' | head -1 | cut -d: -f1)"
if [[ -n "$deny_line" && -n "$allow_line" && "$deny_line" -gt "$allow_line" ]]; then
  __test_pass=$((__test_pass + 1))
else
  __test_fail=$((__test_fail + 1))
  echo "FAIL: ${__test_name}" >&2
  echo "  deny on line ${deny_line:-?}, allow on line ${allow_line:-?} — deny must come AFTER allow" >&2
fi

t "base-codex.sb denies writes to .xcodex"
out="$(cat "${__xclaude_dir}/base-codex.sb")"
assert_contains 'deny file-write' "$out"
assert_contains '.xcodex' "$out"

t "base-codex.sb allows Codex state"
assert_contains '/.codex' "$out"
assert_contains '/.nvm' "$out"

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
out="$(HOME="$empty_dir" __xclaude_assemble "$empty_dir")"
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

t "xcodex assembly with project config includes toolchain"
proj_dir="$(mktemp -d)"
echo "tool node" > "${proj_dir}/.xcodex"
out="$(__xcodex_assemble "$proj_dir")"
assert_contains 'Project config: .xcodex' "$out"
assert_contains 'toolchain: node' "$out"
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

# ── Trust-gate color ──────────────────────────────────────────
echo "=== Trust gate color ==="

strip_ansi() {
  # POSIX-esque CSI stripper. Matches ESC [ <params> m.
  sed $'s/\x1b\\[[0-9;]*m//g'
}

# Sample unified diff input used across multiple tests
__sample_diff=$'--- trusted\n+++ current\n@@ -1,3 +1,4 @@\n tool node\n-allow-read ~/.config/old\n+allow-write ~/.config/new\n+allow-exec ~/.local/bin/x\n context-line\n'

t "XSANDBOX_COLOR=never: no ANSI in diff"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=never __xsandbox_colorize_diff)
assert_eq "$__sample_diff" "${out}"$'\n'
assert_not_contains $'\e[' "$out"

t "NO_COLOR=1 (auto mode): no ANSI in diff"
out=$(printf '%s' "$__sample_diff" | NO_COLOR=1 XSANDBOX_COLOR=auto __xsandbox_colorize_diff)
assert_not_contains $'\e[' "$out"

t "XSANDBOX_COLOR=always: removed line has red polarity + green bold verb (read)"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[31m-\e[0m\e[32m\e[1mallow-read\e[0m\e[31m ~/.config/old\e[0m' "$out"

t "XSANDBOX_COLOR=always: added allow-write has green polarity + yellow bold verb"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[32m+\e[0m\e[33m\e[1mallow-write\e[0m\e[32m ~/.config/new\e[0m' "$out"

t "XSANDBOX_COLOR=always: added allow-exec has green polarity + magenta bold verb"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[32m+\e[0m\e[35m\e[1mallow-exec\e[0m\e[32m ~/.local/bin/x\e[0m' "$out"

t "XSANDBOX_COLOR=always: context tool line stays dim (no verb overlay)"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[2m tool node\e[0m' "$out"

t "XSANDBOX_COLOR=always: added tool has cyan bold verb overlay"
diff_with_tool=$'--- trusted\n+++ current\n@@ -1,1 +1,2 @@\n tool node\n+tool uv\n'
out=$(printf '%s' "$diff_with_tool" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[32m+\e[0m\e[36m\e[1mtool\e[0m\e[32m uv\e[0m' "$out"

t "XSANDBOX_COLOR=always: added comment line has green polarity but no verb overlay"
diff_with_comment=$'--- trusted\n+++ current\n@@ -1,1 +1,2 @@\n tool node\n+# a new comment\n'
out=$(printf '%s' "$diff_with_comment" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[32m+# a new comment\e[0m' "$out"
assert_not_contains $'\e[1m+# a new comment' "$out"

t "XSANDBOX_COLOR=always: cyan on +++/--- file headers"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[36m\e[1m--- trusted\e[0m' "$out"
assert_contains $'\e[36m\e[1m+++ current\e[0m' "$out"

t "XSANDBOX_COLOR=always: cyan on @@ hunk header"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[36m@@ -1,3 +1,4 @@\e[0m' "$out"

t "XSANDBOX_COLOR=always: context line is dim"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
assert_contains $'\e[2m tool node\e[0m' "$out"

t "colorized diff strips to original content"
out=$(printf '%s' "$__sample_diff" | XSANDBOX_COLOR=always __xsandbox_colorize_diff)
stripped=$(printf '%s' "$out" | strip_ansi)
# Command substitution strips a trailing newline; normalize both sides
assert_eq "${__sample_diff%$'\n'}" "$stripped"

# ── New-config colorizer tests ────────────────────────────────
__sample_new=$'# a comment\ntool node\nallow-read ~/.config/foo\nallow-write ~/data\nallow-exec ~/.local/bin/x\n'

t "new-config: XSANDBOX_COLOR=never pass-through"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=never __xsandbox_colorize_new)
assert_eq "$__sample_new" "${out}"$'\n'

t "new-config: tool verb cyan+bold"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=always __xsandbox_colorize_new)
assert_contains $'\e[36m\e[1mtool\e[0m node' "$out"

t "new-config: allow-read verb green+bold"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=always __xsandbox_colorize_new)
assert_contains $'\e[32m\e[1mallow-read\e[0m ~/.config/foo' "$out"

t "new-config: allow-write verb yellow+bold"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=always __xsandbox_colorize_new)
assert_contains $'\e[33m\e[1mallow-write\e[0m ~/data' "$out"

t "new-config: allow-exec verb magenta+bold"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=always __xsandbox_colorize_new)
assert_contains $'\e[35m\e[1mallow-exec\e[0m ~/.local/bin/x' "$out"

t "new-config: comment is dim"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=always __xsandbox_colorize_new)
assert_contains $'\e[2m# a comment\e[0m' "$out"

t "new-config: content preserved after ANSI strip"
out=$(printf '%s' "$__sample_new" | XSANDBOX_COLOR=always __xsandbox_colorize_new)
stripped=$(printf '%s' "$out" | strip_ansi)
assert_eq "${__sample_new%$'\n'}" "$stripped"

# ── Summary-line tests ────────────────────────────────────────
echo "=== Trust gate summary ==="

__write_fixture() {
  local path="$1" content="$2"
  printf '%s' "$content" > "$path"
}

t "summarize_diff: identical files produce no output"
fa="$(fixture sd1a $'tool node\n')"
fb="$(fixture sd1b $'tool node\n')"
out=$(XSANDBOX_COLOR=never __xsandbox_summarize_diff "$fa" "$fb")
assert_eq "" "$out"

t "summarize_diff: uncolored counts match verb categories"
fa="$(fixture sd2a $'tool node\nallow-read ~/.config/old\n')"
fb="$(fixture sd2b $'tool node\nallow-read ~/.config/new\nallow-write ~/data\nallow-exec ~/.local/bin/x\n')"
out=$(XSANDBOX_COLOR=never __xsandbox_summarize_diff "$fa" "$fb")
# +1 exec, +1 write, +1 read, -1 read (tool is unchanged)
assert_contains "+1 exec" "$out"
assert_contains "+1 write" "$out"
assert_contains "+1 read" "$out"
assert_contains "-1 read" "$out"
assert_not_contains "tool" "$out"

t "summarize_diff: ordering is exec, write, tool, read (additions before removals)"
fa="$(fixture sd3a $'tool node\nallow-read ~/r\nallow-write ~/w\nallow-exec ~/x\n')"
fb="$(fixture sd3b $'tool uv\nallow-read ~/r2\nallow-write ~/w2\nallow-exec ~/x2\n')"
out=$(XSANDBOX_COLOR=never __xsandbox_summarize_diff "$fa" "$fb")
# All four are +1/-1 each. Check that exec appears before write, write before tool, tool before read, + before -
exec_pos=$(echo "$out" | awk '{ print index($0, "+1 exec") }')
write_pos=$(echo "$out" | awk '{ print index($0, "+1 write") }')
tool_pos=$(echo "$out" | awk '{ print index($0, "+1 tool") }')
read_pos=$(echo "$out" | awk '{ print index($0, "+1 read") }')
minus_exec_pos=$(echo "$out" | awk '{ print index($0, "-1 exec") }')
if (( exec_pos > 0 && exec_pos < write_pos && write_pos < tool_pos && tool_pos < read_pos && read_pos < minus_exec_pos )); then
  __test_pass=$((__test_pass + 1))
else
  __test_fail=$((__test_fail + 1))
  echo "FAIL: ${__test_name}" >&2
  echo "  positions: +exec=$exec_pos +write=$write_pos +tool=$tool_pos +read=$read_pos -exec=$minus_exec_pos" >&2
  echo "  out: $out" >&2
fi

t "summarize_diff: colored summary includes green +, red -, magenta exec, yellow write"
fa="$(fixture sd4a $'allow-read ~/old\n')"
fb="$(fixture sd4b $'allow-write ~/new\nallow-exec ~/x\n')"
out=$(XSANDBOX_COLOR=always __xsandbox_summarize_diff "$fa" "$fb")
assert_contains $'\e[32m+1\e[0m' "$out"     # green +
assert_contains $'\e[31m-1\e[0m' "$out"     # red -
assert_contains $'\e[35m\e[1mexec\e[0m' "$out"   # magenta exec
assert_contains $'\e[33m\e[1mwrite\e[0m' "$out"  # yellow write

t "summarize_new: empty/commented file produces no output"
fa="$(fixture sn1 $'# just a comment\n\n')"
out=$(XSANDBOX_COLOR=never __xsandbox_summarize_new "$fa")
assert_eq "" "$out"

t "summarize_new: counts verbs (comments ignored)"
fa="$(fixture sn2 $'# header\ntool node\ntool uv\nallow-read ~/a\nallow-write ~/b\nallow-exec ~/c\nallow-exec ~/d\n')"
out=$(XSANDBOX_COLOR=never __xsandbox_summarize_new "$fa")
assert_contains "2 exec" "$out"
assert_contains "1 write" "$out"
assert_contains "2 tool" "$out"
assert_contains "1 read" "$out"

t "summarize_new: colored segments include severity palette"
fa="$(fixture sn3 $'tool node\nallow-exec ~/x\n')"
out=$(XSANDBOX_COLOR=always __xsandbox_summarize_new "$fa")
assert_contains $'\e[36m\e[1mtool\e[0m' "$out"
assert_contains $'\e[35m\e[1mexec\e[0m' "$out"

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
