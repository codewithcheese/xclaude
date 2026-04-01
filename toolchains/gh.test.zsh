# GitHub CLI toolchain sandbox tests
tc_setup gh

tc_fixture_dir "${HOME}/.config/gh"
tc_fixture_file "${HOME}/.config/gh/hosts.yml"

# ── Access ──
t "gh: read ~/.config/gh"
expect_success "allowed" tc_sandboxed cat "${HOME}/.config/gh/hosts.yml"

t "gh: ~/.config/gh not writable (read-only toolchain)"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.config/gh/test-write"

# ── Usability ──
# gh is installed via homebrew — exec via /opt/homebrew (base profile)
# The gh toolchain grants read access to auth config, not exec.
# sandbox-exec needs the full path — bare names don't search PATH.
__gh_bin="$(command -v gh 2>/dev/null || echo "")"
if [[ -z "$__gh_bin" ]]; then
  echo "SKIP: gh binary not found in PATH" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

t "gh: gh --version"
expect_success "runs" tc_sandboxed "$__gh_bin" --version

t "gh: gh help"
expect_success "help" tc_sandboxed "$__gh_bin" help

# ── Isolation ──
t "gh: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
