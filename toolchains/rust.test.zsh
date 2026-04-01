# Rust toolchain sandbox tests
tc_setup rust

tc_fixture_dir "${HOME}/.cargo/bin"
tc_fixture_dir "${HOME}/.cargo/registry"
tc_fixture_dir "${HOME}/.cargo/git"
tc_fixture_file "${HOME}/.cargo/env"
tc_fixture_dir "${HOME}/.rustup/toolchains"

t "rust: read ~/.cargo"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cargo/env"

t "rust: read ~/.rustup"
tc_fixture_file "${HOME}/.rustup/settings.toml"
expect_success "allowed" tc_sandboxed cat "${HOME}/.rustup/settings.toml"

t "rust: write ~/.cargo/registry"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cargo/registry/test-write"
rm -f "${HOME}/.cargo/registry/test-write"

t "rust: write ~/.cargo/git"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cargo/git/test-write"
rm -f "${HOME}/.cargo/git/test-write"

if tc_has_cmd cargo; then
  t "rust: cargo executable works"
  expect_success "usable" tc_sandboxed cargo --version

  t "rust: rustc executable works"
  expect_success "usable" tc_sandboxed rustc --version
fi

t "rust: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
