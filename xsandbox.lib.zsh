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
  : "${__xsandbox_packs_dir:=${HOME}/.config/${__xsandbox_name}/packs}"
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
      pack)
        [[ -z "$arg" ]] && { __xsandbox_log "${file}:${lineno}: 'pack' requires a name"; return 1; }
        # Pack names are file basenames under ~/.config/<name>/packs/ — constrain
        # to a safe charset so '..', '/', or leading dashes can't escape the dir.
        if [[ ! "$arg" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
          __xsandbox_log "${file}:${lineno}: invalid pack name '${arg}' — use [A-Za-z0-9_-], no leading dash"
          return 1
        fi
        echo "pack ${arg}"
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
  # Source context controls which verbs are legal here:
  #   user    — ~/.config/<name>/config
  #   project — project <config_name> file
  #   pack    — a file inside ~/.config/<name>/packs/
  # `pack` directives are only legal when source=project (no nesting, no
  # user-level packs — packs exist to reuse config across projects).
  local source="${1:-project}"
  local line verb arg toolchains_dir="${__xsandbox_dir}/toolchains"
  local packs_dir="${__xsandbox_packs_dir}"
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
      pack)
        case "$source" in
          user)
            __xsandbox_log "'pack' is not allowed in user config — packs are for project-level reuse only"
            return 1
            ;;
          pack)
            __xsandbox_log "'pack' cannot be nested inside another pack (pack '${arg}')"
            return 1
            ;;
        esac
        if [[ ! -f "${packs_dir}/${arg}" ]]; then
          __xsandbox_log "unknown pack '${arg}' — expected file at ${packs_dir}/${arg}"
          if [[ -d "$packs_dir" ]]; then
            __xsandbox_log "available: $(ls "${packs_dir}" 2>/dev/null | tr '\n' ' ')"
          else
            __xsandbox_log "packs directory does not exist — create it and add pack files as plain DSL"
          fi
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
  # pipefail is required: the `pack` branch recurses through
  # parse|validate|generate, and a failure in any stage must abort
  # the whole expansion (not silently produce an empty fragment).
  setopt local_options pipefail
  local line verb arg sbpl_path toolchains_dir="${__xsandbox_dir}/toolchains"
  local packs_dir="${__xsandbox_packs_dir}"
  local pack_file pack_content
  while IFS= read -r line; do
    verb="${line%% *}"
    arg="${line#* }"

    case "$verb" in
      tool)
        echo ""
        echo ";; ── toolchain: ${arg} ──"
        cat "${toolchains_dir}/${arg}.sb"
        ;;
      pack)
        # Validator already confirmed file existence and legality in the
        # enclosing source. Recurse with source=pack to forbid nesting.
        pack_file="${packs_dir}/${arg}"
        pack_content="$(__xsandbox_parse "$pack_file" | __xsandbox_validate pack | __xsandbox_generate)" || return 1
        echo ""
        echo ";; ── pack: ${arg} (${pack_file/#${HOME}/~}) ──"
        printf '%s\n' "$pack_content"
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

# Trust scope: a stable identity for "where this config lives" so trust can
# follow the project, not the absolute file path. Inside a git working tree
# the scope is the resolved git-common-dir (shared by main repo and all
# worktrees). Outside git it falls back to the resolved file path.
#
#   in repo:    repo:/abs/path/to/.git
#   not in repo: path:/abs/path/to/file
__xsandbox_trust_scope() {
  __xsandbox_sync_defaults
  local file="$1"
  local dir="${file:h}"
  local common_dir
  if common_dir="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)"; then
    case "$common_dir" in
      /*) common_dir="$(readlink -f "$common_dir")" ;;
      *)  common_dir="$(readlink -f "${dir}/${common_dir}")" ;;
    esac
    echo "repo:${common_dir}"
  else
    echo "path:$(readlink -f "$file")"
  fi
}

__xsandbox_path_key() {
  echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

# Snapshot key for a (project, pack) pair. Keyed on the project's trust
# scope (repo: or path:) so worktrees of the same repo share pack trust
# while unrelated projects remain independent. Different name from the
# legacy key (`__xsandbox_pack_key_legacy`) so check_pack_trust can fall
# back to the old key during migration.
__xsandbox_pack_key() {
  local pack_file="$1" project_config="$2"
  local pack_name="${pack_file##*/}"
  local scope="$(__xsandbox_trust_scope "$project_config")"
  echo -n "${scope}|pack|${pack_name}" | shasum -a 256 | cut -d' ' -f1
}

__xsandbox_pack_key_legacy() {
  local pack_file="$1" project_config="$2"
  local pack_name="${pack_file##*/}"
  echo -n "${project_config}|pack|${pack_name}" | shasum -a 256 | cut -d' ' -f1
}

# Trust ledger entry formats:
#   in-repo:  "<hash> # repo:<git_common_dir> @ <file_path>"
#   non-git:  "<hash> # path:<resolved_file_path>"
#   legacy:   "<hash> # <file_path>"     (read-only compat; trust() rewrites)
#
# Lookup matches all three. trust() always writes the new format and removes
# any prior entry for the same scope OR for the legacy file path so the
# ledger stays a single source of truth as users upgrade.

__xsandbox_is_trusted() {
  __xsandbox_sync_defaults
  local file="$1" hash scope new_exact new_prefix legacy_exact line
  [[ ! -f "$__xsandbox_trusted_file" ]] && return 1
  hash="$(__xsandbox_file_hash "$file")"
  scope="$(__xsandbox_trust_scope "$file")"
  new_exact="${hash} # ${scope}"
  new_prefix="${hash} # ${scope} @ "
  legacy_exact="${hash} # ${file}"
  while IFS= read -r line; do
    [[ "$line" = "$new_exact" ]] && return 0
    [[ "$line" = "${new_prefix}"* ]] && return 0
    [[ "$line" = "$legacy_exact" ]] && return 0
  done < "$__xsandbox_trusted_file"
  return 1
}

__xsandbox_was_previously_trusted() {
  __xsandbox_sync_defaults
  local file="$1" scope new_exact_suffix new_substr legacy_suffix line
  [[ ! -f "$__xsandbox_trusted_file" ]] && return 1
  scope="$(__xsandbox_trust_scope "$file")"
  new_exact_suffix=" # ${scope}"
  new_substr=" # ${scope} @ "
  legacy_suffix=" # ${file}"
  while IFS= read -r line; do
    [[ "$line" = *"$new_substr"* ]] && return 0
    [[ "$line" = *"$new_exact_suffix" ]] && return 0
    [[ "$line" = *"$legacy_suffix" ]] && return 0
  done < "$__xsandbox_trusted_file"
  return 1
}

__xsandbox_trust() {
  __xsandbox_sync_defaults
  local file="$1"
  mkdir -p "$__xsandbox_trust_dir" "$__xsandbox_trusted_copies"
  local hash="$(__xsandbox_file_hash "$file")"
  local scope="$(__xsandbox_trust_scope "$file")"
  local new_exact_suffix=" # ${scope}"
  local new_substr=" # ${scope} @ "
  local legacy_suffix=" # ${file}"
  local entry
  case "$scope" in
    # Repo scope: include @ <file> tail so the entry shows where the file lived.
    repo:*) entry="${hash} # ${scope} @ ${file}" ;;
    # Path scope: file path is already in the scope key — no redundant tail.
    *)      entry="${hash} # ${scope}" ;;
  esac
  if [[ -f "$__xsandbox_trusted_file" ]]; then
    : > "${__xsandbox_trusted_file}.tmp"
    local line
    while IFS= read -r line; do
      [[ "$line" = *"$new_substr"* ]]      && continue   # drop in-repo entries for this scope
      [[ "$line" = *"$new_exact_suffix" ]] && continue   # drop path-scope entries for this scope
      [[ "$line" = *"$legacy_suffix" ]]    && continue   # drop legacy entry for this exact path
      printf '%s\n' "$line" >> "${__xsandbox_trusted_file}.tmp"
    done < "$__xsandbox_trusted_file"
    mv "${__xsandbox_trusted_file}.tmp" "$__xsandbox_trusted_file"
  fi
  echo "$entry" >> "$__xsandbox_trusted_file"
  cp "$file" "${__xsandbox_trusted_copies}/$(__xsandbox_path_key "$scope")"
}

# Pack trust ledger entry formats:
#   in-repo:  "<pack_hash> # repo:<git_common_dir> pack <pack_name> @ <project_config>"
#   non-git:  "<pack_hash> # path:<resolved_project_config> pack <pack_name>"
#   legacy:  "<pack_hash> # <project_config> pack <pack_name>"
#
# Scope = trust_scope(project_config). Sharing follows the project: worktrees
# of the same repo inherit pack trust at the same content hash; different
# repos always re-prompt.

__xsandbox_is_pack_trusted_for_project() {
  __xsandbox_sync_defaults
  local pack_file="$1" project_config="$2"
  [[ ! -f "$__xsandbox_trusted_file" ]] && return 1
  local hash="$(__xsandbox_file_hash "$pack_file")"
  local pack_name="${pack_file##*/}"
  local scope="$(__xsandbox_trust_scope "$project_config")"
  local new_exact="${hash} # ${scope} pack ${pack_name}"
  local new_prefix="${hash} # ${scope} pack ${pack_name} @ "
  local legacy_exact="${hash} # ${project_config} pack ${pack_name}"
  local line
  while IFS= read -r line; do
    [[ "$line" = "$new_exact" ]]      && return 0
    [[ "$line" = "${new_prefix}"* ]]  && return 0
    [[ "$line" = "$legacy_exact" ]]   && return 0
  done < "$__xsandbox_trusted_file"
  return 1
}

__xsandbox_was_pack_previously_trusted_for_project() {
  __xsandbox_sync_defaults
  local pack_file="$1" project_config="$2"
  [[ ! -f "$__xsandbox_trusted_file" ]] && return 1
  local pack_name="${pack_file##*/}"
  local scope="$(__xsandbox_trust_scope "$project_config")"
  local new_exact_suffix=" # ${scope} pack ${pack_name}"
  local new_substr=" # ${scope} pack ${pack_name} @ "
  local legacy_suffix=" # ${project_config} pack ${pack_name}"
  local line
  while IFS= read -r line; do
    [[ "$line" = *"$new_substr"* ]]      && return 0
    [[ "$line" = *"$new_exact_suffix" ]] && return 0
    [[ "$line" = *"$legacy_suffix" ]]    && return 0
  done < "$__xsandbox_trusted_file"
  return 1
}

__xsandbox_trust_pack_for_project() {
  __xsandbox_sync_defaults
  local pack_file="$1" project_config="$2"
  mkdir -p "$__xsandbox_trust_dir" "$__xsandbox_trusted_copies"
  local hash="$(__xsandbox_file_hash "$pack_file")"
  local pack_name="${pack_file##*/}"
  local scope="$(__xsandbox_trust_scope "$project_config")"
  local new_exact_suffix=" # ${scope} pack ${pack_name}"
  local new_substr=" # ${scope} pack ${pack_name} @ "
  local legacy_suffix=" # ${project_config} pack ${pack_name}"
  local entry
  case "$scope" in
    repo:*) entry="${hash} # ${scope} pack ${pack_name} @ ${project_config}" ;;
    *)      entry="${hash} # ${scope} pack ${pack_name}" ;;
  esac
  if [[ -f "$__xsandbox_trusted_file" ]]; then
    : > "${__xsandbox_trusted_file}.tmp"
    local line
    while IFS= read -r line; do
      [[ "$line" = *"$new_substr"* ]]      && continue
      [[ "$line" = *"$new_exact_suffix" ]] && continue
      [[ "$line" = *"$legacy_suffix" ]]    && continue
      printf '%s\n' "$line" >> "${__xsandbox_trusted_file}.tmp"
    done < "$__xsandbox_trusted_file"
    mv "${__xsandbox_trusted_file}.tmp" "$__xsandbox_trusted_file"
  fi
  echo "$entry" >> "$__xsandbox_trusted_file"
  cp "$pack_file" "${__xsandbox_trusted_copies}/$(__xsandbox_pack_key "$pack_file" "$project_config")"
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

  local scope="$(__xsandbox_trust_scope "$file")"
  local trusted_copy="${__xsandbox_trusted_copies}/$(__xsandbox_path_key "$scope")"
  # Fall back to the legacy snapshot key (hash of the file path) so users
  # upgrading from a path-keyed ledger still see a diff on the first re-trust.
  if [[ ! -f "$trusted_copy" ]]; then
    trusted_copy="${__xsandbox_trusted_copies}/$(__xsandbox_path_key "$file")"
  fi

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
      __xsandbox_log "denied"
      return 1
      ;;
  esac
}

# Per-(project, pack) trust gate. Silent when the pack's current hash is
# already trusted for this project (prints a reminder line + summary so the
# user still sees what's active). Prompts on new, changed, or never-seen-
# for-this-project packs. Return 0 on approval (or no-op), 1 on denial.
__xsandbox_check_pack_trust() {
  __xsandbox_sync_defaults
  local pack_file="$1" project_config="$2"
  [[ ! -f "$pack_file" ]] && return 0  # missing pack handled by validator
  local pack_name="${pack_file##*/}"

  if __xsandbox_is_pack_trusted_for_project "$pack_file" "$project_config"; then
    __xsandbox_log "using pack ${pack_name} (trusted)"
    __xsandbox_summarize_new "$pack_file" >&2
    return 0
  fi

  local snapshot="${__xsandbox_trusted_copies}/$(__xsandbox_pack_key "$pack_file" "$project_config")"
  # Legacy snapshot fallback for users upgrading from path-keyed pack trust.
  if [[ ! -f "$snapshot" ]]; then
    snapshot="${__xsandbox_trusted_copies}/$(__xsandbox_pack_key_legacy "$pack_file" "$project_config")"
  fi

  if __xsandbox_was_pack_previously_trusted_for_project "$pack_file" "$project_config" && [[ -f "$snapshot" ]]; then
    __xsandbox_log "pack changed: ${pack_name} (for ${project_config})"
    __xsandbox_summarize_diff "$snapshot" "$pack_file" >&2
    echo "─────────────────────────────────────" >&2
    diff -u "$snapshot" "$pack_file" --label "trusted" --label "current" \
      | __xsandbox_colorize_diff >&2 || true
    echo "─────────────────────────────────────" >&2
  else
    __xsandbox_log "new pack: ${pack_name} (for ${project_config})"
    __xsandbox_summarize_new "$pack_file" >&2
    echo "─────────────────────────────────────" >&2
    __xsandbox_colorize_new < "$pack_file" >&2
    echo "─────────────────────────────────────" >&2
  fi

  local PB="" PZ=""
  if __xsandbox_color_enabled; then
    PB=$'\e[1m'
    PZ=$'\e[0m'
  fi
  echo -n "${PB}${__xsandbox_name}: allow pack ${pack_name} for this project? [y/N]${PZ} " >&2
  local reply
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS])
      __xsandbox_trust_pack_for_project "$pack_file" "$project_config"
      return 0
      ;;
    *)
      __xsandbox_log "pack ${pack_name} denied"
      return 1
      ;;
  esac
}

# Walks the project config for `pack <name>` references and trust-gates
# each one in the context of this project. Stops at the first denial so
# the user sees a clean "pack X denied" error instead of a cascade.
__xsandbox_check_pack_trusts() {
  __xsandbox_sync_defaults
  local project_config="$1"
  [[ ! -f "$project_config" ]] && return 0
  local line name pack_file
  # If the project config has a parse error the assembler will surface it;
  # here we just ignore unparseable lines (|| true) so a bad config
  # doesn't wedge the trust check before the real error is emitted.
  #
  # fd 3 carries the parse output so the inner check_pack_trust can still
  # read user replies from stdin. Without this the while-loop's stdin
  # redirection would starve the interactive `read` inside the prompt.
  while IFS= read -r line <&3; do
    [[ "$line" = "pack "* ]] || continue
    name="${line#pack }"
    pack_file="${__xsandbox_packs_dir}/${name}"
    if ! __xsandbox_check_pack_trust "$pack_file" "$project_config"; then
      exec 3<&-
      return 1
    fi
  done 3< <(__xsandbox_parse "$project_config" 2>/dev/null || true)
  exec 3<&-
  return 0
}

__xsandbox_assemble() {
  __xsandbox_sync_defaults
  # Without pipefail, a parse failure early in the pipeline is masked by
  # the later stages' zero exit. The assembler must abort on any failure.
  setopt local_options pipefail
  local project_dir="$1"
  local project_config="${project_dir}/${__xsandbox_config_name}"
  local assembled generated

  assembled="$(__xsandbox_read_base_profile)"

  # Linked git worktree: auto-grant read on the main checkout so tools like
  # `git -C <main>`, branch comparison, and reading sibling files work from
  # inside the worktree. Writes stay scoped to the worktree's PROJECT_DIR.
  # Skipped for main checkouts (already covered by PROJECT_DIR) and bare
  # repos (no main worktree). Per-worktree opt-out is a future config knob.
  local common_dir main_worktree project_dir_resolved
  project_dir_resolved="$(readlink -f "$project_dir")"
  if common_dir="$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null)"; then
    case "$common_dir" in
      /*) ;;
      *)  common_dir="${project_dir}/${common_dir}" ;;
    esac
    common_dir="$(readlink -f "$common_dir")"
    if [[ "$common_dir" = */.git ]]; then
      local candidate="${common_dir%/.git}"
      if [[ -d "$candidate" && "$candidate" != "$project_dir_resolved" ]]; then
        main_worktree="$candidate"
      fi
    fi
  fi
  if [[ -n "$main_worktree" ]]; then
    assembled+=$'\n\n;; ============================================================'
    assembled+=$'\n;; Linked worktree: read grant for main checkout\n;; ============================================================'
    assembled+=$'\n(allow file-read-data (subpath "'"${main_worktree}"$'"))'
    # Git operations from a linked worktree write to the shared .git/
    # (per-worktree state under worktrees/<name>/, plus shared objects/,
    # refs/, logs/). Allow that, but deny hooks/ and config — those are
    # privilege-escalation paths (hook scripts run on next git op in main;
    # config can redirect remotes). Deny-after-allow uses last-match-wins.
    assembled+=$'\n;; --- shared .git/ writes (minus hooks/ and config) ---'
    assembled+=$'\n(allow file-write* (subpath "'"${common_dir}"$'"))'
    assembled+=$'\n(deny file-write* (subpath "'"${common_dir}"$'/hooks"))'
    assembled+=$'\n(deny file-write* (literal "'"${common_dir}"$'/config"))'
  fi

  if [[ -f "$__xsandbox_user_config" ]]; then
    generated="$(__xsandbox_parse "$__xsandbox_user_config" | __xsandbox_validate user | __xsandbox_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; User config: '"${__xsandbox_user_config/#${HOME}/~}"$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  if [[ -f "$project_config" ]]; then
    # Project config must be trusted. Denial exits — no base-only fallback.
    if ! __xsandbox_check_trust "$project_config"; then
      return 1
    fi
    # Every pack referenced from the project gets its own per-project
    # trust check. Denial exits — see above.
    if ! __xsandbox_check_pack_trusts "$project_config"; then
      return 1
    fi
    generated="$(__xsandbox_parse "$project_config" | __xsandbox_validate project | __xsandbox_generate)" || return 1
    if [[ -n "$generated" ]]; then
      assembled+=$'\n\n;; ============================================================'
      assembled+=$'\n;; Project config: '"${__xsandbox_config_name}"$'\n;; ============================================================'
      assembled+="$generated"
    fi
  fi

  echo "$assembled"
}
