#!/usr/bin/env zsh
# seshi toolchain sandbox tests
#
# Validates the SBPL rules without invoking seshi-hook. Uses generic
# commands (cat/touch) so the test runs regardless of whether seshi
# is installed on the host — the sandbox enforces rules against path
# strings, not runtime tool behavior.
tc_setup seshi

# Fixtures — sandbox checks path strings, not whether tools exist
tc_fixture_dir "${HOME}/.local/share/seshi"
tc_fixture_file "${HOME}/.local/share/seshi/hook-status.jsonl" ""
tc_fixture_dir "${HOME}/.local/share/uv/tools/seshi/bin"
tc_fixture_file "${HOME}/.local/share/uv/tools/seshi/bin/seshi-hook" ""
tc_fixture_dir "${HOME}/.local/share/uv/tools/seshi/lib"
tc_fixture_dir "${HOME}/.local/share/uv/python"
tc_fixture_file "${HOME}/.local/share/uv/python/marker" ""

# ── Granted reads ──
t "seshi: read data dir"
expect_success "allowed" tc_sandboxed cat "${HOME}/.local/share/seshi/hook-status.jsonl"

t "seshi: read venv bin (hook entry script)"
expect_success "allowed" tc_sandboxed cat "${HOME}/.local/share/uv/tools/seshi/bin/seshi-hook"

t "seshi: read uv-managed cpython tree"
expect_success "allowed" tc_sandboxed cat "${HOME}/.local/share/uv/python/marker"

# ── Granted writes ──
t "seshi: write data dir"
expect_success "allowed" tc_sandboxed touch "${HOME}/.local/share/seshi/test-write"
/bin/rm -f "${HOME}/.local/share/seshi/test-write"

t "seshi: write venv lib (for Python __pycache__)"
expect_success "allowed" tc_sandboxed touch "${HOME}/.local/share/uv/tools/seshi/lib/test-write"
/bin/rm -f "${HOME}/.local/share/uv/tools/seshi/lib/test-write"

# ── Shebang-overwrite defense ──
# venv bin and the cpython tree must NOT be writable, otherwise an
# attacker inside the sandbox could replace the hook script or the
# interpreter and hijack the next Stop/SessionStart invocation.
t "seshi: venv bin NOT writable"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.local/share/uv/tools/seshi/bin/attacker"

t "seshi: uv python tree NOT writable"
expect_fail "blocked" tc_sandboxed touch "${HOME}/.local/share/uv/python/attacker"

# ── Isolation ──
t "seshi: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
