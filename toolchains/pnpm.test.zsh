# pnpm toolchain sandbox tests
tc_setup pnpm

tc_fixture_dir "${HOME}/.pnpm-store/v3"
tc_fixture_dir "${HOME}/.local/share/pnpm"
tc_fixture_dir "${HOME}/.config/pnpm"
tc_fixture_file "${HOME}/.config/pnpm/rc" "store-dir=~/.pnpm-store"

t "pnpm: read ~/.pnpm-store"
tc_fixture_file "${HOME}/.pnpm-store/test-data"
expect_success "allowed" tc_sandboxed cat "${HOME}/.pnpm-store/test-data"

t "pnpm: write ~/.pnpm-store"
expect_success "allowed" tc_sandboxed touch "${HOME}/.pnpm-store/test-write"
rm -f "${HOME}/.pnpm-store/test-write"

t "pnpm: read config"
expect_success "allowed" tc_sandboxed cat "${HOME}/.config/pnpm/rc"

# pnpm installed via standalone script at ~/.local/share/pnpm
if [[ -x "${HOME}/.local/share/pnpm/pnpm" ]]; then
  t "pnpm: pnpm executable works via ~/.local/share/pnpm"
  expect_success "usable" tc_sandboxed "${HOME}/.local/share/pnpm/pnpm" --version
elif tc_has_cmd pnpm; then
  # Homebrew install — exec via /opt/homebrew (base profile)
  t "pnpm: pnpm executable works"
  expect_success "usable" tc_sandboxed pnpm --version
fi

t "pnpm: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
