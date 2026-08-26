# xomp library — compatibility wrappers over the shared sandbox library.
# Sourced by the xomp executable. No side effects on load.
#
# Requires __xomp_dir to be set by the sourcer before use.

: "${__xomp_dir:?__xomp_dir must be set before sourcing xomp.lib.zsh}"

source "${__xomp_dir}/xsandbox.lib.zsh"

__xomp_sync() {
  __xsandbox_name="xomp"
  __xsandbox_dir="${__xomp_dir}"
  __xsandbox_base_profile="${__xomp_dir}/base-omp.sb"
  __xsandbox_base_profiles=("${__xomp_dir}/base-common.sb" "${__xomp_dir}/base-omp.sb")
  __xsandbox_config_name=".xclaude"
  : "${__xomp_trust_dir:=${HOME}/.config/xomp}"
  : "${__xomp_trusted_file:=${__xomp_trust_dir}/trusted}"
  : "${__xomp_trusted_copies:=${__xomp_trust_dir}/trusted.d}"
  __xsandbox_user_config="${HOME}/.config/xomp/config"
  __xsandbox_trust_dir="${__xomp_trust_dir}"
  __xsandbox_trusted_file="${__xomp_trusted_file}"
  __xsandbox_trusted_copies="${__xomp_trusted_copies}"
  __xsandbox_packs_dir="${HOME}/.config/xclaude/packs"
}

__xomp_parse() { __xomp_sync; __xsandbox_parse "$@"; }
__xomp_validate() { __xomp_sync; __xsandbox_validate "$@"; }
__xomp_generate() { __xomp_sync; __xsandbox_generate "$@"; }
__xomp_path_to_sbpl() { __xomp_sync; __xsandbox_path_to_sbpl "$@"; }
__xomp_file_hash() { __xomp_sync; __xsandbox_file_hash "$@"; }
__xomp_path_key() { __xomp_sync; __xsandbox_path_key "$@"; }
__xomp_pack_key() { __xomp_sync; __xsandbox_pack_key "$@"; }
__xomp_is_trusted() { __xomp_sync; __xsandbox_is_trusted "$@"; }
__xomp_was_previously_trusted() { __xomp_sync; __xsandbox_was_previously_trusted "$@"; }
__xomp_trust() { __xomp_sync; __xsandbox_trust "$@"; }
__xomp_check_trust() { __xomp_sync; __xsandbox_check_trust "$@"; }
__xomp_is_pack_trusted_for_project() { __xomp_sync; __xsandbox_is_pack_trusted_for_project "$@"; }
__xomp_was_pack_previously_trusted_for_project() { __xomp_sync; __xsandbox_was_pack_previously_trusted_for_project "$@"; }
__xomp_trust_pack_for_project() { __xomp_sync; __xsandbox_trust_pack_for_project "$@"; }
__xomp_check_pack_trust() { __xomp_sync; __xsandbox_check_pack_trust "$@"; }
__xomp_check_pack_trusts() { __xomp_sync; __xsandbox_check_pack_trusts "$@"; }
__xomp_assemble() { __xomp_sync; __xsandbox_assemble "$@"; }
