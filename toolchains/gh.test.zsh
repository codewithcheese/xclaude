# GitHub CLI toolchain sandbox tests
tc_setup gh

tc_fixture_dir "${HOME}/.config/gh"
tc_fixture_file "${HOME}/.config/gh/hosts.yml"

t "gh: read ~/.config/gh"
expect_success "allowed" tc_sandboxed cat "${HOME}/.config/gh/hosts.yml"

t "gh: ~/.config/gh not writable (read-only toolchain)"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.config/gh/test-write"

if tc_has_cmd gh; then
  t "gh: gh executable works"
  expect_success "usable" tc_sandboxed gh --version
fi

t "gh: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
