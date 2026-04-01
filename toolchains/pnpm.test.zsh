# pnpm toolchain sandbox tests
tc_setup pnpm

tc_fixture_dir "${HOME}/.pnpm-store/v3"
tc_fixture_dir "${HOME}/.local/share/pnpm"
tc_fixture_dir "${HOME}/.config/pnpm"
tc_fixture_file "${HOME}/.config/pnpm/rc" "store-dir=~/.pnpm-store"

# ── Access ──
t "pnpm: read ~/.pnpm-store"
tc_fixture_file "${HOME}/.pnpm-store/test-data"
expect_success "allowed" tc_sandboxed cat "${HOME}/.pnpm-store/test-data"

t "pnpm: write ~/.pnpm-store"
expect_success "allowed" tc_sandboxed touch "${HOME}/.pnpm-store/test-write"
rm -f "${HOME}/.pnpm-store/test-write"

t "pnpm: read config"
expect_success "allowed" tc_sandboxed cat "${HOME}/.config/pnpm/rc"

# ── Usability ──
__pnpm="${HOME}/.local/share/pnpm/pnpm"
if [[ ! -x "$__pnpm" ]]; then
  __pnpm="$(command -v pnpm 2>/dev/null || echo "")"
fi
if [[ -z "$__pnpm" ]]; then
  echo "SKIP: pnpm binary not found" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

t "pnpm: pnpm --version"
expect_success "runs" tc_sandboxed "$__pnpm" --version

# pnpm add
t "pnpm: pnpm add"
mkdir -p "${PROJECT_DIR}/pnpm-test"
echo '{"name":"sandbox-test","private":true}' > "${PROJECT_DIR}/pnpm-test/package.json"
expect_success "pnpm add" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/pnpm-test' && '$__pnpm' add is-odd 2>&1"

t "pnpm: node_modules created"
expect_success "exists" tc_sandboxed test -d "${PROJECT_DIR}/pnpm-test/node_modules/is-odd"

t "pnpm: pnpm-lock.yaml created"
expect_success "lockfile" tc_sandboxed test -f "${PROJECT_DIR}/pnpm-test/pnpm-lock.yaml"

rm -rf "${PROJECT_DIR}/pnpm-test"

# pnpm dlx (downloads + executes from store)
t "pnpm: pnpm dlx executes package"
expect_success "dlx" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}' && '$__pnpm' dlx semver 1.2.3 2>&1"

# ── Isolation ──
t "pnpm: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
