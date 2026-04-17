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
        case "$verb" in
          allow-read)
            case "$arg" in
              /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
                __xsandbox_log "system path '${arg}' is already readable via base profile"
                return 1
                ;;
            esac
            ;;
          allow-write)
            case "$arg" in
              /System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/opt/homebrew/*)
                __xsandbox_log "system path '${arg}' cannot be made writable from project config"
                return 1
                ;;
            esac
            ;;
          allow-exec)
            case "$arg" in
              /bin/*|/usr/bin/*|/opt/homebrew/*)
                __xsandbox_log "exec path '${arg}' is already allowed by base profile"
                return 1
                ;;
            esac
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
  # On changed (+/-) lines with a known verb, the polarity color wraps the
  # whole line and the verb token is overlaid with its severity color in
  # bold. Verb palette: tool=cyan, allow-read=green, allow-write=yellow,
  # allow-exec=magenta. Severity reads at a glance inside either polarity.
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

__xsandbox_summarize_diff() {
  # One-line verb-grouped summary of a diff between two files.
  # Format: "  +1 exec  +1 write  +1 tool  -1 read" — zero-count verbs omitted.
  # Writes nothing if both files are identical.
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
  # Order: exec, write, tool, read (most-to-least capable), additions first.
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
  # One-line verb-grouped summary of a single config file (no signs).
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
  (( read_n > 0 ))  && segs+=("${read_n} ${G}${B}read${Z}")

  local out="" s first=1
  for s in "${segs[@]}"; do
    if (( first )); then out="$s"; first=0; else out+="  $s"; fi
  done
  printf '  %s\n' "$out"
}

__xsandbox_check_trust() {
  __xsandbox_sync_defaults
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  __xsandbox_is_trusted "$file" && return 0

  local trusted_copy="${__xsandbox_trusted_copies}/$(__xsandbox_path_key "$file")"

  if __xsandbox_was_previously_trusted "$file" && [[ -f "$trusted_copy" ]]; then
    __xsandbox_log "config changed: ${file}"
    __xsandbox_summarize_diff "$trusted_copy" "$file" >&2
    echo "─────────────────────────────────────" >&2
    diff -u "$trusted_copy" "$file" --label "trusted" --label "current" \
      | __xsandbox_colorize_diff >&2 || true
    echo "─────────────────────────────────────" >&2
  else
    __xsandbox_log "new config: ${file}"
    __xsandbox_summarize_new "$file" >&2
    echo "─────────────────────────────────────" >&2
    __xsandbox_colorize_new < "$file" >&2
    echo "─────────────────────────────────────" >&2
  fi

  local PB="" PZ=""
  if __xsandbox_color_enabled; then
    PB=$'\e[1m'
    PZ=$'\e[0m'
  fi
  echo -n "${PB}${__xsandbox_name}: allow this config? [y/N]${PZ} " >&2
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
