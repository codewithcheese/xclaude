# Node.js / npm toolchain sandbox tests
tc_setup node

tc_fixture_dir "${HOME}/.nvm/versions/node"
tc_fixture_file "${HOME}/.nvm/default-packages"
tc_fixture_dir "${HOME}/.npm/_cacache"

t "node: read ~/.nvm"
expect_success "allowed" tc_sandboxed cat "${HOME}/.nvm/default-packages"

t "node: write ~/.npm"
expect_success "allowed" tc_sandboxed touch "${HOME}/.npm/test-write"
rm -f "${HOME}/.npm/test-write"

t "node: ~/.nvm not writable (read-only)"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.nvm/test-write"

if tc_has_cmd node; then
  t "node: node executable works"
  expect_success "usable" tc_sandboxed node --version

  t "node: npm executable works"
  expect_success "usable" tc_sandboxed npm --version
fi

t "node: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

t "node: ~/.cargo not granted"
expect_fail "isolated" tc_sandboxed cat "${HOME}/.cargo/test" 2>/dev/null

tc_cleanup
