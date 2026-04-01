# Rust toolchain sandbox tests
tc_setup rust

tc_fixture_dir "${HOME}/.cargo/bin"
tc_fixture_dir "${HOME}/.cargo/registry"
tc_fixture_dir "${HOME}/.cargo/git"
tc_fixture_file "${HOME}/.cargo/env"
tc_fixture_dir "${HOME}/.rustup/toolchains"

# ── Access ──
t "rust: read ~/.cargo"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cargo/env"

t "rust: read ~/.rustup"
tc_fixture_file "${HOME}/.rustup/settings.toml"
expect_success "allowed" tc_sandboxed cat "${HOME}/.rustup/settings.toml"

t "rust: write ~/.cargo/registry"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cargo/registry/test-write"
rm -f "${HOME}/.cargo/registry/test-write"

# ── Usability ──
__cargo="${HOME}/.cargo/bin/cargo"

t "rust: cargo --version"
expect_success "runs" tc_sandboxed "$__cargo" --version

t "rust: rustc --version"
expect_success "runs" tc_sandboxed "${HOME}/.cargo/bin/rustc" --version

# cargo init + build
t "rust: cargo init"
expect_success "cargo init" tc_sandboxed "$__cargo" init "${PROJECT_DIR}/rust-test"

t "rust: cargo build"
expect_success "cargo build" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/rust-test' && '${__cargo}' build 2>&1"

t "rust: compiled binary exists"
expect_success "binary" tc_sandboxed test -f "${PROJECT_DIR}/rust-test/target/debug/rust-test"

rm -rf "${PROJECT_DIR}/rust-test"

# cargo install (installs binary to ~/.cargo/bin)
t "rust: cargo install"
expect_success "cargo install" tc_sandboxed "$__cargo" install du-dust

t "rust: installed binary in ~/.cargo/bin"
expect_success "binary" tc_sandboxed test -f "${HOME}/.cargo/bin/dust"

t "rust: installed binary runs"
expect_success "runs" tc_sandboxed "${HOME}/.cargo/bin/dust" --version

# ── Isolation ──
t "rust: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
