# Hugging Face toolchain sandbox tests
tc_setup huggingface

tc_fixture_dir "${HOME}/.cache/huggingface/hub"
tc_fixture_dir "${HOME}/.cache/huggingface/assets"
tc_fixture_dir "${HOME}/.cache/huggingface/xet"
tc_fixture_file "${HOME}/.cache/huggingface/token" "hf_test_token"

t "huggingface: read ~/.cache/huggingface"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cache/huggingface/token"

t "huggingface: read hub cache"
tc_fixture_file "${HOME}/.cache/huggingface/hub/test-model"
expect_success "allowed" tc_sandboxed cat "${HOME}/.cache/huggingface/hub/test-model"

t "huggingface: write hub cache (model downloads)"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/huggingface/hub/test-write"
rm -f "${HOME}/.cache/huggingface/hub/test-write"

t "huggingface: write assets cache"
expect_success "allowed" tc_sandboxed touch "${HOME}/.cache/huggingface/assets/test-write"
rm -f "${HOME}/.cache/huggingface/assets/test-write"

t "huggingface: write token"
expect_success "allowed" tc_sandboxed /bin/sh -c "echo 'hf_new_token' > '${HOME}/.cache/huggingface/token'"

# huggingface-cli is a Python script — exec via python (base or uv toolchain)
if tc_has_cmd huggingface-cli; then
  t "huggingface: huggingface-cli works"
  expect_success "usable" tc_sandboxed huggingface-cli --help
fi

t "huggingface: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

t "huggingface: ~/.aws blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.aws/credentials"

tc_cleanup
