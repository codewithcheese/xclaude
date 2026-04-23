# xclaude library — compatibility wrappers over the shared sandbox library.
# Sourced by the xclaude executable and by tests. No side effects on load.
#
# Requires __xclaude_dir to be set by the sourcer before use.

: "${__xclaude_dir:?__xclaude_dir must be set before sourcing xclaude.lib.zsh}"

source "${__xclaude_dir}/xsandbox.lib.zsh"

__xclaude_sync() {
  __xsandbox_name="xclaude"
  __xsandbox_dir="${__xclaude_dir}"
  __xsandbox_base_profile="${__xclaude_dir}/base.sb"
  __xsandbox_base_profiles=("${__xclaude_dir}/base-common.sb" "${__xclaude_dir}/base.sb")
  __xsandbox_config_name=".xclaude"
  : "${__xclaude_trust_dir:=${HOME}/.config/xclaude}"
  : "${__xclaude_trusted_file:=${__xclaude_trust_dir}/trusted}"
  : "${__xclaude_trusted_copies:=${__xclaude_trust_dir}/trusted.d}"
  __xsandbox_user_config="${HOME}/.config/xclaude/config"
  __xsandbox_trust_dir="${__xclaude_trust_dir}"
  __xsandbox_trusted_file="${__xclaude_trusted_file}"
  __xsandbox_trusted_copies="${__xclaude_trusted_copies}"
  __xsandbox_packs_dir="${HOME}/.config/xclaude/packs"
}

__xclaude_parse() { __xclaude_sync; __xsandbox_parse "$@"; }
__xclaude_validate() { __xclaude_sync; __xsandbox_validate "$@"; }
__xclaude_generate() { __xclaude_sync; __xsandbox_generate "$@"; }
__xclaude_path_to_sbpl() { __xclaude_sync; __xsandbox_path_to_sbpl "$@"; }
__xclaude_file_hash() { __xclaude_sync; __xsandbox_file_hash "$@"; }
__xclaude_path_key() { __xclaude_sync; __xsandbox_path_key "$@"; }
__xclaude_pack_key() { __xclaude_sync; __xsandbox_pack_key "$@"; }
__xclaude_is_trusted() { __xclaude_sync; __xsandbox_is_trusted "$@"; }
__xclaude_was_previously_trusted() { __xclaude_sync; __xsandbox_was_previously_trusted "$@"; }
__xclaude_trust() { __xclaude_sync; __xsandbox_trust "$@"; }
__xclaude_check_trust() { __xclaude_sync; __xsandbox_check_trust "$@"; }
__xclaude_is_pack_trusted_for_project() { __xclaude_sync; __xsandbox_is_pack_trusted_for_project "$@"; }
__xclaude_was_pack_previously_trusted_for_project() { __xclaude_sync; __xsandbox_was_pack_previously_trusted_for_project "$@"; }
__xclaude_trust_pack_for_project() { __xclaude_sync; __xsandbox_trust_pack_for_project "$@"; }
__xclaude_check_pack_trust() { __xclaude_sync; __xsandbox_check_pack_trust "$@"; }
__xclaude_check_pack_trusts() { __xclaude_sync; __xsandbox_check_pack_trusts "$@"; }
__xclaude_assemble() { __xclaude_sync; __xsandbox_assemble "$@"; }
