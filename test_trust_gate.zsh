#!/bin/zsh
# test_trust_gate.zsh — integration tests for __xsandbox_check_trust
#
# Exercises the end-to-end wiring: summary + colorize filters + bold prompt +
# stdin approval + trust ledger updates. Runs on any platform with zsh
# (no sandbox-exec required).
#
# Usage: zsh test_trust_gate.zsh

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/xsandbox.lib.zsh"

# ── Framework ────────────────────────────────────────────────
__pass=0
__fail=0
__name=""

t() { __name="$1"; }

assert_eq() {
  local expected="$1" actual="$2"
  if [[ "$expected" == "$actual" ]]; then
    __pass=$((__pass + 1))
  else
    __fail=$((__fail + 1))
    echo "FAIL: ${__name}" >&2
    echo "  expected: ${(V)expected}" >&2
    echo "  actual:   ${(V)actual}" >&2
  fi
}

assert_contains() {
  local needle="$1" haystack="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    __pass=$((__pass + 1))
  else
    __fail=$((__fail + 1))
    echo "FAIL: ${__name}" >&2
    echo "  expected to contain: ${(V)needle}" >&2
  fi
}

assert_not_contains() {
  local needle="$1" haystack="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    __pass=$((__pass + 1))
  else
    __fail=$((__fail + 1))
    echo "FAIL: ${__name}" >&2
    echo "  expected NOT to contain: ${(V)needle}" >&2
  fi
}

# ── Isolated trust env ──────────────────────────────────────
TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

__xsandbox_name="xclaude"
__xsandbox_dir="${SCRIPT_DIR}"
__xsandbox_base_profile="${SCRIPT_DIR}/base.sb"
__xsandbox_config_name=".xclaude"
__xsandbox_user_config="${TMP}/no-user-config"
__xsandbox_trust_dir="${TMP}/trust"
__xsandbox_trusted_file="${__xsandbox_trust_dir}/trusted"
__xsandbox_trusted_copies="${__xsandbox_trust_dir}/trusted.d"

# Run check_trust directly (not via command substitution, which would swallow
# __rc in a subshell). Sets __rc and __out in the caller's scope.
run_trust() {
  local file="$1" reply="$2" color="${3:-always}"
  XSANDBOX_COLOR="$color" __xsandbox_check_trust "$file" \
    2>"${TMP}/stderr" >/dev/null <<< "$reply"
  __rc=$?
  __out="$(< "${TMP}/stderr")"
}

reset_ledger() { rm -rf "${__xsandbox_trust_dir}"; }

# ── Tests ───────────────────────────────────────────────────
echo "=== Trust gate integration ==="

t "non-existent file: returns 0, no output"
nonexistent="${TMP}/nothing-here"
out=$(__xsandbox_check_trust "$nonexistent" 2>&1 >/dev/null </dev/null)
rc=$?
assert_eq "0" "$rc"
assert_eq "" "$out"

t "already-trusted file: short-circuits, no output"
cfg="${TMP}/already.xclaude"
echo "tool node" > "$cfg"
__xsandbox_trust "$cfg"
out=$(XSANDBOX_COLOR=always __xsandbox_check_trust "$cfg" 2>&1 >/dev/null </dev/null)
rc=$?
assert_eq "0" "$rc"
assert_eq "" "$out"
reset_ledger

t "new config + 'y': summary line shown before body"
cfg="${TMP}/new.xclaude"
cat > "$cfg" <<EOF
# demo
tool node
allow-write ~/data
allow-exec ~/.local/bin/foo
EOF
run_trust "$cfg" "y"
assert_contains "new config: ${cfg}" "$__out"
# Summary should name each verb present
assert_contains "exec"  "$__out"
assert_contains "write" "$__out"
assert_contains "tool"  "$__out"
# The log line "new config:" must come before the verb-body rendering of 'tool'
log_pos=$(echo "$__out"  | awk 'BEGIN{p=-1} /new config:/{p=NR; exit} END{print p}')
tool_pos=$(echo "$__out" | awk 'BEGIN{p=-1} /\x1b\[36m\x1b\[1mtool\x1b\[0m node/{p=NR; exit} END{print p}')
if (( log_pos > 0 && tool_pos > log_pos )); then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — log_pos=$log_pos tool_pos=$tool_pos" >&2
fi

t "new config + 'y': body renders with severity-colored verbs"
assert_contains $'\e[35m\e[1mallow-exec\e[0m'  "$__out"  # magenta
assert_contains $'\e[33m\e[1mallow-write\e[0m' "$__out"  # yellow
assert_contains $'\e[36m\e[1mtool\e[0m'        "$__out"  # cyan

t "new config + 'y': approval prompt is bold"
assert_contains $'\e[1mxclaude: allow this config? [y/N]\e[0m' "$__out"

t "new config + 'y': ledger gets entry, exit 0"
assert_eq "0" "$__rc"
if [[ -f "$__xsandbox_trusted_file" ]] && grep -q "# ${cfg}$" "$__xsandbox_trusted_file"; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — ledger not updated" >&2
fi
reset_ledger

t "new config + 'n': exit 1, ledger untouched, 'denied' logged"
cfg="${TMP}/rejected.xclaude"
echo "tool node" > "$cfg"
run_trust "$cfg" "n"
assert_eq "1" "$__rc"
assert_contains "denied" "$__out"
if [[ ! -f "$__xsandbox_trusted_file" ]]; then
  __pass=$((__pass + 1))
elif ! grep -q "# ${cfg}$" "$__xsandbox_trusted_file"; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — ledger unexpectedly updated" >&2
fi
reset_ledger

t "new config + empty reply: default is deny (exit 1)"
cfg="${TMP}/empty-reply.xclaude"
echo "tool node" > "$cfg"
run_trust "$cfg" ""
assert_eq "1" "$__rc"
assert_contains "denied" "$__out"
reset_ledger

t "changed config + 'y': diff is rendered with file headers"
cfg="${TMP}/changing.xclaude"
echo "tool node" > "$cfg"
__xsandbox_trust "$cfg"
cat > "$cfg" <<EOF
tool node
allow-exec ~/.local/bin/foo
EOF
run_trust "$cfg" "y"
assert_contains "config changed: ${cfg}" "$__out"
assert_contains "--- trusted" "$__out"
assert_contains "+++ current" "$__out"

t "changed config + 'y': summary reflects +1 exec delta"
assert_contains "+1" "$__out"
assert_contains "exec" "$__out"
# No additions should be reported for verbs that didn't change
assert_not_contains "+1 write" "$__out"
assert_not_contains "+1 read"  "$__out"

t "changed config + 'y': added exec line has magenta verb overlay on green polarity"
assert_contains $'\e[32m+\e[0m\e[35m\e[1mallow-exec\e[0m\e[32m ~/.local/bin/foo\e[0m' "$__out"
assert_eq "0" "$__rc"
reset_ledger

t "XSANDBOX_COLOR=never: plain body, no ANSI"
cfg="${TMP}/plain.xclaude"
echo "tool node" > "$cfg"
run_trust "$cfg" "y" "never"
assert_not_contains $'\e[' "$__out"
assert_contains "tool node" "$__out"
assert_contains "allow this config? [y/N]" "$__out"
reset_ledger

# ── Results ────────────────────────────────────────────────
echo ""
echo "=== Results ==="
total=$((__pass + __fail))
echo "${__pass}/${total} passed"
if (( __fail > 0 )); then
  exit 1
fi
