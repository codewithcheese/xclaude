# pnpm configuration and sandbox scope

`tool node` supports Node/npm installations under NVM, Corepack caches,
and pnpm's macOS dependency and package-manager caches. Wrangler packs
can include `tool node`; pnpm permissions belong in the toolchain, not
in the Wrangler pack or the base profile.

## Why the older rules failed

The April 2026 toolchain described pnpm as running through Corepack and
covered `~/.local/share/pnpm` and `~/.pnpm-store`, but omitted the macOS
data directory `~/Library/pnpm`.

The September 2026 investigation used a native pnpm 12.3.4 executable
installed by npm under NVM and a project pinning `pnpm@10.34.1`.
NVM execution was already allowed. The failure occurred when pnpm tried
to read and replace its version-switch lockfile before starting the
project's CLI. A temporary pnpm home was not a persistent solution: it
discarded access to the user's existing managed versions and global tools.

Relevant upstream changes:

- [pnpm 11](https://github.com/pnpm/pnpm.io/blob/main/blog/releases/11.0.md)
  changed configuration to YAML, introduced `pmOnFail`, and moved global
  binaries into `PNPM_HOME/bin`.
- [pnpm 12](https://github.com/pnpm/pnpm.io/blob/main/blog/releases/12.0.md)
  rewrote the CLI in Rust. An npm installation can now contain a native
  executable; installing through npm does not imply running through Corepack.
- The [12.3.4 engine installer](https://github.com/pnpm/pnpm/blob/v12.3.4/pnpm/crates/cli/src/engine_pm/install.rs)
  uses `package-manager-store` independently of the normal dependency
  `storeDir`. Its pnpm engine lockfile lives under `global/v11`, even in v12.

## macOS permissions

| Path under home | Access | Purpose |
|---|---|---|
| `Library/pnpm/store` | Read, write, exec | Dependency content and executable packages |
| `Library/pnpm/package-manager-store` | Read, write, exec | Downloaded version-pinned package managers, indexes and install locks |
| `Library/pnpm/.tools/pnpm` | Read, write, exec | pnpm 10 managed versions |
| `Library/pnpm/global/v11/pnpm-lock.yaml` | Read, write | pnpm version-switch integrity metadata |
| `Library/pnpm/global/v11/.tmp…` | Read, write | Atomic lockfile replacement; direct children only |
| `.pnpm-state` | Read, write | macOS update-check state |
| `Library/Preferences/pnpm`, `.config/pnpm` | Read only | User configuration |

Parent directory creation is allowed where needed. These macOS additions
do not grant writes to global app installations or global bin shims, nor
execution from configuration or update-check state. Installing a global
CLI remains a separate permission decision. Existing legacy/XDG rules
are retained.

Shared writable executable caches allow a sandboxed process to alter
cached code that another project may later execute. This is the same
trade-off as the toolchain's npm/npx caches; enable it only for projects
you trust with these shared caches. The engine lockfile is also writable
state, not an integrity boundary against code already inside the sandbox.

## Correct pnpm configuration

On macOS, pnpm 11+ reads general settings from
`~/Library/Preferences/pnpm/config.yaml`, or
`$XDG_CONFIG_HOME/pnpm/config.yaml` when configured.
The adjacent `rc` file is for registry/auth settings. See
[pnpm config](https://pnpm.io/cli/config).

For example, to retain an older `node-linker=hoisted` preference:

```yaml
# ~/Library/Preferences/pnpm/config.yaml
nodeLinker: hoisted
```

Projects still using pnpm 10 may need the legacy `rc` setting too.
Do not change linker strategy merely to work around a sandbox denial.

`PNPM_HOME="$HOME/Library/pnpm"` matches the macOS data layout. With pnpm
11+, put `$PNPM_HOME/bin` on PATH for global commands. A custom `pnpmHomeDir`
belongs in trusted user configuration or CLI options, not a project's
`pnpm-workspace.yaml`. Changing `storeDir` alone does not relocate the
package-manager store.

Keep the project's `packageManager` pin. The default
[`pmOnFail: download`](https://pnpm.io/settings/cli#pmonfail) runs that version.
`pmOnFail: ignore` intentionally bypasses the pin; it is not a sandbox fix.
The old `managePackageManagerVersions` setting and `npm_config_*` settings
are replaced by `pmOnFail` and `pnpm_config_*` in pnpm 11+.

Current pnpm defaults
[`verifyDepsBeforeRun`](https://pnpm.io/settings/build#verifydepsbeforerun)
to `install`, so even `pnpm <local-cli> --version` can reinstall stale
dependencies. For diagnostics that should fail instead of reinstalling:

```yaml
verifyDepsBeforeRun: error
```

Use disposable projects for testing version changes. Do not bypass the
project pin to test an existing project's dependencies with another major.

## Verification

Run `zsh test_sandbox.zsh --toolchain node` on macOS. Tests cover cache
access, protected global/config paths, installs, local CLI dispatch,
`dlx`, and a project pin to pnpm 10.34.1. GitHub Actions workflows are
temporarily disabled; run these checks locally.
