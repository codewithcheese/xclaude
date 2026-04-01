# GitHub CLI toolchain sandbox tests
tc_setup gh

tc_fixture_dir "${HOME}/.config/gh"
# Don't write a hosts.yml with fake tokens — gh validates them on startup.
# The read test uses a simple config file instead.
tc_fixture_file "${HOME}/.config/gh/test-config" "fixture-data"

# ── Access ──
t "gh: read ~/.config/gh"
expect_success "allowed" tc_sandboxed cat "${HOME}/.config/gh/test-config"

t "gh: ~/.config/gh not writable (read-only toolchain)"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.config/gh/test-write"

# ── Usability ──
# gh is installed via homebrew — exec via /opt/homebrew (base profile)
# The gh toolchain grants read access to auth config, not exec.
# Use GH_CONFIG_DIR to avoid reading real config that may trigger API calls.
__gh_bin="$(command -v gh 2>/dev/null || echo "")"
if [[ -z "$__gh_bin" ]]; then
  echo "SKIP: gh binary not found in PATH" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

# Point gh at an empty config dir so it doesn't try to validate tokens
__gh_empty_config="${PROJECT_DIR}/.gh-test-config"
/bin/mkdir -p "$__gh_empty_config"

t "gh: gh --version"
expect_success "runs" tc_sandboxed /bin/sh -c "GH_CONFIG_DIR='${__gh_empty_config}' '${__gh_bin}' --version"

t "gh: gh help"
expect_success "help" tc_sandboxed /bin/sh -c "GH_CONFIG_DIR='${__gh_empty_config}' '${__gh_bin}' help"

rm -rf "$__gh_empty_config"

# ── Isolation ──
t "gh: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
