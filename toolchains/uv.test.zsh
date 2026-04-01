# Python uv toolchain sandbox tests
tc_setup uv

tc_fixture_dir "${HOME}/.cache/uv"
tc_fixture_dir "${HOME}/Library/Caches/uv"
tc_fixture_dir "${HOME}/.local/share/uv"

# ── Access ──
t "uv: write ~/Library/Caches/uv (macOS cache)"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/Caches/uv/test-write"
rm -f "${HOME}/Library/Caches/uv/test-write"

t "uv: write ~/.local/share/uv"
expect_success "allowed" tc_sandboxed touch "${HOME}/.local/share/uv/test-write"
rm -f "${HOME}/.local/share/uv/test-write"

# ── Usability ──
__uv="${HOME}/.local/bin/uv"
__uvx="${HOME}/.local/bin/uvx"

t "uv: uv --version"
expect_success "runs" tc_sandboxed "$__uv" --version

# venv + pip install
t "uv: uv venv"
expect_success "venv" tc_sandboxed "$__uv" venv "${PROJECT_DIR}/uv-venv"

t "uv: uv pip install"
expect_success "pip install" tc_sandboxed "$__uv" pip install --python "${PROJECT_DIR}/uv-venv/bin/python" six

t "uv: import installed package"
expect_success "import" tc_sandboxed "${PROJECT_DIR}/uv-venv/bin/python" -c "import six; print(six.__version__)"

# editable install (pip install -e .)
t "uv: editable install"
mkdir -p "${PROJECT_DIR}/editable-pkg/src/mypkg"
printf '[project]\nname = "mypkg"\nversion = "0.1.0"\n\n[build-system]\nrequires = ["setuptools"]\nbuild-backend = "setuptools.backends._legacy:_Backend"\n' > "${PROJECT_DIR}/editable-pkg/pyproject.toml"
printf 'def hello():\n    return "sandbox ok"\n' > "${PROJECT_DIR}/editable-pkg/src/mypkg/__init__.py"
expect_success "pip install -e" tc_sandboxed "$__uv" pip install --python "${PROJECT_DIR}/uv-venv/bin/python" -e "${PROJECT_DIR}/editable-pkg"

t "uv: import editable package"
expect_success "import editable" tc_sandboxed "${PROJECT_DIR}/uv-venv/bin/python" -c "from mypkg import hello; print(hello())"

rm -rf "${PROJECT_DIR}/uv-venv" "${PROJECT_DIR}/editable-pkg"

# uvx (run without installing)
t "uv: uvx runs package"
expect_success "uvx" tc_sandboxed "$__uvx" ruff version

# uv tool install (persistent tool)
t "uv: uv tool install"
expect_success "tool install" tc_sandboxed "$__uv" tool install ruff

t "uv: tool binary in ~/.local/bin"
expect_success "tool binary" tc_sandboxed test -f "${HOME}/.local/bin/ruff"

t "uv: installed tool runs"
expect_success "tool runs" tc_sandboxed "${HOME}/.local/bin/ruff" version

# clean up tool
tc_sandboxed "$__uv" tool uninstall ruff 2>/dev/null || true

# uv init
t "uv: uv init"
expect_success "init" tc_sandboxed "$__uv" init "${PROJECT_DIR}/uv-proj"
expect_success "pyproject.toml" tc_sandboxed test -f "${PROJECT_DIR}/uv-proj/pyproject.toml"
rm -rf "${PROJECT_DIR}/uv-proj"

# ── Isolation ──
t "uv: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
