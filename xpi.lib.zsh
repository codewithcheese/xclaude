# xpi library — compatibility wrappers over the shared sandbox library.
# Sourced by the xpi executable. No side effects on load.
#
# Requires __xpi_dir to be set by the sourcer before use.

: "${__xpi_dir:?__xpi_dir must be set before sourcing xpi.lib.zsh}"

source "${__xpi_dir}/xsandbox.lib.zsh"

__xpi_sync() {
  __xsandbox_name="xpi"
  __xsandbox_dir="${__xpi_dir}"
  __xsandbox_base_profile="${__xpi_dir}/base-pi.sb"
  __xsandbox_base_profiles=("${__xpi_dir}/base-common.sb" "${__xpi_dir}/base-pi.sb")
  __xsandbox_config_name=".xclaude"
  : "${__xpi_trust_dir:=${HOME}/.config/xpi}"
  : "${__xpi_trusted_file:=${__xpi_trust_dir}/trusted}"
  : "${__xpi_trusted_copies:=${__xpi_trust_dir}/trusted.d}"
  __xsandbox_user_config="${HOME}/.config/xpi/config"
  __xsandbox_trust_dir="${__xpi_trust_dir}"
  __xsandbox_trusted_file="${__xpi_trusted_file}"
  __xsandbox_trusted_copies="${__xpi_trusted_copies}"
  __xsandbox_packs_dir="${HOME}/.config/xclaude/packs"
}

__xpi_parse() { __xpi_sync; __xsandbox_parse "$@"; }
__xpi_validate() { __xpi_sync; __xsandbox_validate "$@"; }
__xpi_generate() { __xpi_sync; __xsandbox_generate "$@"; }
__xpi_path_to_sbpl() { __xpi_sync; __xsandbox_path_to_sbpl "$@"; }
__xpi_file_hash() { __xpi_sync; __xsandbox_file_hash "$@"; }
__xpi_path_key() { __xpi_sync; __xsandbox_path_key "$@"; }
__xpi_pack_key() { __xpi_sync; __xsandbox_pack_key "$@"; }
__xpi_is_trusted() { __xpi_sync; __xsandbox_is_trusted "$@"; }
__xpi_was_previously_trusted() { __xpi_sync; __xsandbox_was_previously_trusted "$@"; }
__xpi_trust() { __xpi_sync; __xsandbox_trust "$@"; }
__xpi_check_trust() { __xpi_sync; __xsandbox_check_trust "$@"; }
__xpi_is_pack_trusted_for_project() { __xpi_sync; __xsandbox_is_pack_trusted_for_project "$@"; }
__xpi_was_pack_previously_trusted_for_project() { __xpi_sync; __xsandbox_was_pack_previously_trusted_for_project "$@"; }
__xpi_trust_pack_for_project() { __xpi_sync; __xsandbox_trust_pack_for_project "$@"; }
__xpi_check_pack_trust() { __xpi_sync; __xsandbox_check_pack_trust "$@"; }
__xpi_check_pack_trusts() { __xpi_sync; __xsandbox_check_pack_trusts "$@"; }
__xpi_assemble() { __xpi_sync; __xsandbox_assemble "$@"; }
