# Shared sandbox library — DSL parser, validator, SBPL generator, trust gate, assembler
# Sourced by xclaude.lib.zsh and xcodex.lib.zsh. No side effects on load.
#
# Required variables before use:
#   __xsandbox_name         Display name / config namespace (e.g. xclaude)
#   __xsandbox_dir          Installation directory
# Optional variables:
#   __xsandbox_base_profile Path to the base SBPL profile
#   __xsandbox_config_name  Project config basename (default: .<name>)
#   __xsandbox_user_config  User config path (default: ~/.config/<name>/config)
#   __xsandbox_trust_dir    Trust store directory (default: ~/.config/<name>)
#   __xsandbox_trusted_file Trust ledger path
#   __xsandbox_trusted_copies Directory of trusted config snapshots

__xsandbox_sync_defaults() {
  : "${__xsandbox_name:?__xsandbox_name is required}"
  : "${__xsandbox_dir:?__xsandbox_dir is required}"
  : "${__xsandbox_base_profile:=${__xsandbox_dir}/base.sb}"
  : "${__xsandbox_config_name:=.${__xsandbox_name}}"
  : "${__xsandbox_user_config:=${HOME}/.config/${__xsandbox_name}/config}"
  : "${__xsandbox_trust_dir:=${HOME}/.config/${__xsandbox_name}}"
  : "${__xsandbox_trusted_file:=${__xsandbox_trust_dir}/trusted}"
  : "${__xsandbox_trusted_copies:=${__xsandbox_trust_dir}/trusted.d}"
}

__xsandbox_log() {
  echo "${__xsandbox_name}: $*" >&2
}

__xsandbox_read_base_profile() {
  __xsandbox_sync_defaults
  local -a base_profiles
  base_profiles=("${__xsandbox_base_profiles[@]}")
  if (( ${#base_profiles[@]} > 0 )); then
    cat "${base_profiles[@]}"
  else
    cat "$__xsandbox_base_profile"
  fi
}

__xsandbox_parse() {
  __xsandbox_sync_defaults
  local file="$1" line verb arg lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%%#*}"
    line="${line##[[:space:]]#}"
    line="${line%%[[:space:]]#}"
    [[ -z "$line" ]] && continue

    verb="${line%% *}"
    arg="${line#* }"
    [[ "$arg" = "$verb" ]] && arg=""

    case "$verb" in
      tool)
        [[ -z "$arg" ]] && { __xsandbox_log "${file}:${lineno}: 'tool' requires a name"; return 1; }
        echo "tool ${arg}"
        ;;
      allow-read|allow-write|allow-exec)
        [[ -z "$arg" ]] && { __xsandbox_log "${file}:${lineno}: '${verb}' requires a path"; return 1; }
        echo "${verb} ${arg}"
        ;;
      *)
        __xsandbox_log "${file}:${lineno}: unknown directive '${verb}'"
        return 1
        ;;
    esac
  done < "$file"
}

__xsandbox_validate() {
  __xsandbox_sync_defaults
  local line verb arg toolchains_dir="${__xsandbox_dir}/toolchains"
  while IFS= read -r line; do
    verb="${line%% *}"
    arg="${line#* }"

    case "$verb" in
      tool)
        if [[ ! -f "${toolchains_dir}/${arg}.sb" ]]; then
          __xsandbox_log "unknown toolchain '${arg}'"
          __xsandbox_log "available: $(ls "${toolchains_dir}"/*.sb 2>/dev/null | xargs -I{} basename {} .sb | tr '\n' ' ')"
          return 1
        fi
        echo "$line"
        ;;
      allow-read|allow-write|allow-exec)
        local prefix2="${arg:0:2}"
        if [[ "$arg" = "~" || "$arg" = "~/" ]]; then
          __xsandbox_log "bare '~' or '~/' is too broad — use ~/specific/path"
          return 1
        elif [[ "$arg" = "./" || "$arg" = "." ]]; then
          __xsandbox_log "bare './' is too broad — use ./specific/path"
          return 1
        elif [[ "$prefix2" != "~/" && "$prefix2" != "./" && "${arg:0:1}" != "/" ]]; then
          __xsandbox_log "invalid path '${arg}' — must start with ~/, ./, or /"
          return 1
        fi
        case "$arg" in
          /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
            __xsandbox_log "system path '${arg}' is already allowed by base profile"
            return 1
            ;;
        esac
        local basename="${arg##*/}"
        if [[ "$basename" = "${__xsandbox_config_name}" ]]; then
          __xsandbox_log "cannot target '${__xsandbox_config_name}' — sandbox config is protected"
          return 1
        fi
        echo "$line"
        ;;
    esac
  done
}

__xsandbox_generate() {
  __xsandbox_sync_defaults
  local line verb arg sbpl_path toolchains_dir="${__xsandbox_dir}/toolchains"
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
        sbpl_path="$(__xsandbox_path_to_sbpl "$arg")"
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

__xsandbox_path_to_sbpl() {
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

__xsandbox_file_hash() {
  shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

__xsandbox_path_key() {
  echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

__xsandbox_is_trusted() {
  __xsandbox_sync_defaults
  local file="$1"
  [[ ! -f "$__xsandbox_trusted_file" ]] && return 1
  local hash="$(__xsandbox_file_hash "$file")"
  grep -q "^${hash} " "$__xsandbox_trusted_file" 2>/dev/null
}

__xsandbox_was_previously_trusted() {
  __xsandbox_sync_defaults
  local file="$1"
  [[ ! -f "$__xsandbox_trusted_file" ]] && return 1
  grep -q "# ${file}$" "$__xsandbox_trusted_file" 2>/dev/null
}

__xsandbox_trust() {
  __xsandbox_sync_defaults
  local file="$1"
  mkdir -p "$__xsandbox_trust_dir" "$__xsandbox_trusted_copies"
  local hash="$(__xsandbox_file_hash "$file")"
  if [[ -f "$__xsandbox_trusted_file" ]]; then
    grep -v "# ${file}$" "$__xsandbox_trusted_file" > "${__xsandbox_trusted_file}.tmp" 2>/dev/null || true
    mv "${__xsandbox_trusted_file}.tmp" "$__xsandbox_trusted_file"
  fi
  echo "${hash} # ${file}" >> "$__xsandbox_trusted_file"
  cp "$file" "${__xsandbox_trusted_copies}/$(__xsandbox_path_key "$file")"
}

__xsandbox_check_trust() {
  __xsandbox_sync_defaults
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  __xsandbox_is_trusted "$file" && return 0

  local trusted_copy="${__xsandbox_trusted_copies}/$(__xsandbox_path_key "$file")"

  if __xsandbox_was_previously_trusted "$file" && [[ -f "$trusted_copy" ]]; then
    __xsandbox_log "config changed: ${file}"
    echo "─────────────────────────────────────" >&2
    diff -u "$trusted_copy" "$file" --label "trusted" --label "current" >&2 || true
    echo "─────────────────────────────────────" >&2
  else
    __xsandbox_log "new config: ${file}"
    echo "─────────────────────────────────────" >&2
    cat "$file" >&2
    echo "─────────────────────────────────────" >&2
  fi

  echo -n "${__xsandbox_name}: allow this config? [y/N] " >&2
  local reply
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS])
      __xsandbox_trust "$file"
      return 0
      ;;
    *)
      __xsandbox_log "denied — running with base profile only"
      return 1
      ;;
  esac
}

__xsandbox_assemble() {
  __xsandbox_sync_defaults
  local project_dir="$1"
  local project_config="${project_dir}/${__xsandbox_config_name}"
  local assembled generated

  assembled="$(__xsandbox_read_base_profile)"

  if [[ -f "$__xsandbox_user_config" ]]; then
    generated="$(__xsandbox_parse "$__xsandbox_user_config" | __xsandbox_validate | __xsandbox_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; User config: '"${__xsandbox_user_config/#${HOME}/~}"$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  if [[ -f "$project_config" ]] && __xsandbox_check_trust "$project_config"; then
    generated="$(__xsandbox_parse "$project_config" | __xsandbox_validate | __xsandbox_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; Project config: '"${__xsandbox_config_name}"$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  echo "$assembled"
}
