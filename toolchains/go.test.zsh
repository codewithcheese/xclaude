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

if tc_has_cmd go; then
  t "go: go executable works"
  expect_success "usable" tc_sandboxed go version
fi

t "go: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
