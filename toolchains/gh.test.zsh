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

t "gh: gh --version"
expect_success "runs" tc_sandboxed gh --version

t "gh: gh help"
expect_success "help" tc_sandboxed gh help

# ── Isolation ──
t "gh: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
