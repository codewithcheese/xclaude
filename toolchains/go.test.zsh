# Go toolchain sandbox tests
tc_setup go

tc_fixture_dir "${HOME}/go/bin"
tc_fixture_dir "${HOME}/go/pkg"
tc_fixture_file "${HOME}/go/test-data"
tc_fixture_dir "${HOME}/.cache/go-build"

# ── Access ──
t "go: read ~/go"
expect_success "allowed" tc_sandboxed cat "${HOME}/go/test-data"

t "go: write ~/go/pkg"
expect_success "allowed" tc_sandboxed touch "${HOME}/go/pkg/test-write"
rm -f "${HOME}/go/pkg/test-write"

t "go: write ~/.cache/go-build"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/go-build/test-write"
rm -f "${HOME}/.cache/go-build/test-write"

# ── Usability ──
__go="/usr/local/go/bin/go"

t "go: go version"
expect_success "runs" tc_sandboxed "$__go" version

t "go: go mod init"
mkdir -p "${PROJECT_DIR}/go-test"
expect_success "mod init" tc_sandboxed "$__go" mod init sandbox-test -C "${PROJECT_DIR}/go-test"

t "go: go build"
printf 'package main\nimport "fmt"\nfunc main() { fmt.Println("sandbox ok") }\n' > "${PROJECT_DIR}/go-test/main.go"
expect_success "go build" tc_sandboxed "$__go" build -C "${PROJECT_DIR}/go-test" -o "${PROJECT_DIR}/go-test/test-bin"

t "go: run compiled binary"
expect_success "binary runs" tc_sandboxed "${PROJECT_DIR}/go-test/test-bin"

rm -rf "${PROJECT_DIR}/go-test"

# ── Isolation ──
t "go: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
