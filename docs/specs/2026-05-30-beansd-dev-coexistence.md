# beansd dev/prod coexistence via a `--dev` flag

Date: 2026-05-30

## Problem

`beansd` is developed on the same machine that runs the production daemon
(launchd-managed, `KeepAlive = true`). A dev build can't coexist with prod
because three resources are fixed or shared:

- **Socket** — `beansd_rpc::default_socket_path()` is fixed, and `bind_uds`
  refuses to clobber a live socket (`crates/beansd-rpc/src/socket.rs`), so a dev
  daemon can't bind while prod holds the canonical path.
- **Launcher port** — defaults to 9000 (`crates/beansd/src/config.rs`), bound in
  `web::Server::bind` (`crates/beansd/src/run.rs:45`); two daemons collide.
- **Config file** — both read `$XDG_CONFIG_HOME/beans-daemon/config.toml`.

Every client (`beansctl`, the zsh `chpwd` hook, the Claude `beans prime` hooks)
connects to the one canonical socket, so a dev CLI cannot reach a dev daemon.

## Goal

Run a dev `beansd` alongside prod, on its own socket + launcher port, with dev
clients routed to it — selected by an **explicit, visible** flag, not by build
profile or ambient environment. State collision between the two daemons (same
project `.beans.yml` data) is explicitly **not** a concern.

## Non-goals

- Multiple named dev instances (`dev2`, scratch daemons). One dev instance.
- A second launchd/systemd agent for the dev daemon — it is always run manually
  via `cargo run -- --dev`.
- Changing how prod is deployed or how the hooks invoke the Nix-built binaries.
- Isolating dev/prod project data.

## Design

A global `--dev` flag on both binaries shifts the two per-instance coordinates
(socket path and daemon config path). Prod and the hooks never pass `--dev`, so
they are untouched.

### 1. Socket path — `beansd-rpc`

Change the signature to take the flavor explicitly:

```rust
pub fn default_socket_path(dev: bool) -> anyhow::Result<PathBuf>
```

When `dev`, append a `-dev` suffix to the canonical file name:

- macOS: `…/Library/Caches/beans-daemon/sock` → `…/sock-dev`
- Linux: `$XDG_RUNTIME_DIR/beans-daemon.sock` →
  `$XDG_RUNTIME_DIR/beans-daemon-dev.sock`

`bind_uds` is unchanged — it receives whichever path it's given. Because both
binaries call this same function, a dev daemon and a dev CLI independently
resolve the identical dev path and find each other with no coordination.

### 2. `beansd` — parse `--dev`, thread it through

`beansd` has no argument parsing today (`main()` just runs `run::run()`). Add a
minimal clap parser (`clap` is already a workspace dependency, used by
`beansctl`):

```rust
#[derive(clap::Parser)]
#[command(name = "beansd", version)]
struct Cli {
    /// Use the dev instance: dev socket + repo-local dev-config.toml.
    #[arg(long)]
    dev: bool,
}
```

`main()` parses it and calls `run::run(cli.dev)`. In `run.rs`:

- line 14: `Config::load(&Config::default_path(dev)?)?`
- line 37: `default_socket_path(dev)?`

### 3. `beansctl` — global `--dev`, route the client

`beansctl` already uses clap. Add a global flag so it can precede any subcommand:

```rust
#[arg(long, global = true)]
dev: bool,
```

Route the connection:

```rust
let client = if cli.dev {
    Client::connect_to(beansd_rpc::default_socket_path(true)?)?
} else {
    Client::connect()?
};
```

(`Client::connect()` already resolves `default_socket_path(false)` internally;
its signature updates to pass `false`.)

### 4. Repo-local dev config

A checked-in `crates/beansd/dev-config.toml`:

```toml
launcher_port  = 9001
lru_cap        = 8
heartbeat_secs = 15
log_level      = "debug"
# beans_serve_path omitted — resolved from $PATH (see §5)
```

`Config::default_path` takes the flavor:

```rust
pub fn default_path(dev: bool) -> anyhow::Result<PathBuf>
```

- `dev == false`: today's behavior — `$XDG_CONFIG_HOME/beans-daemon/config.toml`.
- `dev == true`: the repo-local file, resolved from the crate's compile-time
  source directory so it is independent of the working directory:
  `concat!(env!("CARGO_MANIFEST_DIR"), "/dev-config.toml")`.

The Nix release binary bakes its build-sandbox path into that constant, but the
string is dead code there — `--dev` is never passed to the prod binary.

### 5. Optional `beans_serve_path` with `$PATH` fallback

`beans_serve_path` is a `/nix/store/...` path in prod and would go stale in a
hand-maintained dev config on every `beans` rebuild. To make the dev config
immune to store churn, make the field optional and fall back to `$PATH`:

```rust
pub beans_serve_path: Option<PathBuf>,   // was PathBuf
```

Add resolution:

```rust
/// The explicit beans_serve_path, or the first `beans-serve` on $PATH.
pub fn resolve_beans_serve(&self) -> anyhow::Result<PathBuf>
```

- `Some(p)` → return `p`.
- `None` → resolve `beans-serve` on `$PATH` via the `which` crate, added to
  `[workspace.dependencies]` in the root `Cargo.toml` and inherited by `beansd`.
  Error if none found:
  `"beans-serve not found on $PATH; set beans_serve_path in dev-config.toml"`.

`run.rs` calls `resolve_beans_serve()` once to build `BeansServeSpawner`, and
`validate()` runs its is-file / is-executable checks against the **resolved**
path. The home-manager-rendered prod `config.toml` keeps setting
`beans_serve_path`, so prod behavior is unchanged.

### Dev workflow

```sh
# terminal 1 — dev daemon: dev socket + dev-config.toml + port 9001
cargo run -p beansd -- --dev

# terminal 2 — dev CLI talks to the dev daemon
cargo run -p beansctl -- --dev ls
cargo run -p beansctl -- --dev status
```

Prod (launchd) and the chpwd/prime hooks invoke the Nix binaries without
`--dev`, so they continue to use the canonical socket, config, and port 9000.

## Error handling

- Forgetting `--dev` on one side: a dev `beansctl` without the flag connects to
  prod. This is loud and intentional — explicitness is the chosen trade-off over
  ambient env routing.
- No `beans-serve` resolvable in dev: `resolve_beans_serve()` fails with the
  message above before the daemon binds anything.
- Dev socket already held by another dev daemon: existing `bind_uds`
  "already in use by a live daemon" error applies unchanged.

## Testing

Colocated `#[cfg(test)]` modules, per `crates/CLAUDE.md`:

- `socket.rs`: `default_socket_path(true)` yields the `-dev` path;
  `default_socket_path(false)` yields today's path (locks the shared contract).
- `config.rs`: `beans_serve_path` omitted → parses to `None`; present → `Some`.
  Existing `Config { .. }` literals updated to wrap the path in `Some(..)`.
- `config.rs`: `resolve_beans_serve()` returns the explicit path when set; finds
  an executable `beans-serve` placed in a temp dir prepended to `$PATH`; errors
  when absent.
- `config.rs`: `default_path(true)` ends in `dev-config.toml`.

## Files touched

- `crates/beansd-rpc/src/socket.rs` — `default_socket_path(dev)`.
- `crates/beansd-rpc/src/client.rs` — `connect()` passes `false`.
- `crates/beansd/src/main.rs` — clap `Cli`, pass `dev` to `run`.
- `crates/beansd/src/run.rs` — thread `dev` into the two calls; resolve serve
  path.
- `crates/beansd/src/config.rs` — `default_path(dev)`, optional
  `beans_serve_path`, `resolve_beans_serve()`.
- `crates/beansd/src/spawner.rs` — consume the resolved path (if it currently
  reads `cfg.beans_serve_path` directly).
- `crates/beansctl/src/main.rs` — global `--dev`, route client.
- `Cargo.toml` (root) — add `which` to `[workspace.dependencies]`;
  `crates/beansd/Cargo.toml` inherits it.
- `crates/beansd/dev-config.toml` — new checked-in dev config.
- `crates/CLAUDE.md` — document the `--dev` dev workflow.

## Out of scope / future

- Rendering the dev config from home-manager (rejected: keep dev-only, in repo).
- Multiple dev instances / named instances.
