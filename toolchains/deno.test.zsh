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

  t "deno: deno eval"
  expect_success "deno eval" tc_sandboxed "${HOME}/.deno/bin/deno" eval "console.log('sandbox ok')"

  t "deno: deno run script"
  printf 'const x = 1 + 2;\nconsole.log("result:", x);\n' > "${PROJECT_DIR}/deno-test.ts"
  expect_success "deno run" tc_sandboxed "${HOME}/.deno/bin/deno" run "${PROJECT_DIR}/deno-test.ts"
  rm -f "${PROJECT_DIR}/deno-test.ts"

  t "deno: deno init project"
  expect_success "deno init" tc_sandboxed "${HOME}/.deno/bin/deno" init "${PROJECT_DIR}/deno-test-proj"
  expect_success "deno.json created" tc_sandboxed test -f "${PROJECT_DIR}/deno-test-proj/deno.json"
  rm -rf "${PROJECT_DIR}/deno-test-proj"
fi

t "deno: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
