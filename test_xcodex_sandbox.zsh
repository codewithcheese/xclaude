#!/bin/zsh
# xcodex sandbox integration tests
# Runs on macOS only. Exercises the Codex-specific base profile without
# requiring Codex to be installed; if codex exists, verifies it can start.
#
# Usage: zsh test_xcodex_sandbox.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
__xcodex_dir="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/xcodex.lib.zsh"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "SKIP: sandbox tests require macOS" >&2
  exit 0
fi

if ! command -v sandbox-exec &>/dev/null; then
  echo "SKIP: sandbox-exec not found" >&2
  exit 0
fi

__test_pass=0
__test_fail=0
__test_skip=0
__test_name=""

t() { __test_name="$1"; }

expect_success() {
  local desc="$1"; shift
  local __stderr_file="${TMPDIR_RESOLVED}/xcodex-test-stderr-$$.txt"
  if "$@" >/dev/null 2>"$__stderr_file"; then
    __test_pass=$((__test_pass + 1))
  else
    __test_fail=$((__test_fail + 1))
    echo "FAIL: ${__test_name} — ${desc}" >&2
    echo "  command: $*" >&2
    if [[ -s "$__stderr_file" ]]; then
      echo "  stderr:" >&2
      sed 's/^/    /' < "$__stderr_file" | tail -20 >&2
    fi
  fi
  rm -f "$__stderr_file"
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

PROJECT_DIR="$(readlink -f "$(mktemp -d)")"
TMPDIR_RESOLVED="$(readlink -f "${TMPDIR:-/private/tmp}")"
CACHE_DIR="${TMPDIR_RESOLVED%/T*}/C"
VOLATILE_DIR="${TMPDIR_RESOLVED%/T*}/X"
XCODEX_DIR="$(readlink -f "${SCRIPT_DIR}")"
HOME_DIR="${HOME}"

__xcodex_trust_dir="$(mktemp -d)"
__xcodex_trusted_file="${__xcodex_trust_dir}/trusted"
__xcodex_trusted_copies="${__xcodex_trust_dir}/trusted.d"

__fixtures_created=()
__ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    /bin/mkdir -p "$dir"
    __fixtures_created+=("$dir")
  fi
}

__ensure_file() {
  local path="$1" content="${2:-xcodex-test-fixture}"
  __ensure_dir "${path:h}"
  if [[ ! -f "$path" ]]; then
    /bin/echo "$content" > "$path"
    __fixtures_created+=("$path")
  fi
}

__ensure_executable() {
  local path="$1"
  __ensure_file "$path" $'#!/bin/sh\necho xcodex-test\n'
  /bin/chmod +x "$path"
}

__ensure_dir "${HOME}/.codex"
__ensure_file "${HOME}/.codex/xcodex-test-readable-$$"
__ensure_file "${HOME}/.ssh/known_hosts"
__ensure_executable "${HOME}/.local/bin/xcodex-standalone-test-$$"
__ensure_executable "${HOME}/.bun/bin/xcodex-bun-test-$$"

/bin/echo "hello" > "${PROJECT_DIR}/testfile.txt"

cleanup() {
  rm -rf "$PROJECT_DIR" "$__xcodex_trust_dir"
  rm -f "${PROFILE_PATH:-}"
  local f
  for f in "${(Oa)__fixtures_created[@]}"; do
    if [[ -d "$f" ]]; then
      rmdir "$f" 2>/dev/null || true
    else
      rm -f "$f" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

PROFILE="$(__xcodex_assemble "$PROJECT_DIR")"
PROFILE_PATH="${TMPDIR_RESOLVED}/xcodex-test-$$.sb"
/bin/echo "$PROFILE" > "$PROFILE_PATH"

sandboxed() {
  cd "$PROJECT_DIR"
  XCODEX_ACTIVE=1 sandbox-exec \
    -D "PROJECT_DIR=${PROJECT_DIR}" \
    -D "TMPDIR=${TMPDIR_RESOLVED}" \
    -D "CACHE_DIR=${CACHE_DIR}" \
    -D "VOLATILE_DIR=${VOLATILE_DIR}" \
    -D "HOME=${HOME_DIR}" \
    -D "XCODEX_DIR=${XCODEX_DIR}" \
    -f "$PROFILE_PATH" \
    -- "$@"
}

echo "=== xcodex profile ==="
echo "  base-common.sb + base-codex.sb assembled to: ${PROFILE_PATH}"
echo "  project dir: ${PROJECT_DIR}"
echo ""

echo "=== Read access ==="

t "read project file"
expect_success "allowed" sandboxed cat "${PROJECT_DIR}/testfile.txt"

t "read Codex state"
expect_success "allowed" sandboxed cat "${HOME}/.codex/xcodex-test-readable-$$"

t "read ~/.ssh remains blocked"
expect_fail "blocked" sandboxed cat "${HOME}/.ssh/known_hosts"

echo "=== Write access ==="

t "write project file"
expect_success "allowed" sandboxed touch "${PROJECT_DIR}/newfile.txt"

t "write Codex state"
expect_success "allowed" sandboxed touch "${HOME}/.codex/xcodex-test-write-$$"
rm -f "${HOME}/.codex/xcodex-test-write-$$"

t "write home root remains blocked"
expect_fail "blocked" sandboxed touch "${HOME}/xcodex-test-should-not-exist"

t "write to existing .xclaude config is blocked"
/bin/echo "tool node" > "${PROJECT_DIR}/.xclaude"
expect_fail "blocked" sandboxed /bin/sh -c "echo 'allow-read ~/.ssh' >> '${PROJECT_DIR}/.xclaude'"

t "create .xclaude config is blocked"
rm -f "${PROJECT_DIR}/.xclaude"
expect_fail "blocked" sandboxed /bin/sh -c "echo 'allow-read ~/.ssh' > '${PROJECT_DIR}/.xclaude'"

echo "=== Exec access ==="

t "exec direct-release style ~/.local/bin binary"
expect_success "allowed" sandboxed "${HOME}/.local/bin/xcodex-standalone-test-$$"

t "exec bun-global style binary"
expect_success "allowed" sandboxed "${HOME}/.bun/bin/xcodex-bun-test-$$"

t "tmp script execution remains blocked"
sandboxed /bin/sh -c "printf '#!/bin/sh\necho bad\n' > /private/tmp/xcodex-exec-$$ && chmod +x /private/tmp/xcodex-exec-$$" 2>/dev/null || true
if [[ -f "/private/tmp/xcodex-exec-$$" ]]; then
  expect_fail "blocked" sandboxed "/private/tmp/xcodex-exec-$$"
  rm -f "/private/tmp/xcodex-exec-$$"
else
  __test_pass=$((__test_pass + 1))
fi

t "XCODEX_ACTIVE is visible"
expect_success "visible" sandboxed /bin/sh -c 'test "$XCODEX_ACTIVE" = 1'

t "installed codex can start"
if codex_bin="$(command -v codex 2>/dev/null)"; then
  expect_success "runs" sandboxed "$codex_bin" --version
else
  skip "codex not installed"
fi

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
