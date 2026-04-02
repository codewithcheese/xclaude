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
    # Strip comments and leading/trailing whitespace (tabs and spaces)
    line="${line%%#*}"
    line="${line##[[:space:]]#}"
    line="${line%%[[:space:]]#}"
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
          echo "xclaude: available: $(ls "${toolchains_dir}"/*.sb 2>/dev/null | xargs -I{} basename {} .sb | tr '\n' ' ')" >&2
          return 1
        fi
        echo "$line"
        ;;
      allow-read|allow-write|allow-exec)
        # Validate path prefix
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
        # Block system paths that the base profile already covers
        case "$arg" in
          /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
            echo "xclaude: system path '${arg}' is already allowed by base profile" >&2
            return 1
            ;;
        esac
        # Block rules targeting .xclaude itself — the config file
        # must not be writable or executable from inside the sandbox
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

# ── Trust gate ────────────────────────────────────────────────
# .xclaude files are security-sensitive — they control what the
# sandbox allows. Like direnv, we require explicit approval.
#
# Approved configs are tracked by sha256 hash in:
#   ~/.config/xclaude/trusted
#
# Returns 0 if trusted, 1 if denied.
__xclaude_trust_dir="${HOME}/.config/xclaude"
__xclaude_trusted_file="${__xclaude_trust_dir}/trusted"
# Directory storing copies of previously approved configs for diffing
__xclaude_trusted_copies="${__xclaude_trust_dir}/trusted.d"

__xclaude_file_hash() {
  shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

# Returns a stable filename for storing a trusted copy, derived from the filepath
__xclaude_path_key() {
  echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

__xclaude_is_trusted() {
  local file="$1"
  [[ ! -f "$__xclaude_trusted_file" ]] && return 1
  local hash="$(__xclaude_file_hash "$file")"
  grep -q "^${hash} " "$__xclaude_trusted_file" 2>/dev/null
}

# Returns 0 if there is a previously trusted version of this file (even if hash changed)
__xclaude_was_previously_trusted() {
  local file="$1"
  [[ ! -f "$__xclaude_trusted_file" ]] && return 1
  grep -q "# ${file}$" "$__xclaude_trusted_file" 2>/dev/null
}

__xclaude_trust() {
  local file="$1"
  mkdir -p "$__xclaude_trust_dir" "$__xclaude_trusted_copies"
  local hash="$(__xclaude_file_hash "$file")"
  # Remove old entries for this file path, then add current hash
  if [[ -f "$__xclaude_trusted_file" ]]; then
    grep -v "# ${file}$" "$__xclaude_trusted_file" > "${__xclaude_trusted_file}.tmp" 2>/dev/null || true
    mv "${__xclaude_trusted_file}.tmp" "$__xclaude_trusted_file"
  fi
  echo "${hash} # ${file}" >> "$__xclaude_trusted_file"
  # Store a copy so we can diff against it when the config changes
  cp "$file" "${__xclaude_trusted_copies}/$(__xclaude_path_key "$file")"
}

__xclaude_check_trust() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  __xclaude_is_trusted "$file" && return 0

  local trusted_copy="${__xclaude_trusted_copies}/$(__xclaude_path_key "$file")"

  if __xclaude_was_previously_trusted "$file" && [[ -f "$trusted_copy" ]]; then
    # Config changed — show diff
    echo "xclaude: config changed: ${file}" >&2
    echo "─────────────────────────────────────" >&2
    # unified diff: old (trusted) vs new (current), coloured if tput available
    diff -u "$trusted_copy" "$file" \
      --label "trusted" --label "current" >&2 || true
    echo "─────────────────────────────────────" >&2
  else
    # New config — show full contents
    echo "xclaude: new config: ${file}" >&2
    echo "─────────────────────────────────────" >&2
    cat "$file" >&2
    echo "─────────────────────────────────────" >&2
  fi

  echo -n "xclaude: allow this config? [y/N] " >&2
  local reply
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS])
      __xclaude_trust "$file"
      return 0
      ;;
    *)
      echo "xclaude: denied — running with base profile only" >&2
      return 1
      ;;
  esac
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

  # Layer: project config (trust-gated)
  if [[ -f "$project_config" ]] && __xclaude_check_trust "$project_config"; then
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
  local tmpdir="${TMPDIR:-/private/tmp}"
  # Resolve symlinks (Seatbelt uses real paths, /var -> /private/var)
  local home_dir="$(readlink -f "${HOME}")"
  local project_dir="$(readlink -f "${PWD}")"
  tmpdir="$(readlink -f "$tmpdir")"

  # TMPDIR is .../T or .../T/, siblings are .../C (cache) and .../X (volatile)
  # Cache: needed by Security framework (Spotlight mds) for keychain access
  # Volatile: needed by macOS for code-signing clones at process launch
  local cache_dir="${tmpdir%/T*}/C"
  local volatile_dir="${tmpdir%/T*}/X"

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

  # Stream sandbox denials to a temp file outside the sandbox.
  # The hook script (inside the sandbox) reads this file since
  # /usr/bin/log refuses to run inside a sandbox.
  local denial_log="${tmpdir}/xclaude-$$-denials.log"
  setopt local_options no_monitor
  /usr/bin/log stream \
    --predicate 'eventMessage CONTAINS "Sandbox" AND eventMessage CONTAINS "deny"' \
    --style compact > "$denial_log" 2>/dev/null &
  local log_pid=$!

  local xclaude_dir_resolved="$(readlink -f "${__xclaude_dir}")"

  XCLAUDE_ACTIVE=1 XCLAUDE_DENIAL_LOG="$denial_log" sandbox-exec \
    -D "PROJECT_DIR=${project_dir}" \
    -D "TMPDIR=${tmpdir}" \
    -D "CACHE_DIR=${cache_dir}" \
    -D "VOLATILE_DIR=${volatile_dir}" \
    -D "HOME=${home_dir}" \
    -D "XCLAUDE_DIR=${xclaude_dir_resolved}" \
    -f "$profile_path" \
    -- claude --dangerously-skip-permissions --plugin-dir "${__xclaude_dir}" "$@"
  local rc=$?

  # Cleanup
  kill "$log_pid" 2>/dev/null || true
  wait "$log_pid" 2>/dev/null || true
  rm -f "$profile_path" "$denial_log"
  return $rc
}
