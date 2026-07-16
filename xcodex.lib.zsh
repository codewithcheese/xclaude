# xcodex library — compatibility wrappers over the shared sandbox library.
# Sourced by the xcodex executable. No side effects on load.
#
# Requires __xcodex_dir to be set by the sourcer before use.

: "${__xcodex_dir:?__xcodex_dir must be set before sourcing xcodex.lib.zsh}"

source "${__xcodex_dir}/xsandbox.lib.zsh"

# Return success when the user-level Codex config registers the Node REPL
# bundled with ChatGPT.app. xcodex uses this to disable only the REPL's nested
# Codex sandbox; the outer Seatbelt profile remains the security boundary.
__xcodex_uses_chatgpt_node_repl() {
  local codex_home="${CODEX_HOME:-${HOME}/.codex}"
  local config_file="${codex_home}/config.toml"

  [[ -r "$config_file" ]] || return 1

  /usr/bin/awk '
    /^[[:space:]]*\[[[:space:]]*mcp_servers[.]"?node_repl"?[[:space:]]*\][[:space:]]*(#.*)?$/ {
      in_node_repl = 1
      next
    }
    /^[[:space:]]*\[/ {
      in_node_repl = 0
    }
    in_node_repl && /^[[:space:]]*command[[:space:]]*=[[:space:]]*"\/Applications\/ChatGPT[.]app\/Contents\/Resources\/cua_node\/bin\/node_repl"[[:space:]]*(#.*)?$/ {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$config_file"
}

__xcodex_sync() {
  __xsandbox_name="xcodex"
  __xsandbox_dir="${__xcodex_dir}"
  __xsandbox_base_profile="${__xcodex_dir}/base-codex.sb"
  __xsandbox_base_profiles=("${__xcodex_dir}/base-common.sb" "${__xcodex_dir}/base-codex.sb")
  __xsandbox_config_name=".xclaude"
  : "${__xcodex_trust_dir:=${HOME}/.config/xcodex}"
  : "${__xcodex_trusted_file:=${__xcodex_trust_dir}/trusted}"
  : "${__xcodex_trusted_copies:=${__xcodex_trust_dir}/trusted.d}"
  __xsandbox_user_config="${HOME}/.config/xcodex/config"
  __xsandbox_trust_dir="${__xcodex_trust_dir}"
  __xsandbox_trusted_file="${__xcodex_trusted_file}"
  __xsandbox_trusted_copies="${__xcodex_trusted_copies}"
  __xsandbox_packs_dir="${HOME}/.config/xclaude/packs"
}

__xcodex_parse() { __xcodex_sync; __xsandbox_parse "$@"; }
__xcodex_validate() { __xcodex_sync; __xsandbox_validate "$@"; }
__xcodex_generate() { __xcodex_sync; __xsandbox_generate "$@"; }
__xcodex_path_to_sbpl() { __xcodex_sync; __xsandbox_path_to_sbpl "$@"; }
__xcodex_file_hash() { __xcodex_sync; __xsandbox_file_hash "$@"; }
__xcodex_path_key() { __xcodex_sync; __xsandbox_path_key "$@"; }
__xcodex_pack_key() { __xcodex_sync; __xsandbox_pack_key "$@"; }
__xcodex_is_trusted() { __xcodex_sync; __xsandbox_is_trusted "$@"; }
__xcodex_was_previously_trusted() { __xcodex_sync; __xsandbox_was_previously_trusted "$@"; }
__xcodex_trust() { __xcodex_sync; __xsandbox_trust "$@"; }
__xcodex_check_trust() { __xcodex_sync; __xsandbox_check_trust "$@"; }
__xcodex_is_pack_trusted_for_project() { __xcodex_sync; __xsandbox_is_pack_trusted_for_project "$@"; }
__xcodex_was_pack_previously_trusted_for_project() { __xcodex_sync; __xsandbox_was_pack_previously_trusted_for_project "$@"; }
__xcodex_trust_pack_for_project() { __xcodex_sync; __xsandbox_trust_pack_for_project "$@"; }
__xcodex_check_pack_trust() { __xcodex_sync; __xsandbox_check_pack_trust "$@"; }
__xcodex_check_pack_trusts() { __xcodex_sync; __xsandbox_check_pack_trusts "$@"; }
__xcodex_assemble() { __xcodex_sync; __xsandbox_assemble "$@"; }
