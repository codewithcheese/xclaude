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
__xsandbox_base_profiles=("${SCRIPT_DIR}/base-common.sb" "${SCRIPT_DIR}/base.sb")
__xsandbox_config_name=".xclaude"
__xsandbox_user_config="${TMP}/no-user-config"
__xsandbox_trust_dir="${TMP}/trust"
__xsandbox_trusted_file="${__xsandbox_trust_dir}/trusted"
__xsandbox_trusted_copies="${__xsandbox_trust_dir}/trusted.d"
__xsandbox_packs_dir="${TMP}/packs"
mkdir -p "$__xsandbox_packs_dir"

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

# ── Pack trust gate ─────────────────────────────────────────
echo ""
echo "=== Pack trust gate ==="

# Helper: run check_pack_trust, capture stderr + rc (same shape as run_trust).
run_pack_trust() {
  local pack_file="$1" project_config="$2" reply="$3" color="${4:-always}"
  XSANDBOX_COLOR="$color" __xsandbox_check_pack_trust "$pack_file" "$project_config" \
    2>"${TMP}/stderr" >/dev/null <<< "$reply"
  __rc=$?
  __out="$(< "${TMP}/stderr")"
}

# Helper: run check_pack_trusts (orchestrator over a whole project config).
run_pack_trusts() {
  local project_config="$1" replies="$2" color="${3:-always}"
  XSANDBOX_COLOR="$color" __xsandbox_check_pack_trusts "$project_config" \
    2>"${TMP}/stderr" >/dev/null <<< "$replies"
  __rc=$?
  __out="$(< "${TMP}/stderr")"
}

reset_ledger  # start fresh

t "new pack for project + 'y': prompt shown, ledger gets compound entry"
pack="${__xsandbox_packs_dir}/dev"
proj="${TMP}/projA/.xclaude"
mkdir -p "${TMP}/projA"
cat > "$pack" <<EOF
# shared dev pack
allow-read ~/.config/shared
allow-write ~/data/dev
EOF
echo "pack dev" > "$proj"
run_pack_trust "$pack" "$proj" "y"
assert_eq "0" "$__rc"
assert_contains "new pack: dev" "$__out"
assert_contains "allow pack dev for this project? [y/N]" "$__out"
# Ledger entry is compound — hash + project_path + pack name
if grep -q "# ${proj} pack dev\$" "$__xsandbox_trusted_file"; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — ledger missing compound entry for dev" >&2
fi

t "trusted pack (same project, same hash): reminder only, no prompt"
run_pack_trust "$pack" "$proj" ""
assert_eq "0" "$__rc"
assert_contains "using pack dev (trusted)" "$__out"
# Prompt string must NOT appear
assert_not_contains "allow pack dev for this project?" "$__out"

t "same pack, different project: prompts again (no cross-project trust)"
projB="${TMP}/projB/.xclaude"
mkdir -p "${TMP}/projB"
echo "pack dev" > "$projB"
run_pack_trust "$pack" "$projB" "y"
assert_eq "0" "$__rc"
assert_contains "new pack: dev" "$__out"
assert_contains "allow pack dev for this project?" "$__out"
# Both projects' entries coexist in the ledger
if grep -q "# ${proj} pack dev\$" "$__xsandbox_trusted_file" \
  && grep -q "# ${projB} pack dev\$" "$__xsandbox_trusted_file"; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — ledger should have both project entries" >&2
fi

t "changed pack (same project): diff prompt, summary shows delta"
cat > "$pack" <<EOF
# shared dev pack
allow-read ~/.config/shared
allow-write ~/data/dev
allow-exec ~/.local/bin/dev-tool
EOF
run_pack_trust "$pack" "$proj" "y"
assert_eq "0" "$__rc"
assert_contains "pack changed: dev" "$__out"
assert_contains "--- trusted" "$__out"
assert_contains "+++ current" "$__out"
assert_contains "+1" "$__out"
assert_contains "exec" "$__out"
# Ledger entry updated to new hash, only one entry per (proj, pack name)
count=$(grep -c "# ${proj} pack dev\$" "$__xsandbox_trusted_file")
assert_eq "1" "$count"

t "pack denial: rc=1, ledger entry not added"
pack2="${__xsandbox_packs_dir}/rejected"
echo "allow-read ~/.config/x" > "$pack2"
projC="${TMP}/projC/.xclaude"
mkdir -p "${TMP}/projC"
echo "pack rejected" > "$projC"
run_pack_trust "$pack2" "$projC" "n"
assert_eq "1" "$__rc"
assert_contains "pack rejected denied" "$__out"
if ! grep -q "# ${projC} pack rejected\$" "$__xsandbox_trusted_file" 2>/dev/null; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — denied pack should not be in ledger" >&2
fi

reset_ledger

t "check_pack_trusts: all new packs — prompts each, all approved → rc=0"
pack_a="${__xsandbox_packs_dir}/alpha"
pack_b="${__xsandbox_packs_dir}/beta"
echo "allow-read ~/.config/alpha" > "$pack_a"
echo "allow-read ~/.config/beta" > "$pack_b"
proj2="${TMP}/proj2/.xclaude"
mkdir -p "${TMP}/proj2"
cat > "$proj2" <<EOF
pack alpha
pack beta
allow-read ~/.config/direct
EOF
run_pack_trusts "$proj2" $'y\ny'
assert_eq "0" "$__rc"
assert_contains "new pack: alpha" "$__out"
assert_contains "new pack: beta" "$__out"

t "check_pack_trusts: denying one pack aborts, remaining not prompted"
reset_ledger
run_pack_trusts "$proj2" $'n'
assert_eq "1" "$__rc"
assert_contains "new pack: alpha" "$__out"
# beta should NOT have been prompted — ordering stops on first denial
assert_not_contains "new pack: beta" "$__out"

t "check_pack_trusts: no pack directives → rc=0, no output"
proj3="${TMP}/proj3/.xclaude"
mkdir -p "${TMP}/proj3"
cat > "$proj3" <<EOF
tool node
allow-read ~/.config/nopack
EOF
run_pack_trusts "$proj3" ""
assert_eq "0" "$__rc"
assert_eq "" "$__out"

# ── Reject-on-denial behavior (assembler) ───────────────────
echo ""
echo "=== Reject-on-denial ==="

reset_ledger

t "__xsandbox_assemble: denied project config → rc=1 (no fallback)"
proj_dir="${TMP}/reject-proj"
mkdir -p "$proj_dir"
echo "tool node" > "${proj_dir}/.xclaude"
__xsandbox_assemble "$proj_dir" >/dev/null 2>"${TMP}/stderr" <<< "n"
rc=$?
assert_eq "1" "$rc"

t "__xsandbox_assemble: denied project no longer writes a base-only profile"
# Regression test: old behavior returned 0 with base-only SBPL when the
# user rejected the project config. New behavior must return 1.
out="$(__xsandbox_assemble "$proj_dir" 2>/dev/null <<< "n" || echo __FAILED__)"
assert_contains "__FAILED__" "$out"

t "__xsandbox_assemble: approved project + denied pack → rc=1"
reset_ledger
pack3="${__xsandbox_packs_dir}/gamma"
echo "allow-read ~/.config/gamma" > "$pack3"
proj_dir2="${TMP}/reject-pack-proj"
mkdir -p "$proj_dir2"
echo "pack gamma" > "${proj_dir2}/.xclaude"
# Reply "y" to approve project, "n" to deny pack
__xsandbox_assemble "$proj_dir2" >/dev/null 2>"${TMP}/stderr" <<< $'y\nn'
rc=$?
assert_eq "1" "$rc"

t "__xsandbox_assemble: approved project + approved pack → rc=0, pack body emitted"
reset_ledger
out="$(__xsandbox_assemble "$proj_dir2" 2>/dev/null <<< $'y\ny')"
rc=$?
assert_eq "0" "$rc"
assert_contains "pack: gamma" "$out"
assert_contains "/.config/gamma" "$out"

# ── Ledger collision regression ─────────────────────────────
echo ""
echo "=== Ledger collision ==="

reset_ledger

t "pack + project with identical content: project still prompts"
# Regression: old grep patterns matched ^<hash> anywhere, so an approved
# pack entry with the same content-hash as an unrelated project config
# would silently treat the project as trusted. After the rewrite, trust
# lookups are line-exact and must not collide.
identical='allow-read ~/.config/shared'
pack_id="${__xsandbox_packs_dir}/ident"
proj_id_dir="${TMP}/ident-proj"
mkdir -p "$proj_id_dir"
printf '%s\n' "$identical" > "$pack_id"
printf '%s\n' "$identical" > "${proj_id_dir}/.xclaude"
# Pre-trust the pack for a completely different project
other_proj="${TMP}/other-proj/.xclaude"
mkdir -p "${TMP}/other-proj"
printf '%s\n' "$identical" > "$other_proj"
__xsandbox_trust_pack_for_project "$pack_id" "$other_proj"
# Now check: is_trusted for a project whose hash matches the pack's hash
# must return false (we never trusted THAT project config).
if __xsandbox_is_trusted "${proj_id_dir}/.xclaude"; then
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — is_trusted matched a pack entry by hash alone" >&2
else
  __pass=$((__pass + 1))
fi
reset_ledger

t "project path with regex metacharacters: no over-match"
# Paths routinely contain '.', which in regex matches any char. If the
# old grep pattern were still in play, 'proj.x/.xclaude' would match
# 'projXx/.xclaude' in is_trusted. Line-exact comparison must not.
reset_ledger
proj_dot_dir="${TMP}/proj.x"
proj_alt_dir="${TMP}/projXx"
mkdir -p "$proj_dot_dir" "$proj_alt_dir"
printf 'tool node\n' > "${proj_dot_dir}/.xclaude"
printf 'tool node\n' > "${proj_alt_dir}/.xclaude"  # same content → same hash
__xsandbox_trust "${proj_dot_dir}/.xclaude"
if __xsandbox_is_trusted "${proj_alt_dir}/.xclaude"; then
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — '.' in path over-matched as regex" >&2
else
  __pass=$((__pass + 1))
fi
reset_ledger

t "pack ledger entry does not satisfy project is_trusted (compound format)"
# Ensure the compound pack ledger entry ('<hash> # <proj> pack <name>')
# is not picked up by is_trusted when looking for a plain project entry.
reset_ledger
pack_plain="${__xsandbox_packs_dir}/plain"
printf 'allow-read ~/.config/x\n' > "$pack_plain"
proj_plain="${TMP}/plain-proj/.xclaude"
mkdir -p "${TMP}/plain-proj"
printf 'pack plain\n' > "$proj_plain"
__xsandbox_trust_pack_for_project "$pack_plain" "$proj_plain"
# The ledger now has ONE entry: '<hash> # /.../plain-proj/.xclaude pack plain'.
# is_trusted for the project file must not fire on it.
if __xsandbox_is_trusted "$proj_plain"; then
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — project is_trusted matched compound pack entry" >&2
else
  __pass=$((__pass + 1))
fi
reset_ledger

t "trust_pack: removing old pack entry does not touch project entries"
# Regression: rewriting the ledger to update a pack entry must preserve
# all project config entries, even when they share a prefix (same proj path).
reset_ledger
pack_upd="${__xsandbox_packs_dir}/upd"
printf 'allow-read ~/.config/v1\n' > "$pack_upd"
proj_upd="${TMP}/upd-proj/.xclaude"
mkdir -p "${TMP}/upd-proj"
printf 'pack upd\n' > "$proj_upd"
__xsandbox_trust "$proj_upd"
__xsandbox_trust_pack_for_project "$pack_upd" "$proj_upd"
# Mutate the pack and re-trust
printf 'allow-read ~/.config/v2\n' > "$pack_upd"
__xsandbox_trust_pack_for_project "$pack_upd" "$proj_upd"
# Project must still be trusted after pack re-trust
if __xsandbox_is_trusted "$proj_upd"; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — pack re-trust wiped the project entry" >&2
fi
# And pack must be trusted at its new hash
if __xsandbox_is_pack_trusted_for_project "$pack_upd" "$proj_upd"; then
  __pass=$((__pass + 1))
else
  __fail=$((__fail + 1))
  echo "FAIL: ${__name} — pack not trusted at new hash" >&2
fi
reset_ledger

# ── Results ────────────────────────────────────────────────
echo ""
echo "=== Results ==="
total=$((__pass + __fail))
echo "${__pass}/${total} passed"
if (( __fail > 0 )); then
  exit 1
fi
