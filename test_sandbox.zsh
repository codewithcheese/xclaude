#!/bin/zsh
# xclaude sandbox integration tests
# Runs on macOS only — tests that sandbox-exec with the assembled
# profile actually blocks/allows the right filesystem operations.
#
# Usage: zsh test_sandbox.zsh [--with-config .xclaude-test-fixture]
#
# Requires: macOS with sandbox-exec, shasum

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/xclaude.zsh"

# ── Pre-flight checks ────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "SKIP: sandbox tests require macOS" >&2
  exit 0
fi

if ! command -v sandbox-exec &>/dev/null; then
  echo "SKIP: sandbox-exec not found" >&2
  exit 0
fi

# ── Test framework ────────────────────────────────────────────
__test_pass=0
__test_fail=0
__test_skip=0
__test_name=""

t() { __test_name="$1"; }

expect_success() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    __test_pass=$((__test_pass + 1))
  else
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name} — ${desc}" >&2
    echo "  command: $*" >&2
  fi
}

expect_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name} — ${desc}" >&2
    echo "  expected sandbox to block: $*" >&2
  else
    __test_pass=$((__test_pass + 1))
  fi
}

skip() {
  __test_skip=$((__test_skip + 1))
  echo "SKIP: ${__test_name} — $1" >&2
}

# ── Setup ─────────────────────────────────────────────────────
PROJECT_DIR="$(mktemp -d)"
TMPDIR_RESOLVED="$(readlink -f "${TMPDIR:-/private/tmp}")"
CACHE_DIR="${TMPDIR_RESOLVED%/T*}/C"
HOME_DIR="${HOME}"

# Create test fixtures in the project dir
echo "hello" > "${PROJECT_DIR}/testfile.txt"
mkdir -p "${PROJECT_DIR}/subdir"
echo "nested" > "${PROJECT_DIR}/subdir/nested.txt"

cleanup() {
  rm -rf "$PROJECT_DIR"
  rm -f "${PROFILE_PATH:-}"
}
trap cleanup EXIT

# ── Assemble profile ─────────────────────────────────────────
# Parse optional --with-config to test project configs
PROJECT_CONFIG=""
if [[ "${1:-}" = "--with-config" && -n "${2:-}" ]]; then
  cp "$2" "${PROJECT_DIR}/.xclaude"
  # Pre-trust the config so assembly doesn't prompt
  __xclaude_trust_dir="$(mktemp -d)"
  __xclaude_trusted_file="${__xclaude_trust_dir}/trusted"
  __xclaude_trust "${PROJECT_DIR}/.xclaude"
fi

PROFILE="$(__xclaude_assemble "$PROJECT_DIR")"
PROFILE_PATH="${TMPDIR_RESOLVED}/xclaude-test-$$.sb"
echo "$PROFILE" > "$PROFILE_PATH"

# Helper: run a command inside the sandbox
sandboxed() {
  sandbox-exec \
    -D "PROJECT_DIR=${PROJECT_DIR}" \
    -D "TMPDIR=${TMPDIR_RESOLVED}" \
    -D "CACHE_DIR=${CACHE_DIR}" \
    -D "HOME=${HOME_DIR}" \
    -f "$PROFILE_PATH" \
    -- "$@"
}

echo "=== Profile ==="
echo "  base.sb + project config assembled to: ${PROFILE_PATH}"
echo "  project dir: ${PROJECT_DIR}"
echo ""

# ── Tests: base profile (reads) ──────────────────────────────
echo "=== Read access ==="

t "read project file"
expect_success "allowed" sandboxed cat "${PROJECT_DIR}/testfile.txt"

t "read nested project file"
expect_success "allowed" sandboxed cat "${PROJECT_DIR}/subdir/nested.txt"

t "read system binary"
expect_success "allowed" sandboxed cat /bin/echo

t "read /etc/hosts"
expect_success "allowed" sandboxed cat /private/etc/hosts

t "read ~/.claude directory"
if [[ -d "${HOME}/.claude" ]]; then
  expect_success "allowed" sandboxed ls "${HOME}/.claude"
else
  skip "~/.claude doesn't exist"
fi

# ── Tests: base profile (blocked reads) ──────────────────────
echo "=== Blocked reads ==="

t "read ~/.ssh"
if [[ -d "${HOME}/.ssh" ]]; then
  expect_fail "blocked" sandboxed cat "${HOME}/.ssh/known_hosts"
else
  skip "~/.ssh doesn't exist"
fi

t "read ~/.aws"
if [[ -d "${HOME}/.aws" ]]; then
  expect_fail "blocked" sandboxed cat "${HOME}/.aws/credentials"
else
  skip "~/.aws doesn't exist"
fi

t "read ~/Desktop"
if [[ -d "${HOME}/Desktop" ]]; then
  expect_fail "blocked" sandboxed ls "${HOME}/Desktop"
else
  skip "~/Desktop doesn't exist"
fi

t "read ~/Documents"
if [[ -d "${HOME}/Documents" ]]; then
  expect_fail "blocked" sandboxed ls "${HOME}/Documents"
else
  skip "~/Documents doesn't exist"
fi

t "read ~/Downloads"
if [[ -d "${HOME}/Downloads" ]]; then
  expect_fail "blocked" sandboxed ls "${HOME}/Downloads"
else
  skip "~/Downloads doesn't exist"
fi

t "read ~/.gnupg"
if [[ -d "${HOME}/.gnupg" ]]; then
  expect_fail "blocked" sandboxed ls "${HOME}/.gnupg"
else
  skip "~/.gnupg doesn't exist"
fi

t "read ~/.docker"
if [[ -d "${HOME}/.docker" ]]; then
  expect_fail "blocked" sandboxed cat "${HOME}/.docker/config.json"
else
  skip "~/.docker doesn't exist"
fi

t "read ~/.zsh_history"
if [[ -f "${HOME}/.zsh_history" ]]; then
  expect_fail "blocked" sandboxed cat "${HOME}/.zsh_history"
else
  skip "~/.zsh_history doesn't exist"
fi

# ── Tests: base profile (writes) ─────────────────────────────
echo "=== Write access ==="

t "write to project dir"
expect_success "allowed" sandboxed touch "${PROJECT_DIR}/newfile.txt"

t "write to project subdir"
expect_success "allowed" sandboxed touch "${PROJECT_DIR}/subdir/newfile.txt"

t "write to tmp"
expect_success "allowed" sandboxed touch "/private/tmp/xclaude-test-$$"
rm -f "/private/tmp/xclaude-test-$$"

# ── Tests: base profile (blocked writes) ─────────────────────
echo "=== Blocked writes ==="

t "write to home root"
expect_fail "blocked" sandboxed touch "${HOME}/xclaude-test-should-not-exist"

t "write to ~/Desktop"
if [[ -d "${HOME}/Desktop" ]]; then
  expect_fail "blocked" sandboxed touch "${HOME}/Desktop/xclaude-test"
else
  skip "~/Desktop doesn't exist"
fi

t "write to ~/.ssh"
expect_fail "blocked" sandboxed touch "${HOME}/.ssh/xclaude-test"

t "write to .xclaude config"
expect_fail "blocked" sandboxed /bin/sh -c "echo 'allow-read ~/.ssh' >> '${PROJECT_DIR}/.xclaude'"

# ── Tests: base profile (exec) ───────────────────────────────
echo "=== Exec access ==="

t "exec /bin/echo"
expect_success "allowed" sandboxed /bin/echo "hello"

t "exec /usr/bin/env"
expect_success "allowed" sandboxed /usr/bin/env echo "hello"

t "exec project script"
echo '#!/bin/sh\necho ok' > "${PROJECT_DIR}/test.sh"
chmod +x "${PROJECT_DIR}/test.sh"
expect_success "allowed" sandboxed "${PROJECT_DIR}/test.sh"

# ── Tests: escape vectors ────────────────────────────────────
echo "=== Escape vectors ==="

t "symlink escape: link to ~/.ssh from project dir"
ln -sf "${HOME}/.ssh" "${PROJECT_DIR}/ssh-link" 2>/dev/null || true
if [[ -L "${PROJECT_DIR}/ssh-link" ]] && [[ -d "${HOME}/.ssh" ]]; then
  expect_fail "blocked" sandboxed cat "${PROJECT_DIR}/ssh-link/known_hosts"
else
  skip "couldn't create symlink or ~/.ssh missing"
fi

t "path traversal via .."
expect_fail "blocked" sandboxed cat "${PROJECT_DIR}/../../.ssh/known_hosts"

t "/tmp script writing then executing"
# Write a script to /tmp, then try to exec it — should fail
# because /tmp is not in the exec allowlist
sandboxed /bin/sh -c "echo '#!/bin/sh\ncat ~/.ssh/id_rsa' > /private/tmp/xclaude-escape-$$.sh && chmod +x /private/tmp/xclaude-escape-$$.sh" 2>/dev/null || true
if [[ -f "/private/tmp/xclaude-escape-$$.sh" ]]; then
  expect_fail "blocked" sandboxed /private/tmp/xclaude-escape-$$.sh
  rm -f "/private/tmp/xclaude-escape-$$.sh"
else
  # The write itself might have succeeded but the inner cat would fail
  # Either way, the escape vector is blocked
  __test_pass=$((__test_pass + 1))
fi

t "child process inherits sandbox"
expect_fail "blocked" sandboxed /bin/sh -c "cat ${HOME}/.ssh/known_hosts"

# ── Cleanup test artifacts ────────────────────────────────────
rm -f "${PROJECT_DIR}/ssh-link" "${PROJECT_DIR}/newfile.txt" "${PROJECT_DIR}/subdir/newfile.txt" "${PROJECT_DIR}/test.sh"

# ── Results ───────────────────────────────────────────────────
echo ""
echo "=== Results ==="
total=$((__test_pass + __test_fail))
echo "${__test_pass}/${total} passed, ${__test_skip} skipped"
if [[ $__test_fail -gt 0 ]]; then
  echo "${__test_fail} FAILED"
  exit 1
else
  echo "All tests passed."
  exit 0
fi
