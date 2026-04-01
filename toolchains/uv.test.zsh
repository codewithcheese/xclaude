# Python uv toolchain sandbox tests
tc_setup uv

tc_fixture_dir "${HOME}/.cache/uv"
tc_fixture_dir "${HOME}/.local/share/uv"
tc_fixture_file "${HOME}/.cache/uv/test-data"

# ── Access ──
t "uv: read ~/.cache/uv"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cache/uv/test-data"

t "uv: write ~/.cache/uv"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/uv/test-write"
rm -f "${HOME}/.cache/uv/test-write"

t "uv: write ~/.local/share/uv"
expect_success "allowed" tc_sandboxed touch "${HOME}/.local/share/uv/test-write"
rm -f "${HOME}/.local/share/uv/test-write"

# ── Usability ──
__uv_bin="${HOME}/.local/bin/uv"

t "uv: uv --version"
expect_success "runs" tc_sandboxed "$__uv_bin" --version

t "uv: uv venv"
expect_success "uv venv" tc_sandboxed "$__uv_bin" venv "${PROJECT_DIR}/uv-test-venv"

t "uv: uv pip install (small package)"
expect_success "pip install" tc_sandboxed "$__uv_bin" pip install --python "${PROJECT_DIR}/uv-test-venv/bin/python" six

t "uv: import installed package"
expect_success "import" tc_sandboxed "${PROJECT_DIR}/uv-test-venv/bin/python" -c "import six; print(six.__version__)"

rm -rf "${PROJECT_DIR}/uv-test-venv"

t "uv: uv init"
expect_success "uv init" tc_sandboxed "$__uv_bin" init "${PROJECT_DIR}/uv-test-proj"
expect_success "pyproject.toml" tc_sandboxed test -f "${PROJECT_DIR}/uv-test-proj/pyproject.toml"

rm -rf "${PROJECT_DIR}/uv-test-proj"

# ── Isolation ──
t "uv: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
