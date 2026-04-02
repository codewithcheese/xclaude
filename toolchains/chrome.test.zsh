# Google Chrome toolchain sandbox tests
tc_setup chrome

tc_fixture_dir "${HOME}/Library/Application Support/Google/Chrome"
tc_fixture_dir "${HOME}/Library/Google"
tc_fixture_dir "${HOME}/Library/Input Methods"
tc_fixture_dir "${HOME}/Library/Keyboard Layouts"
tc_fixture_dir "${HOME}/Library/Spelling"

# ── Access ──
t "chrome: read /Applications/Google Chrome.app"
expect_success "allowed" tc_sandboxed test -d "/Applications/Google Chrome.app"

t "chrome: read ~/Library/Application Support/Google/Chrome"
tc_fixture_file "${HOME}/Library/Application Support/Google/Chrome/test-data"
expect_success "allowed" tc_sandboxed cat "${HOME}/Library/Application Support/Google/Chrome/test-data"

t "chrome: write ~/Library/Application Support/Google/Chrome"
expect_success "allowed" tc_sandboxed touch "${HOME}/Library/Application Support/Google/Chrome/test-write"
rm -f "${HOME}/Library/Application Support/Google/Chrome/test-write"

t "chrome: read ~/Library/Google"
tc_fixture_file "${HOME}/Library/Google/test-data"
expect_success "allowed" tc_sandboxed cat "${HOME}/Library/Google/test-data"

# ── Usability ──
__chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [[ ! -x "$__chrome" ]]; then
  echo "SKIP: Google Chrome not found at ${__chrome}" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

# Pick a random high port to avoid conflicts
__debug_port=$((9300 + RANDOM % 100))
__profile_dir="${PROJECT_DIR}/chrome-test-profile"

t "chrome: launch headless with remote debugging"
# --no-sandbox disables Chrome's internal sandbox which can't nest inside Seatbelt
tc_sandboxed "$__chrome" \
  --headless=new \
  --remote-debugging-port=${__debug_port} \
  --user-data-dir="${__profile_dir}" \
  --no-first-run \
  --no-default-browser-check \
  --no-sandbox \
  --disable-gpu \
  about:blank &
__chrome_pid=$!

# Wait for Chrome to start and open the debugging port
__attempts=0
__chrome_ready=false
while [[ $__attempts -lt 20 ]]; do
  if /usr/bin/curl -s "http://localhost:${__debug_port}/json/version" >/dev/null 2>&1; then
    __chrome_ready=true
    break
  fi
  sleep 0.5
  __attempts=$((__attempts + 1))
done

if $__chrome_ready; then
  expect_success "chrome started" true

  t "chrome: CDP endpoint responds"
  expect_success "CDP" /usr/bin/curl -s "http://localhost:${__debug_port}/json/version"

  t "chrome: CDP lists targets"
  expect_success "targets" /usr/bin/curl -s "http://localhost:${__debug_port}/json/list"
else
  expect_success "chrome started (timed out waiting for CDP)" false
fi

# Cleanup Chrome process
kill "$__chrome_pid" 2>/dev/null || true
wait "$__chrome_pid" 2>/dev/null || true
rm -rf "${__profile_dir}"

# ── Isolation ──
t "chrome: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

t "chrome: ~/.aws blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.aws/credentials"

tc_cleanup
