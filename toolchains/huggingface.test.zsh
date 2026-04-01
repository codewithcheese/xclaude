# Hugging Face toolchain sandbox tests
tc_setup huggingface

tc_fixture_dir "${HOME}/.cache/huggingface/hub"
tc_fixture_dir "${HOME}/.cache/huggingface/assets"
tc_fixture_dir "${HOME}/.cache/huggingface/xet"
tc_fixture_file "${HOME}/.cache/huggingface/token" "hf_test_token"

# ── Access ──
t "huggingface: read ~/.cache/huggingface"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cache/huggingface/token"

t "huggingface: read hub cache"
tc_fixture_file "${HOME}/.cache/huggingface/hub/test-model"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cache/huggingface/hub/test-model"

t "huggingface: write hub cache"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/huggingface/hub/test-write"
rm -f "${HOME}/.cache/huggingface/hub/test-write"

t "huggingface: write assets cache"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/huggingface/assets/test-write"
rm -f "${HOME}/.cache/huggingface/assets/test-write"

t "huggingface: write token"
expect_success "allowed" tc_sandboxed /bin/sh -c "echo 'hf_new_token' > '${HOME}/.cache/huggingface/token'"

# ── Usability ──
# huggingface-cli is a Python script — exec via system python (base profile)
# sandbox-exec needs the full path — bare names don't search PATH.
__hf_cli="$(command -v huggingface-cli 2>/dev/null || echo "")"
if [[ -z "$__hf_cli" ]]; then
  echo "SKIP: huggingface-cli binary not found in PATH" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

t "huggingface: huggingface-cli --version"
expect_success "runs" tc_sandboxed "$__hf_cli" version

t "huggingface: huggingface-cli scan-cache"
expect_success "scan-cache" tc_sandboxed "$__hf_cli" scan-cache

t "huggingface: huggingface-cli env"
expect_success "env" tc_sandboxed "$__hf_cli" env

# ── Isolation ──
t "huggingface: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

t "huggingface: ~/.aws blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.aws/credentials"

tc_cleanup
