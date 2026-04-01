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
if [[ ! -x "$__cargo" ]]; then
  __cargo="$(command -v cargo 2>/dev/null || echo "")"
fi
if [[ -z "$__cargo" ]]; then
  echo "SKIP: cargo binary not found" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

t "rust: cargo --version"
expect_success "runs" tc_sandboxed "$__cargo" --version

__rustc="${HOME}/.cargo/bin/rustc"
if [[ ! -x "$__rustc" ]]; then
  __rustc="$(command -v rustc 2>/dev/null || echo "${HOME}/.cargo/bin/rustc")"
fi

t "rust: rustc --version"
expect_success "runs" tc_sandboxed "$__rustc" --version

# cargo init + build
t "rust: cargo init"
expect_success "cargo init" tc_sandboxed "$__cargo" init "${PROJECT_DIR}/rust-test"

t "rust: cargo build"
expect_success "cargo build" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/rust-test' && '${__cargo}' build 2>&1"

t "rust: compiled binary exists"
expect_success "binary" tc_sandboxed test -f "${PROJECT_DIR}/rust-test/target/debug/rust-test"

rm -rf "${PROJECT_DIR}/rust-test"

# cargo install (installs binary to ~/.cargo/bin)
# Use a lightweight crate to avoid compile timeouts in CI (du-dust is too heavy)
t "rust: cargo install"
expect_success "cargo install" tc_sandboxed "$__cargo" install names

t "rust: installed binary in ~/.cargo/bin"
expect_success "binary" tc_sandboxed test -f "${HOME}/.cargo/bin/names"

t "rust: installed binary runs"
expect_success "runs" tc_sandboxed "${HOME}/.cargo/bin/names" --help

# ── Isolation ──
t "rust: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
