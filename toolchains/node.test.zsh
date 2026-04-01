# Node.js toolchain (node, npm, npx) sandbox tests
tc_setup node

tc_fixture_dir "${HOME}/.nvm/versions/node"
tc_fixture_file "${HOME}/.nvm/default-packages"
tc_fixture_dir "${HOME}/.npm/_cacache"

# ── Access ──
t "node: read ~/.nvm"
expect_success "allowed" tc_sandboxed cat "${HOME}/.nvm/default-packages"

t "node: write ~/.npm"
expect_success "allowed" tc_sandboxed touch "${HOME}/.npm/test-write"
rm -f "${HOME}/.npm/test-write"

t "node: ~/.nvm not writable (read-only)"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.nvm/test-write"

# ── Usability ──
# Find node binary: try nvm versions first, then fall back to PATH
__node_bin="$(find "${HOME}/.nvm/versions" -name "node" \( -type f -o -type l \) 2>/dev/null | head -1)"
if [[ -z "$__node_bin" ]]; then
  __node_bin="$(command -v node 2>/dev/null || echo "")"
fi
if [[ -z "$__node_bin" ]]; then
  echo "SKIP: node binary not found" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi
__node_dir="$(dirname "$__node_bin")"
# Resolve npm/npx full paths for use inside sandbox-exec
__npm_bin="${__node_dir}/npm"
[[ -x "$__npm_bin" ]] || __npm_bin="$(command -v npm 2>/dev/null || echo "${__node_dir}/npm")"
__npx_bin="${__node_dir}/npx"
[[ -x "$__npx_bin" ]] || __npx_bin="$(command -v npx 2>/dev/null || echo "${__node_dir}/npx")"

t "node: node --version"
expect_success "runs" tc_sandboxed "$__node_bin" --version

# npm install
t "node: npm install"
mkdir -p "${PROJECT_DIR}/node-test"
echo '{"name":"sandbox-test","private":true}' > "${PROJECT_DIR}/node-test/package.json"
expect_success "npm install" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/node-test' && '${__npm_bin}' install is-odd --prefer-offline 2>&1"

t "node: node_modules created"
expect_success "exists" tc_sandboxed test -d "${PROJECT_DIR}/node-test/node_modules/is-odd"

t "node: node require installed package"
expect_success "require" tc_sandboxed "$__node_bin" -e "require('${PROJECT_DIR}/node-test/node_modules/is-odd')"

rm -rf "${PROJECT_DIR}/node-test"

# npx (downloads + executes from ~/.npm/_npx/)
t "node: npx executes package"
expect_success "npx" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}' && '${__npx_bin}' --yes is-odd 3 2>&1"

# node eval
t "node: node eval"
expect_success "eval" tc_sandboxed "$__node_bin" -e "console.log(JSON.stringify({ok:true}))"

# node http (exercises network from sandbox)
t "node: node http request"
expect_success "http" tc_sandboxed "$__node_bin" -e "require('https').get('https://httpbin.org/get',r=>{r.on('data',()=>{});r.on('end',()=>console.log('ok'))})"

# ── Isolation ──
t "node: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

t "node: ~/.cargo not granted"
expect_fail "isolated" tc_sandboxed cat "${HOME}/.cargo/test" 2>/dev/null

tc_cleanup
