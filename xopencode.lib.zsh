# xopencode library — compatibility wrappers over the shared sandbox library.
# Sourced by the xopencode executable and tests. No side effects on load.
#
# Requires __xopencode_dir to be set by the sourcer before use.

: "${__xopencode_dir:?__xopencode_dir must be set before sourcing xopencode.lib.zsh}"

source "${__xopencode_dir}/xsandbox.lib.zsh"

__xopencode_sync() {
  __xsandbox_name="xopencode"
  __xsandbox_dir="${__xopencode_dir}"
  __xsandbox_base_profile="${__xopencode_dir}/base-opencode.sb"
  __xsandbox_base_profiles=("${__xopencode_dir}/base-common.sb" "${__xopencode_dir}/base-opencode.sb")
  __xsandbox_config_name=".xclaude"
  : "${__xopencode_trust_dir:=${HOME}/.config/xopencode}"
  : "${__xopencode_trusted_file:=${__xopencode_trust_dir}/trusted}"
  : "${__xopencode_trusted_copies:=${__xopencode_trust_dir}/trusted.d}"
  __xsandbox_user_config="${HOME}/.config/xopencode/config"
  __xsandbox_trust_dir="${__xopencode_trust_dir}"
  __xsandbox_trusted_file="${__xopencode_trusted_file}"
  __xsandbox_trusted_copies="${__xopencode_trusted_copies}"
  __xsandbox_packs_dir="${HOME}/.config/xclaude/packs"
}

__xopencode_parse() { __xopencode_sync; __xsandbox_parse "$@"; }
__xopencode_validate() { __xopencode_sync; __xsandbox_validate "$@"; }
__xopencode_generate() { __xopencode_sync; __xsandbox_generate "$@"; }
__xopencode_path_to_sbpl() { __xopencode_sync; __xsandbox_path_to_sbpl "$@"; }
__xopencode_file_hash() { __xopencode_sync; __xsandbox_file_hash "$@"; }
__xopencode_path_key() { __xopencode_sync; __xsandbox_path_key "$@"; }
__xopencode_pack_key() { __xopencode_sync; __xsandbox_pack_key "$@"; }
__xopencode_is_trusted() { __xopencode_sync; __xsandbox_is_trusted "$@"; }
__xopencode_was_previously_trusted() { __xopencode_sync; __xsandbox_was_previously_trusted "$@"; }
__xopencode_trust() { __xopencode_sync; __xsandbox_trust "$@"; }
__xopencode_check_trust() { __xopencode_sync; __xsandbox_check_trust "$@"; }
__xopencode_is_pack_trusted_for_project() { __xopencode_sync; __xsandbox_is_pack_trusted_for_project "$@"; }
__xopencode_was_pack_previously_trusted_for_project() { __xopencode_sync; __xsandbox_was_pack_previously_trusted_for_project "$@"; }
__xopencode_trust_pack_for_project() { __xopencode_sync; __xsandbox_trust_pack_for_project "$@"; }
__xopencode_check_pack_trust() { __xopencode_sync; __xsandbox_check_pack_trust "$@"; }
__xopencode_check_pack_trusts() { __xopencode_sync; __xsandbox_check_pack_trusts "$@"; }
__xopencode_assemble() { __xopencode_sync; __xsandbox_assemble "$@"; }
