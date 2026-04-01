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

# Cargo/rustc at canonical path ~/.cargo/bin
if [[ -x "${HOME}/.cargo/bin/cargo" ]]; then
  t "rust: cargo executable works via ~/.cargo/bin"
  expect_success "usable" tc_sandboxed "${HOME}/.cargo/bin/cargo" --version

  t "rust: cargo init project"
  expect_success "cargo init" tc_sandboxed "${HOME}/.cargo/bin/cargo" init "${PROJECT_DIR}/rust-test-proj"
  expect_success "Cargo.toml created" tc_sandboxed test -f "${PROJECT_DIR}/rust-test-proj/Cargo.toml"

  t "rust: cargo build"
  expect_success "cargo build" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/rust-test-proj' && '${HOME}/.cargo/bin/cargo' build 2>&1"

  t "rust: compiled binary exists"
  expect_success "binary exists" tc_sandboxed test -f "${PROJECT_DIR}/rust-test-proj/target/debug/rust-test-proj"

  rm -rf "${PROJECT_DIR}/rust-test-proj"
fi

t "rust: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
