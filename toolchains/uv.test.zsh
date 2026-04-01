# Python uv toolchain sandbox tests
tc_setup uv

tc_fixture_dir "${HOME}/.cache/uv"
tc_fixture_dir "${HOME}/.local/share/uv"
tc_fixture_file "${HOME}/.cache/uv/test-data"

t "uv: read ~/.cache/uv"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cache/uv/test-data"

t "uv: write ~/.cache/uv"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/uv/test-write"
rm -f "${HOME}/.cache/uv/test-write"

t "uv: write ~/.local/share/uv"
expect_success "allowed" tc_sandboxed touch "${HOME}/.local/share/uv/test-write"
rm -f "${HOME}/.local/share/uv/test-write"

# uv installs to ~/.local/bin/uv (canonical path)
if [[ -x "${HOME}/.local/bin/uv" ]]; then
  t "uv: uv executable works via ~/.local/bin"
  expect_success "usable" tc_sandboxed "${HOME}/.local/bin/uv" --version

  t "uv: uv pip install (real package)"
  # Create a venv and install a small package
  expect_success "uv venv" tc_sandboxed "${HOME}/.local/bin/uv" venv "${PROJECT_DIR}/uv-test-venv"
  expect_success "uv pip install" tc_sandboxed "${HOME}/.local/bin/uv" pip install --python "${PROJECT_DIR}/uv-test-venv/bin/python" six

  t "uv: installed package importable"
  expect_success "import works" tc_sandboxed "${PROJECT_DIR}/uv-test-venv/bin/python" -c "import six; print(six.__version__)"

  rm -rf "${PROJECT_DIR}/uv-test-venv"

  t "uv: uv init project"
  expect_success "uv init" tc_sandboxed "${HOME}/.local/bin/uv" init "${PROJECT_DIR}/uv-test-proj"
  expect_success "pyproject.toml created" tc_sandboxed test -f "${PROJECT_DIR}/uv-test-proj/pyproject.toml"

  rm -rf "${PROJECT_DIR}/uv-test-proj"
fi

t "uv: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
