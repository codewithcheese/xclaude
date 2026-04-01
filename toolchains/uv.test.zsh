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

if tc_has_cmd uv; then
  t "uv: uv executable works"
  expect_success "usable" tc_sandboxed uv --version
fi

t "uv: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
