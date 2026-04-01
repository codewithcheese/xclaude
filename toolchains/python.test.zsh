# Python (pyenv) toolchain sandbox tests
tc_setup python

tc_fixture_dir "${HOME}/.pyenv/shims"
tc_fixture_dir "${HOME}/.pyenv/versions"
tc_fixture_file "${HOME}/.pyenv/version" "3.12"

# ── Access ──
t "python: read ~/.pyenv"
expect_success "allowed" tc_sandboxed cat "${HOME}/.pyenv/version"

t "python: write ~/.pyenv/shims"
expect_success "allowed" tc_sandboxed touch "${HOME}/.pyenv/shims/test-write"
rm -f "${HOME}/.pyenv/shims/test-write"

t "python: write ~/.pyenv/versions"
expect_success "allowed" tc_sandboxed touch "${HOME}/.pyenv/versions/test-write"
rm -f "${HOME}/.pyenv/versions/test-write"

# ── Usability ──
# pyenv binary is at /opt/homebrew/bin (base profile exec)
# pyenv-managed pythons are at ~/.pyenv/versions/ (toolchain exec)

t "pyenv: pyenv --version"
expect_success "runs" tc_sandboxed pyenv --version

t "pyenv: pyenv versions"
expect_success "list" tc_sandboxed pyenv versions

# Find the pyenv-managed python — this exercises the toolchain exec rule
__pyenv_python="$(find "${HOME}/.pyenv/versions" -path "*/bin/python3" -type f 2>/dev/null | head -1)"

t "python: pyenv python --version"
expect_success "runs" tc_sandboxed "$__pyenv_python" --version

t "python: pyenv python eval"
expect_success "eval" tc_sandboxed "$__pyenv_python" -c "print('sandbox ok')"

t "python: pyenv python import stdlib"
expect_success "import" tc_sandboxed "$__pyenv_python" -c "import json; print(json.dumps({'ok': True}))"

# ── Isolation ──
t "python: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
