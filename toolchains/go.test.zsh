# Go toolchain sandbox tests
tc_setup go

tc_fixture_dir "${HOME}/go/bin"
tc_fixture_dir "${HOME}/go/pkg"
tc_fixture_file "${HOME}/go/test-data"
tc_fixture_dir "${HOME}/.cache/go-build"

t "go: read ~/go"
expect_success "allowed" tc_sandboxed cat "${HOME}/go/test-data"

t "go: write ~/go/pkg"
expect_success "allowed" tc_sandboxed touch "${HOME}/go/pkg/test-write"
rm -f "${HOME}/go/pkg/test-write"

t "go: write ~/.cache/go-build"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/go-build/test-write"
rm -f "${HOME}/.cache/go-build/test-write"

# Go at canonical path /usr/local/go/bin
if [[ -x "/usr/local/go/bin/go" ]]; then
  t "go: go executable works via /usr/local/go/bin"
  expect_success "usable" tc_sandboxed /usr/local/go/bin/go version
fi

t "go: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
