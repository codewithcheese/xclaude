# Deno toolchain sandbox tests
tc_setup deno

tc_fixture_dir "${HOME}/.deno/bin"
tc_fixture_file "${HOME}/.deno/test-data"

t "deno: read ~/.deno"
expect_success "allowed" tc_sandboxed cat "${HOME}/.deno/test-data"

t "deno: write ~/.deno"
expect_success "allowed" tc_sandboxed touch "${HOME}/.deno/test-write"
rm -f "${HOME}/.deno/test-write"

# Deno installs to ~/.deno/bin/deno (canonical path)
if [[ -x "${HOME}/.deno/bin/deno" ]]; then
  t "deno: deno executable works via ~/.deno/bin"
  expect_success "usable" tc_sandboxed "${HOME}/.deno/bin/deno" --version
fi

t "deno: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
