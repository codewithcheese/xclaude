# PostgreSQL local-server toolchain sandbox tests
tc_setup postgres

# ── Usability ──
# Prefer the version used by CI, then accept the current unversioned formula.
# Resolve the prefix outside Seatbelt and use full binary paths inside it.
__pg_prefix=""
if tc_has_cmd brew; then
  __pg_prefix="$(brew --prefix postgresql@17 2>/dev/null || true)"
  if [[ -z "$__pg_prefix" ]]; then
    __pg_prefix="$(brew --prefix postgresql 2>/dev/null || true)"
  fi
fi

if [[ -z "$__pg_prefix" || ! -x "${__pg_prefix}/bin/postgres" ]]; then
  echo "SKIP: PostgreSQL server not found — skipping postgres usability tests" >&2
  tc_cleanup
  return 0 2>/dev/null || exit 0
fi

__pg_initdb="${__pg_prefix}/bin/initdb"
__pg_ctl="${__pg_prefix}/bin/pg_ctl"
__pg_psql="${__pg_prefix}/bin/psql"
__pg_test_dir="${PROJECT_DIR}/postgres-test"
__pg_data_dir="${__pg_test_dir}/data"
# PostgreSQL's macOS Unix-socket path limit is shorter than the runner's
# generated PROJECT_DIR. Use a compact per-run directory under TMPDIR.
__pg_socket_dir="${TMPDIR_RESOLVED}/xpg-$$"
__pg_log="${__pg_test_dir}/postgres.log"
__pg_port=55432

mkdir -p "$__pg_socket_dir"
chmod 700 "$__pg_socket_dir"

t "postgres: initdb"
expect_success "initializes cluster" tc_sandboxed "$__pg_initdb" \
  -D "$__pg_data_dir" -U pg --locale=C -E UTF8 \
  --auth-local=trust --auth-host=reject

t "postgres: pg_ctl start"
expect_success "starts local server" tc_sandboxed "$__pg_ctl" \
  -D "$__pg_data_dir" \
  -o "-F -c listen_addresses='' -c unix_socket_permissions=0700 -p ${__pg_port} -k ${__pg_socket_dir}" \
  -l "$__pg_log" -w start

if [[ -f "${__pg_data_dir}/postmaster.pid" ]]; then
  t "postgres: psql query"
  expect_success "queries local server" tc_sandboxed "$__pg_psql" \
    -h "$__pg_socket_dir" -p "$__pg_port" -U pg -d postgres \
    -v ON_ERROR_STOP=1 -Atqc "SELECT 1"

  t "postgres: pg_ctl stop"
  expect_success "stops local server" tc_sandboxed "$__pg_ctl" \
    -D "$__pg_data_dir" -m fast -w stop
fi

# Do not remove a data directory from beneath a server if the sandboxed stop
# assertion failed. This host-side fallback is test teardown, not a permission
# under evaluation; the failed assertion remains recorded by expect_success.
if [[ -f "${__pg_data_dir}/postmaster.pid" ]]; then
  "$__pg_ctl" -D "$__pg_data_dir" -m immediate -w stop >/dev/null 2>&1 || true
fi

rm -rf "$__pg_test_dir" "$__pg_socket_dir"

# ── Isolation ──
t "postgres: ~/.ssh blocked"
expect_fail "blocked" tc_sandboxed cat "${HOME}/.ssh/known_hosts"

tc_cleanup
