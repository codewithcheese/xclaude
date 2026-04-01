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
if [[ ! -x "$__uv" ]]; then
  __uv="$(command -v uv 2>/dev/null || echo "")"
fi
if [[ -z "$__uv" ]]; then
  echo "SKIP: uv binary not found" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

__uvx="${HOME}/.local/bin/uvx"
if [[ ! -x "$__uvx" ]]; then
  __uvx="$(command -v uvx 2>/dev/null || echo "")"
fi
# uvx might not exist separately — some installs use "uv tool run" instead
if [[ -z "$__uvx" ]]; then
  __uvx="$__uv"
  __uvx_is_uv=true
else
  __uvx_is_uv=false
fi

t "uv: uv --version"
expect_success "runs" tc_sandboxed "$__uv" --version

# venv + pip install
t "uv: uv venv"
expect_success "venv" tc_sandboxed "$__uv" venv "${PROJECT_DIR}/uv-venv"

# uv venv may create python3 instead of python — find whichever exists
__uv_venv_python="${PROJECT_DIR}/uv-venv/bin/python"
if [[ ! -f "$__uv_venv_python" && ! -L "$__uv_venv_python" ]]; then
  __uv_venv_python="${PROJECT_DIR}/uv-venv/bin/python3"
fi

t "uv: uv pip install"
expect_success "pip install" tc_sandboxed "$__uv" pip install --python "$__uv_venv_python" six

t "uv: import installed package"
expect_success "import" tc_sandboxed "$__uv_venv_python" -c "import six; print(six.__version__)"

# editable install (pip install -e .)
t "uv: editable install"
mkdir -p "${PROJECT_DIR}/editable-pkg/src/mypkg"
printf '[project]\nname = "mypkg"\nversion = "0.1.0"\n\n[build-system]\nrequires = ["setuptools>=64"]\nbuild-backend = "setuptools.build_meta"\n' > "${PROJECT_DIR}/editable-pkg/pyproject.toml"
printf 'def hello():\n    return "sandbox ok"\n' > "${PROJECT_DIR}/editable-pkg/src/mypkg/__init__.py"
expect_success "pip install -e" tc_sandboxed "$__uv" pip install --python "$__uv_venv_python" -e "${PROJECT_DIR}/editable-pkg"

t "uv: import editable package"
expect_success "import editable" tc_sandboxed "$__uv_venv_python" -c "from mypkg import hello; print(hello())"

rm -rf "${PROJECT_DIR}/uv-venv" "${PROJECT_DIR}/editable-pkg"

# uvx (run without installing)
t "uv: uvx runs package"
if $__uvx_is_uv; then
  expect_success "uvx" tc_sandboxed "$__uvx" tool run ruff version
else
  expect_success "uvx" tc_sandboxed "$__uvx" ruff version
fi

# uv tool install — redirect bin symlinks to a safe directory
# (not ~/.local/bin, which would allow overwriting any binary)
__uv_tool_bin="${HOME}/.local/share/uv/bin"

t "uv: uv tool install"
expect_success "tool install" tc_sandboxed /bin/sh -c "UV_TOOL_BIN_DIR='${__uv_tool_bin}' '${__uv}' tool install ruff 2>&1"

t "uv: tool symlink in ~/.local/share/uv/bin"
expect_success "tool binary" tc_sandboxed test -f "${__uv_tool_bin}/ruff"

t "uv: installed tool runs"
expect_success "tool runs" tc_sandboxed "${__uv_tool_bin}/ruff" version

t "uv: ~/.local/bin NOT writable (security: prevents RCE via binary overwrite)"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.local/bin/test-write"

# clean up tool
tc_sandboxed /bin/sh -c "UV_TOOL_BIN_DIR='${__uv_tool_bin}' '${__uv}' tool uninstall ruff 2>&1" 2>/dev/null || true

# uv init
t "uv: uv init"
expect_success "init" tc_sandboxed "$__uv" init "${PROJECT_DIR}/uv-proj"
expect_success "pyproject.toml" tc_sandboxed test -f "${PROJECT_DIR}/uv-proj/pyproject.toml"
rm -rf "${PROJECT_DIR}/uv-proj"

# ── Isolation ──
t "uv: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
