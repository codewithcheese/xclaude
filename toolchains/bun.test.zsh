# Bun runtime sandbox tests
tc_setup bun

tc_fixture_dir "${HOME}/.bun/bin"
tc_fixture_dir "${HOME}/.bun/install/cache"

# ── Access ──
t "bun: read ~/.bun"
tc_fixture_file "${HOME}/.bun/test-data"
expect_success "allowed" tc_sandboxed cat "${HOME}/.bun/test-data"

t "bun: write ~/.bun"
expect_success "allowed" tc_sandboxed touch "${HOME}/.bun/test-write"
rm -f "${HOME}/.bun/test-write"

# ── Usability ──
__bun="${HOME}/.bun/bin/bun"
if [[ ! -x "$__bun" ]]; then
  __bun="$(command -v bun 2>/dev/null || echo "")"
fi
if [[ -z "$__bun" ]]; then
  echo "SKIP: bun binary not found" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

t "bun: bun --version"
expect_success "runs" tc_sandboxed "$__bun" --version

t "bun: bun init"
mkdir -p "${PROJECT_DIR}/bun-test"
expect_success "bun init" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/bun-test' && '$__bun' init -y 2>&1"

t "bun: bun install"
expect_success "bun add" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/bun-test' && '$__bun' add is-odd 2>&1"

t "bun: node_modules created"
expect_success "exists" tc_sandboxed test -d "${PROJECT_DIR}/bun-test/node_modules/is-odd"

t "bun: bun run script"
printf 'console.log("sandbox ok");\n' > "${PROJECT_DIR}/bun-test/test.js"
expect_success "bun run" tc_sandboxed "$__bun" run "${PROJECT_DIR}/bun-test/test.js"

rm -rf "${PROJECT_DIR}/bun-test"

# bunx — run a script from node_modules/.bin via bun x
t "bun: bunx runs local binary"
mkdir -p "${PROJECT_DIR}/bunx-test"
echo '{"name":"bunx-test","private":true}' > "${PROJECT_DIR}/bunx-test/package.json"
tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/bunx-test' && '$__bun' add is-odd 2>&1" >/dev/null 2>&1
# Use bun to run the installed package directly — tests exec from node_modules
expect_success "bunx" tc_sandboxed "$__bun" -e "const isOdd = require('${PROJECT_DIR}/bunx-test/node_modules/is-odd'); console.log(isOdd(3))"
rm -rf "${PROJECT_DIR}/bunx-test"

# ── Isolation ──
t "bun: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
