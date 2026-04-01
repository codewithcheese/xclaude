# Python (pyenv) toolchain sandbox tests
tc_setup python

tc_fixture_dir "${HOME}/.pyenv/shims"
tc_fixture_dir "${HOME}/.pyenv/versions"
tc_fixture_file "${HOME}/.pyenv/version" "3.12.0"

t "python: read ~/.pyenv"
expect_success "allowed" tc_sandboxed cat "${HOME}/.pyenv/version"

t "python: write ~/.pyenv/shims"
expect_success "allowed" tc_sandboxed touch "${HOME}/.pyenv/shims/test-write"
rm -f "${HOME}/.pyenv/shims/test-write"

t "python: write ~/.pyenv/versions"
expect_success "allowed" tc_sandboxed touch "${HOME}/.pyenv/versions/test-write"
rm -f "${HOME}/.pyenv/versions/test-write"

if tc_has_cmd pyenv; then
  t "python: pyenv executable works"
  expect_success "usable" tc_sandboxed pyenv --version
fi

t "python: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
