# Electron + embedded libghostty toolchain sandbox tests
tc_setup electron-ghostty

tc_fixture_dir "${HOME}/Library/Application Support/Electron"
tc_fixture_dir "${HOME}/Library/Logs/Electron"
tc_fixture_dir "${HOME}/Library/Caches/Electron"

# ── Filesystem access added by this toolchain ──
t "electron-ghostty: write ~/Library/Application Support/Electron"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/Application Support/Electron/test-write"
rm -f "${HOME}/Library/Application Support/Electron/test-write"

t "electron-ghostty: write ~/Library/Logs/Electron"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/Logs/Electron/test-write"
rm -f "${HOME}/Library/Logs/Electron/test-write"

t "electron-ghostty: write ~/Library/Caches/Electron"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/Caches/Electron/test-write"
rm -f "${HOME}/Library/Caches/Electron/test-write"

# ── pseudo-tty kernel operation ──
# pty.openpty() calls posix_openpt + grantpt + unlockpt under the hood, which
# is exactly the `pseudo-tty` operation class denied by base. Verifies our
# (allow pseudo-tty) rule is in effect.
# Prefer Homebrew Python — /usr/bin/python3 is an Apple stub that dlopens
# /Applications/Xcode.app/.../libxcrun.dylib on machines where xcode-select
# points to full Xcode, which the base profile does not (and should not)
# grant. Base only allows exec under /bin, /usr/bin, /opt/homebrew, so a
# framework Python under /Library would not be exec-able either.
__py=""
if [[ -x /opt/homebrew/bin/python3 ]]; then
  __py=/opt/homebrew/bin/python3
elif [[ -x /usr/bin/python3 ]]; then
  __py=/usr/bin/python3
fi
if [[ -n "$__py" ]]; then
  t "electron-ghostty: posix_openpt succeeds"
  expect_success "PTY allocation works" tc_sandboxed "$__py" -c \
    "import pty,os; m,s = pty.openpty(); os.close(m); os.close(s)"
fi

# ── Regression guards: things we intentionally do NOT grant ──

# Sugid exec — we picked the "configure bridge to spawn shell directly"
# path. If anyone later grants sugid exec, this test catches the regression.
if [[ -u /usr/bin/login ]]; then
  t "electron-ghostty: /usr/bin/login (setuid) stays blocked"
  expect_fail "blocked" tc_sandboxed /usr/bin/login -pf "${USER}" /bin/true
fi

# Standalone Ghostty.app is intentionally not covered by this toolchain.
if [[ -d /Applications/Ghostty.app ]]; then
  t "electron-ghostty: standalone Ghostty.app config stays blocked"
  expect_fail "blocked" tc_sandboxed cat "${HOME}/Library/Caches/com.mitchellh.ghostty/sentry/installation"
fi

t "electron-ghostty: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
