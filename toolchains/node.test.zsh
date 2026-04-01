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

# Find node/npm binaries installed via NVM (canonical toolchain path)
__node_bin="$(find "${HOME}/.nvm/versions" -name "node" -type f 2>/dev/null | head -1)"
if [[ -n "$__node_bin" ]]; then
  __node_dir="$(dirname "$__node_bin")"

  t "node: node executable works via NVM path"
  expect_success "usable" tc_sandboxed "$__node_bin" --version

  t "node: npm install (real package)"
  # Create a minimal project and install a small package
  mkdir -p "${PROJECT_DIR}/node-test"
  echo '{"name":"sandbox-test","private":true}' > "${PROJECT_DIR}/node-test/package.json"
  expect_success "npm install" tc_sandboxed /bin/sh -c "export PATH='${__node_dir}:$PATH' && cd '${PROJECT_DIR}/node-test' && npm install is-odd"

  t "node: installed package exists"
  expect_success "node_modules created" tc_sandboxed test -d "${PROJECT_DIR}/node-test/node_modules/is-odd"

  t "node: node can require installed package"
  expect_success "require works" tc_sandboxed "$__node_bin" -e "require('${PROJECT_DIR}/node-test/node_modules/is-odd')"

  rm -rf "${PROJECT_DIR}/node-test"
fi

t "node: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

t "node: ~/.cargo not granted"
expect_fail "isolated" tc_sandboxed cat "${HOME}/.cargo/test" 2>/dev/null

tc_cleanup
