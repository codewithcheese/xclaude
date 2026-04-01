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
# pnpm standalone installs to ~/.local/share/pnpm, homebrew to /opt/homebrew/bin
__pnpm_bin="${HOME}/.local/share/pnpm/pnpm"
[[ -x "$__pnpm_bin" ]] || __pnpm_bin="$(command -v pnpm 2>/dev/null)"

t "pnpm: pnpm --version"
expect_success "runs" tc_sandboxed "$__pnpm_bin" --version

t "pnpm: pnpm install (small package)"
mkdir -p "${PROJECT_DIR}/pnpm-test"
echo '{"name":"sandbox-test","private":true}' > "${PROJECT_DIR}/pnpm-test/package.json"
expect_success "pnpm install" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/pnpm-test' && '$__pnpm_bin' add is-odd 2>&1"

t "pnpm: node_modules created"
expect_success "exists" tc_sandboxed test -d "${PROJECT_DIR}/pnpm-test/node_modules/is-odd"

rm -rf "${PROJECT_DIR}/pnpm-test"

# ── Isolation ──
t "pnpm: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
