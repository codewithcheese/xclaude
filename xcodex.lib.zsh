# xcodex library — compatibility wrappers over the shared sandbox library.
# Sourced by the xcodex executable. No side effects on load.
#
# Requires __xcodex_dir to be set by the sourcer before use.

: "${__xcodex_dir:?__xcodex_dir must be set before sourcing xcodex.lib.zsh}"

source "${__xcodex_dir}/xsandbox.lib.zsh"

__xcodex_sync() {
  __xsandbox_name="xcodex"
  __xsandbox_dir="${__xcodex_dir}"
  __xsandbox_base_profile="${__xcodex_dir}/base-codex.sb"
  __xsandbox_base_profiles=("${__xcodex_dir}/base-common.sb" "${__xcodex_dir}/base-codex.sb")
  __xsandbox_config_name=".xcodex"
  : "${__xcodex_trust_dir:=${HOME}/.config/xcodex}"
  : "${__xcodex_trusted_file:=${__xcodex_trust_dir}/trusted}"
  : "${__xcodex_trusted_copies:=${__xcodex_trust_dir}/trusted.d}"
  __xsandbox_user_config="${HOME}/.config/xcodex/config"
  __xsandbox_trust_dir="${__xcodex_trust_dir}"
  __xsandbox_trusted_file="${__xcodex_trusted_file}"
  __xsandbox_trusted_copies="${__xcodex_trusted_copies}"
}

__xcodex_parse() { __xcodex_sync; __xsandbox_parse "$@"; }
__xcodex_validate() { __xcodex_sync; __xsandbox_validate "$@"; }
__xcodex_generate() { __xcodex_sync; __xsandbox_generate "$@"; }
__xcodex_path_to_sbpl() { __xcodex_sync; __xsandbox_path_to_sbpl "$@"; }
__xcodex_file_hash() { __xcodex_sync; __xsandbox_file_hash "$@"; }
__xcodex_path_key() { __xcodex_sync; __xsandbox_path_key "$@"; }
__xcodex_is_trusted() { __xcodex_sync; __xsandbox_is_trusted "$@"; }
__xcodex_was_previously_trusted() { __xcodex_sync; __xsandbox_was_previously_trusted "$@"; }
__xcodex_trust() { __xcodex_sync; __xsandbox_trust "$@"; }
__xcodex_check_trust() { __xcodex_sync; __xsandbox_check_trust "$@"; }
__xcodex_assemble() { __xcodex_sync; __xsandbox_assemble "$@"; }
