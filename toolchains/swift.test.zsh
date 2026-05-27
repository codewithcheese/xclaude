# Swift toolchain sandbox tests
tc_setup swift

tc_fixture_dir "${HOME}/Library/Caches/org.swift.swiftpm"
tc_fixture_dir "${HOME}/Library/org.swift.swiftpm/configuration"
tc_fixture_dir "${HOME}/Library/org.swift.swiftpm/security"
tc_fixture_file "${HOME}/Library/Caches/org.swift.swiftpm/test-data"

# ── Access ──
t "swift: read ~/Library/Caches/org.swift.swiftpm"
expect_success "allowed" tc_sandboxed cat "${HOME}/Library/Caches/org.swift.swiftpm/test-data"

t "swift: write ~/Library/Caches/org.swift.swiftpm"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/Caches/org.swift.swiftpm/test-write"
rm -f "${HOME}/Library/Caches/org.swift.swiftpm/test-write"

t "swift: write ~/Library/org.swift.swiftpm/configuration"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/org.swift.swiftpm/configuration/test-write"
rm -f "${HOME}/Library/org.swift.swiftpm/configuration/test-write"

t "swift: write ~/Library/org.swift.swiftpm/security"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/org.swift.swiftpm/security/test-write"
rm -f "${HOME}/Library/org.swift.swiftpm/security/test-write"

# ── Usability ──
__swift="$(command -v swift 2>/dev/null || echo "")"
if [[ -z "$__swift" ]]; then
  echo "SKIP: swift binary not found in PATH" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

t "swift: swift --version"
expect_success "runs" tc_sandboxed "$__swift" --version

# --disable-sandbox required throughout: macOS forbids nested sandbox-exec.
t "swift: swift package init --disable-sandbox"
mkdir -p "${PROJECT_DIR}/swift-test"
expect_success "package init" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/swift-test' && '${__swift}' package init --disable-sandbox --type executable --name SwiftTest"

t "swift: swift build --disable-sandbox"
expect_success "swift build" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/swift-test' && '${__swift}' build --disable-sandbox"

t "swift: compiled binary exists"
expect_success "binary" tc_sandboxed test -f "${PROJECT_DIR}/swift-test/.build/debug/SwiftTest"

t "swift: swift run --disable-sandbox"
expect_success "runs binary" tc_sandboxed /bin/sh -c "cd '${PROJECT_DIR}/swift-test' && '${__swift}' run --disable-sandbox SwiftTest"

rm -rf "${PROJECT_DIR}/swift-test"

# ── Isolation ──
t "swift: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
