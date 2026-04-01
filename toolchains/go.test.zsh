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

  t "go: go mod init"
  mkdir -p "${PROJECT_DIR}/go-test-proj"
  expect_success "go mod init" tc_sandboxed /usr/local/go/bin/go mod init sandbox-test -C "${PROJECT_DIR}/go-test-proj"
  expect_success "go.mod created" tc_sandboxed test -f "${PROJECT_DIR}/go-test-proj/go.mod"

  t "go: go build"
  printf 'package main\nimport "fmt"\nfunc main() { fmt.Println("sandbox ok") }\n' > "${PROJECT_DIR}/go-test-proj/main.go"
  expect_success "go build" tc_sandboxed /usr/local/go/bin/go build -C "${PROJECT_DIR}/go-test-proj" -o "${PROJECT_DIR}/go-test-proj/test-bin"

  t "go: compiled binary runs"
  expect_success "binary runs" tc_sandboxed "${PROJECT_DIR}/go-test-proj/test-bin"

  rm -rf "${PROJECT_DIR}/go-test-proj"
fi

t "go: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
