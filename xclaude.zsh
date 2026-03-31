__xclaude_dir="${0:A:h}"

xclaude() {
  local project_dir="${PWD}"
  local tmpdir="${TMPDIR:-/private/tmp}"
  local home_dir="${HOME}"
  local script_dir="${__xclaude_dir}"
  local profile_path="${script_dir}/xclaude.sb"

  # Resolve symlinks (Seatbelt uses real paths, /var -> /private/var)
  tmpdir="$(readlink -f "$tmpdir")"

  # TMPDIR is .../T or .../T/, cache dir is sibling .../C
  # Needed by Security framework (Spotlight mds) for keychain access
  local cache_dir="${tmpdir%/T*}/C"

  if [[ ! -f "$profile_path" ]]; then
    echo "xclaude: sandbox profile not found at $profile_path" >&2
    return 1
  fi

  if ! command -v sandbox-exec &>/dev/null; then
    echo "xclaude: sandbox-exec not found, running without sandbox" >&2
    claude "$@"
    return
  fi

  sandbox-exec \
    -D "PROJECT_DIR=${project_dir}" \
    -D "TMPDIR=${tmpdir}" \
    -D "CACHE_DIR=${cache_dir}" \
    -D "HOME=${home_dir}" \
    -f "$profile_path" \
    -- claude --dangerously-skip-permissions "$@"
}
