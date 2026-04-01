__xclaude_dir="${0:A:h}"

# ── DSL parser ────────────────────────────────────────────────
# Parses .xclaude config files. Outputs normalized directives to
# stdout, one per line: "tool <name>" | "allow-read <path>" |
# "allow-write <path>" | "allow-exec <path>"
#
# Path expansion: ~ → $HOME, ./ → $PROJECT_DIR, else absolute.
# Errors go to stderr; returns 1 on first invalid line.
__xclaude_parse() {
  local file="$1" line verb arg lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    # Strip comments and leading/trailing whitespace
    line="${line%%#*}"
    line="${line## }"
    line="${line%% }"
    [[ -z "$line" ]] && continue

    verb="${line%% *}"
    arg="${line#* }"
    # If line has no space, arg == verb (no argument)
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

# ── Validator ─────────────────────────────────────────────────
# Reads parsed directives from stdin. Validates:
#   - tool names exist in toolchains/
#   - paths don't reference dangerous locations
#   - paths start with ~, ./, or / (absolute)
# Passes valid lines through to stdout. Errors to stderr.
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
        # Validate path prefix
        local prefix2="${arg:0:2}"
        if [[ "$arg" = "~" ]]; then
          echo "xclaude: bare '~' is too broad — use ~/specific/path" >&2
          return 1
        elif [[ "$prefix2" != "~/" && "$prefix2" != "./" && "${arg:0:1}" != "/" ]]; then
          echo "xclaude: invalid path '${arg}' — must start with ~/, ./, or /" >&2
          return 1
        fi
        # Block system paths that the base profile already covers
        case "$arg" in
          /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
            echo "xclaude: system path '${arg}' is already allowed by base profile" >&2
            return 1
            ;;
        esac
        echo "$line"
        ;;
    esac
  done
}

# ── SBPL generator ────────────────────────────────────────────
# Reads validated directives from stdin. Outputs SBPL rules to
# stdout. Toolchain directives emit the contents of their .sb
# file. Path directives emit appropriate (allow ...) rules.
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

# ── Path → SBPL expression ───────────────────────────────────
# Converts a DSL path to an SBPL subpath expression string.
#   ~/foo  → (string-append (param "HOME") "/foo")
#   ./foo  → (string-append (param "PROJECT_DIR") "/foo")
#   /foo   → "/foo"
__xclaude_path_to_sbpl() {
  local p="$1"
  local prefix2="${p:0:2}"
  if [[ "$prefix2" = "~/" ]]; then
    echo "(string-append (param \"HOME\") \"/${p:2}\")"
  elif [[ "$prefix2" = "./" ]]; then
    echo "(string-append (param \"PROJECT_DIR\") \"/${p:2}\")"
  elif [[ "${p:0:1}" = "/" ]]; then
    echo "\"${p}\""
  fi
}

# ── Profile assembler ────────────────────────────────────────
# Combines base.sb + user config + project config into a single
# SBPL profile written to a temp file. Returns the path.
__xclaude_assemble() {
  local project_dir="$1"
  local base_profile="${__xclaude_dir}/base.sb"
  local user_config="${HOME}/.config/xclaude/config"
  local project_config="${project_dir}/.xclaude"
  local assembled generated

  # Start with base
  assembled="$(cat "$base_profile")"

  # Layer: user config
  if [[ -f "$user_config" ]]; then
    generated="$(__xclaude_parse "$user_config" | __xclaude_validate | __xclaude_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; User config: ~/.config/xclaude/config'
      assembled+=$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  # Layer: project config
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

# ── Main entry point ─────────────────────────────────────────
xclaude() {
  local project_dir="${PWD}"
  local tmpdir="${TMPDIR:-/private/tmp}"
  local home_dir="${HOME}"

  # Resolve symlinks (Seatbelt uses real paths, /var -> /private/var)
  tmpdir="$(readlink -f "$tmpdir")"

  # TMPDIR is .../T or .../T/, cache dir is sibling .../C
  # Needed by Security framework (Spotlight mds) for keychain access
  local cache_dir="${tmpdir%/T*}/C"

  if [[ ! -f "${__xclaude_dir}/base.sb" ]]; then
    echo "xclaude: base.sb not found at ${__xclaude_dir}/base.sb" >&2
    return 1
  fi

  # Assemble the sandbox profile
  local profile
  profile="$(__xclaude_assemble "$project_dir")" || return 1

  # Write assembled profile to temp file
  local profile_path="${tmpdir}/xclaude-$$.sb"
  echo "$profile" > "$profile_path"

  if ! command -v sandbox-exec &>/dev/null; then
    echo "xclaude: sandbox-exec not found, running without sandbox" >&2
    claude "$@"
    return
  fi

  sandbox-exec \
    -D "PROJECT_DIR=${project_dir}" \
    -D "TMPDIR=${tmpdir}" \
    -D "CACHE_DIR=${cache_dir}" \
    -D "HOME=${home_dir}" \
    -f "$profile_path" \
    -- claude --dangerously-skip-permissions "$@"
  local rc=$?

  # Cleanup
  rm -f "$profile_path"
  return $rc
}
