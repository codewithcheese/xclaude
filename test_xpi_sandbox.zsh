#!/bin/zsh
# xpi sandbox integration tests
# Runs on macOS only. Exercises the Pi-specific base profile without
# requiring Pi to be installed; if pi exists, verifies it can start.
#
# Usage: zsh test_xpi_sandbox.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
__xpi_dir="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/xpi.lib.zsh"

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
  local __stderr_file="${TMPDIR_RESOLVED}/xpi-test-stderr-$$.txt"
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
XPI_DIR="$(readlink -f "${SCRIPT_DIR}")"
HOME_DIR="${HOME}"

__xpi_trust_dir="$(mktemp -d)"
__xpi_trusted_file="${__xpi_trust_dir}/trusted"
__xpi_trusted_copies="${__xpi_trust_dir}/trusted.d"

__fixtures_created=()
__ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    /bin/mkdir -p "$dir"
    __fixtures_created+=("$dir")
  fi
}

__ensure_file() {
  local path="$1" content="${2:-xpi-test-fixture}"
  __ensure_dir "${path:h}"
  if [[ ! -f "$path" ]]; then
    /bin/echo "$content" > "$path"
    __fixtures_created+=("$path")
  fi
}

__ensure_executable() {
  local path="$1"
  __ensure_file "$path" $'#!/bin/sh\necho xpi-test\n'
  /bin/chmod +x "$path"
}

__ensure_dir "${HOME}/.pi/agent"
__ensure_dir "${HOME}/.pi/agent/extensions"
__ensure_dir "${HOME}/.pi/agent/themes"
__ensure_file "${HOME}/.pi/agent/xpi-test-readable-$$"
__ensure_file "${HOME}/.ssh/known_hosts"
__ensure_executable "${HOME}/.local/bin/xpi-standalone-test-$$"
__ensure_executable "${HOME}/.pi/agent/extensions/xpi-ext-test-$$"
__ensure_executable "${HOME}/.pi/agent/themes/xpi-theme-test-$$"

/bin/echo "hello" > "${PROJECT_DIR}/testfile.txt"

cleanup() {
  rm -rf "$PROJECT_DIR" "$__xpi_trust_dir"
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

PROFILE="$(__xpi_assemble "$PROJECT_DIR")"
PROFILE_PATH="${TMPDIR_RESOLVED}/xpi-test-$$.sb"
/bin/echo "$PROFILE" > "$PROFILE_PATH"

sandboxed() {
  cd "$PROJECT_DIR"
  XCLAUDE_ACTIVE=1 XPI_ACTIVE=1 sandbox-exec \
    -D "PROJECT_DIR=${PROJECT_DIR}" \
    -D "TMPDIR=${TMPDIR_RESOLVED}" \
    -D "CACHE_DIR=${CACHE_DIR}" \
    -D "VOLATILE_DIR=${VOLATILE_DIR}" \
    -D "HOME=${HOME_DIR}" \
    -D "XPI_DIR=${XPI_DIR}" \
    -f "$PROFILE_PATH" \
    -- "$@"
}

echo "=== xpi profile ==="
echo "  base-common.sb + base-pi.sb assembled to: ${PROFILE_PATH}"
echo "  project dir: ${PROJECT_DIR}"
echo ""

echo "=== Read access ==="

t "read project file"
expect_success "allowed" sandboxed cat "${PROJECT_DIR}/testfile.txt"

t "read Pi state"
expect_success "allowed" sandboxed cat "${HOME}/.pi/agent/xpi-test-readable-$$"

t "read ~/.ssh remains blocked"
expect_fail "blocked" sandboxed cat "${HOME}/.ssh/known_hosts"

echo "=== Write access ==="

t "write project file"
expect_success "allowed" sandboxed touch "${PROJECT_DIR}/newfile.txt"

t "write Pi state"
expect_success "allowed" sandboxed touch "${HOME}/.pi/agent/xpi-test-write-$$"
rm -f "${HOME}/.pi/agent/xpi-test-write-$$"

t "write home root remains blocked"
expect_fail "blocked" sandboxed touch "${HOME}/xpi-test-should-not-exist"

t "write to existing .xclaude config is blocked"
/bin/echo "tool node" > "${PROJECT_DIR}/.xclaude"
expect_fail "blocked" sandboxed /bin/sh -c "echo 'allow-read ~/.ssh' >> '${PROJECT_DIR}/.xclaude'"

t "create .xclaude config is blocked"
rm -f "${PROJECT_DIR}/.xclaude"
expect_fail "blocked" sandboxed /bin/sh -c "echo 'allow-read ~/.ssh' > '${PROJECT_DIR}/.xclaude'"

echo "=== Exec access ==="

t "exec curl-installer style ~/.local/bin binary"
expect_success "allowed" sandboxed "${HOME}/.local/bin/xpi-standalone-test-$$"

t "exec script under ~/.pi/agent/extensions"
expect_success "allowed" sandboxed "${HOME}/.pi/agent/extensions/xpi-ext-test-$$"

t "exec under ~/.pi/agent/themes is blocked (scoped exec)"
expect_fail "blocked" sandboxed "${HOME}/.pi/agent/themes/xpi-theme-test-$$"

t "tmp script execution remains blocked"
sandboxed /bin/sh -c "printf '#!/bin/sh\necho bad\n' > /private/tmp/xpi-exec-$$ && chmod +x /private/tmp/xpi-exec-$$" 2>/dev/null || true
if [[ -f "/private/tmp/xpi-exec-$$" ]]; then
  expect_fail "blocked" sandboxed "/private/tmp/xpi-exec-$$"
  rm -f "/private/tmp/xpi-exec-$$"
else
  __test_pass=$((__test_pass + 1))
fi

t "XPI_ACTIVE is visible"
expect_success "visible" sandboxed /bin/sh -c 'test "$XPI_ACTIVE" = 1'

t "shared XCLAUDE_ACTIVE is visible"
expect_success "visible" sandboxed /bin/sh -c 'test "$XCLAUDE_ACTIVE" = 1'

t "installed pi can start"
if pi_bin="$(command -v pi 2>/dev/null)"; then
  expect_success "runs" sandboxed "$pi_bin" --version
else
  skip "pi not installed"
fi

echo "=== gh toolchain: keyring (keychain) access ==="

# gh stores its OAuth token in the macOS login keychain by default. Unlike
# base.sb (Claude), base-pi.sb does not grant keychain read — Pi keeps its
# own auth in ~/.pi — so `tool gh` must supply it, or `gh auth status`
# reports the token invalid. Guard both directions: the base alone must
# block keychain reads; `tool gh` must allow them.
__keychain_file=""
for __kc in "${HOME}/Library/Keychains/"*(.N); do
  __keychain_file="$__kc"; break
done

if [[ -z "$__keychain_file" ]]; then
  t "gh keyring: keychain read blocked by base (no tool gh)"; skip "no keychain database present"
  t "gh keyring: tool gh grants keychain read"; skip "no keychain database present"
else
  t "gh keyring: keychain read blocked by base (no tool gh)"
  expect_fail "blocked" sandboxed cat "$__keychain_file"

  # A second profile that opts into the gh toolchain must gain keychain read.
  /bin/echo "tool gh" > "${PROJECT_DIR}/.xclaude"
  __xpi_trust "${PROJECT_DIR}/.xclaude" >/dev/null 2>&1
  GH_PROFILE_PATH="${TMPDIR_RESOLVED}/xpi-gh-test-$$.sb"
  __xpi_assemble "$PROJECT_DIR" > "$GH_PROFILE_PATH"
  rm -f "${PROJECT_DIR}/.xclaude"

  sandboxed_gh() {
    cd "$PROJECT_DIR"
    XCLAUDE_ACTIVE=1 XPI_ACTIVE=1 sandbox-exec \
      -D "PROJECT_DIR=${PROJECT_DIR}" \
      -D "TMPDIR=${TMPDIR_RESOLVED}" \
      -D "CACHE_DIR=${CACHE_DIR}" \
      -D "VOLATILE_DIR=${VOLATILE_DIR}" \
      -D "HOME=${HOME_DIR}" \
      -D "XPI_DIR=${XPI_DIR}" \
      -f "$GH_PROFILE_PATH" \
      -- "$@"
  }

  t "gh keyring: tool gh grants keychain read"
  expect_success "allowed" sandboxed_gh cat "$__keychain_file"
  rm -f "$GH_PROFILE_PATH"
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
