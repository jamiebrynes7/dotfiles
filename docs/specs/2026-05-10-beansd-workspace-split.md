# beansd workspace split — spec

Refactor `packages/beans-daemon/` from a single Rust crate into a Cargo workspace with three crates, encapsulating the UDS control surface behind `Client` and `Handler` so non-RPC code (CLI, launcher, future consumers) doesn't see wire details.

**Status:** approved options doc at `docs/specs/2026-05-10-beansd-workspace-split-options.md` (approach 2). This spec is the implementation contract.

**Parent epic:** `dotfiles-nzsd` (Beans daemon).

---

## Goals

1. Workspace at the repo root, member crates under `crates/`.
2. Three crates: `beansd-rpc`, `beansd`, `beansctl`.
3. The wire format (`WireRequest` / `WireResponse`, newline-delimited JSON) becomes private to `beansd-rpc`. External callers see typed messages.
4. `beansd-rpc::Client` exposes typed sync methods used by `beansctl`.
5. `beansd-rpc::Handler` is an `async_trait` the daemon implements; `beansd-rpc::serve(listener, handler)` runs the dispatch loop. The daemon stops owning per-op JSON envelopes.
6. The 61 existing tests stay green throughout, plus net-new tests for typed responses, error mapping, and end-to-end round-trip via the `beansd-rpc` integration test.

## Non-goals

- Migrating the HTTP launcher to consume `Handler` (out of scope; tracked as a follow-up under the epic).
- Changing the wire format (still newline-delimited JSON).
- Persisting the protocol or breaking compatibility with future `beans-serve` versions (internal protocol, both endpoints are ours).

---

## Layout

```
dotfiles/
  Cargo.toml                        # workspace root
  Cargo.lock
  crates/
    beansd-rpc/
      Cargo.toml
      src/
        lib.rs                      # re-exports
        wire.rs                     # WireRequest, WireResponse (private)
        types.rs                    # pub typed messages + ProjectState
        socket.rs                   # default_socket_path(), bind_uds()
        client.rs                   # pub Client
        server.rs                   # pub Handler trait + serve()
      tests/
        round_trip.rs               # integration: serve(MockHandler) + Client
    beansd/
      Cargo.toml
      src/
        main.rs                     # parse --config, runtime + block_on(run)
        run.rs                      # bind UDS via beansd-rpc, axum::serve launcher
        registry.rs, supervisor.rs, spawner.rs, port_alloc.rs,
        project_key.rs, config.rs, logging.rs, launcher.rs
        handler.rs                  # impl beansd_rpc::Handler for Daemon
      static/htmx.min.js            # moved from packages/beans-daemon/static/
      static/app.css
      templates/index.html
      templates/project_list.html
    beansctl/
      Cargo.toml
      src/
        main.rs                     # clap, build Client, dispatch, format output
  packages/
    beans-daemon/
      default.nix                   # buildRustPackage src=../../; produces beansd + beansctl
```

Workspace root `Cargo.toml`:

```toml
[workspace]
members = ["crates/*"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"

[workspace.dependencies]
anyhow = "1"
async-trait = "0.1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
```

Per-crate `Cargo.toml` uses `{ workspace = true }` for shared deps.

`crates/beansd-rpc/Cargo.toml` deps: anyhow, async-trait, serde, serde_json, tokio, tracing. No app-specific deps.

`crates/beansd/Cargo.toml` deps: above + askama, axum, clap, nix, reqwest, thiserror, tokio-util, toml, tracing-subscriber, xdg, beansd-rpc (path).

`crates/beansctl/Cargo.toml` deps: anyhow, clap, serde_json (for pretty-printing), beansd-rpc (path).

Dependency direction: `beansctl → beansd-rpc`, `beansd → beansd-rpc`. No cycles.

---

## `beansd-rpc`

### `wire` (private to crate)

Identical to today's `protocol.rs`:

```rust
#[derive(Serialize, Deserialize)]
#[serde(tag = "op", content = "args", rename_all = "snake_case")]
pub(crate) enum WireRequest {
    Cd        { cwd: PathBuf },
    Ls        {},
    Start     { key: PathBuf },
    Stop      { key: PathBuf },
    Status    {},
    Heartbeat { key: PathBuf },
}

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
pub(crate) enum WireResponse {
    Ok    { ok: bool, data: serde_json::Value },     // ok=true
    Error { ok: bool, error: String },               // ok=false
}

impl WireResponse {
    pub(crate) fn ok(data: serde_json::Value) -> Self { ... }
    pub(crate) fn err(msg: impl Into<String>) -> Self { ... }
}
```

`pub(crate)` so they don't leak through `lib.rs`.

### `types` (pub)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ProjectState { Spawning, Healthy, Evicting, Dead }

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct ProjectSummary {
    pub key:          PathBuf,
    pub display_name: String,
    pub state:        ProjectState,
    pub port:         Option<u16>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum CdResponse {
    NotRegistered,
    Bumped  { key: PathBuf },
    Spawned { key: PathBuf },
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct LsResponse { pub projects: Vec<ProjectSummary> }

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum StartResponse { AlreadyActive, Spawning }

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct StatusResponse {
    pub registry_size: usize,
    pub active:        usize,
    pub lru_cap:       usize,
}
```

- `Heartbeat`'s response is `()` — drop today's `{"bumped": true}` envelope.
- `Stop`'s response is `()` — bad-input failures (unknown project) bubble as `Err`, leaving no info worth wrapping in a struct.
- `Start`'s response is the bare enum `StartResponse`. Same reasoning: bad input is `Err`.
- `Cd`'s response is the sum type `CdResponse` — three legitimate non-error outcomes, modeled as variants so callers can't construct invalid combinations (`registered: false, action: Some(Bumped)` etc.). The `tag = "outcome"` adjacent attribute keeps the wire form `{"outcome":"bumped","key":"/x"}` shape-stable; `NotRegistered` serialises as `{"outcome":"not_registered"}`.

### `socket` (pub)

`default_socket_path() -> anyhow::Result<PathBuf>` and `bind_uds(&Path) -> anyhow::Result<UnixListener>`, lifted from today's `control.rs` unchanged.

### `client` (pub)

```rust
pub struct Client { socket: PathBuf }

impl Client {
    /// Probe the daemon at the default socket path. Returns Err if the
    /// daemon isn't reachable.
    pub fn connect() -> anyhow::Result<Self>;

    /// Probe the daemon at a specific socket path.
    pub fn connect_to(socket: PathBuf) -> anyhow::Result<Self>;

    /// Fire-and-forget: write the request, half-close the write side, return.
    /// The daemon still writes a response; the kernel discards it. Errors at
    /// connect or write surface here. Silencing for non-interactive callers
    /// (chpwd hook) is the shell wrapper's responsibility.
    pub fn cd(&self, cwd: PathBuf) -> anyhow::Result<()>;

    pub fn ls(&self)                    -> anyhow::Result<LsResponse>;
    pub fn start(&self, key: PathBuf)   -> anyhow::Result<StartResponse>;
    pub fn stop(&self, key: PathBuf)    -> anyhow::Result<()>;
    pub fn status(&self)                -> anyhow::Result<StatusResponse>;
    pub fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()>;
}
```

Implementation notes:

- `connect[_to]` opens a `UnixStream` and immediately drops it. If the open succeeds, store the path. Subsequent calls open fresh streams.
- Each non-`cd` method:
  1. Open `UnixStream`.
  2. Serialise `WireRequest::<Op>` + `\n`, `write_all`.
  3. `shutdown(Shutdown::Write)`.
  4. `BufReader::read_line` → one line.
  5. If `read_line` returned `Ok(0)` (no bytes, no newline) → `Err(anyhow!("daemon closed connection without responding"))`.
  6. `serde_json::from_str::<WireResponse>(&line)`. On parse error → wrap with context: `Err(anyhow!("malformed response from daemon: {e}"))`.
  7. Match: `WireResponse::Ok { data, .. }` → `serde_json::from_value::<T>(data).context("decoding {op} response")`. `WireResponse::Error { error, .. }` → `Err(anyhow!("{error}").context(format!("rpc {op}")))`.
- `cd` skips steps 4–7 entirely. Errors at step 1 / 2 / 3 propagate.

### `server` (pub)

```rust
#[async_trait]
pub trait Handler: Send + Sync + 'static {
    async fn cd(&self, cwd: PathBuf)        -> anyhow::Result<CdResponse>;
    async fn ls(&self)                       -> anyhow::Result<LsResponse>;
    async fn start(&self, key: PathBuf)     -> anyhow::Result<StartResponse>;
    async fn stop(&self, key: PathBuf)      -> anyhow::Result<()>;
    async fn status(&self)                   -> anyhow::Result<StatusResponse>;
    async fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()>;
}

/// Run the UDS dispatch loop. Each accepted connection runs on its own
/// tokio task. One connection may carry many requests, one per line.
pub async fn serve<H: Handler>(
    listener: UnixListener,
    handler: Arc<H>,
) -> anyhow::Result<()>;
```

Per-connection task body (extracted from today's `handle_connection`):

```text
loop on next_line:
    parse WireRequest
        on parse error: write WireResponse::Error { error: format!("bad request: {e}") }; continue
    match request:
        Cd { cwd }       -> handler.cd(cwd).await
        Ls {}            -> handler.ls().await
        Start { key }    -> handler.start(key).await
        Stop { key }     -> handler.stop(key).await
        Status {}        -> handler.status().await
        Heartbeat { key} -> handler.heartbeat(key).await; produces ()
    convert Result<T> to WireResponse:
        Ok(t)  -> WireResponse::ok(serde_json::to_value(t)?)
        Err(e) -> WireResponse::err(format!("{e:#}"))
    write WireResponse + '\n'  (best-effort; ignore EPIPE)
```

Heartbeat's `Ok(())` serialises as `serde_json::Value::Null` so the wire envelope is `{"ok":true,"data":null}` — the client discards `data` for heartbeat.

### `lib.rs`

```rust
mod wire;
mod client;
mod server;
mod socket;
mod types;

pub use client::Client;
pub use server::{Handler, serve};
pub use socket::{default_socket_path, bind_uds};
pub use types::*;
```

---

## `beansd`

### `handler.rs` (new)

```rust
#[async_trait]
impl<S: ChildSpawner + 'static> beansd_rpc::Handler for Daemon<S> {
    async fn cd(&self, cwd: PathBuf) -> anyhow::Result<CdResponse> { ... }
    async fn ls(&self) -> anyhow::Result<LsResponse> { ... }
    async fn start(&self, key: PathBuf) -> anyhow::Result<StartResponse> { ... }
    async fn stop(&self, key: PathBuf) -> anyhow::Result<()> { ... }
    async fn status(&self) -> anyhow::Result<StatusResponse> { ... }
    async fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()> { ... }
}
```

Bodies are today's `Daemon::handle_*` rewritten:

- **`cd`**: `project_key::resolve` errors propagate as `Err` (today swallowed into `error: Option<String>`). On `Ok(None)` (no marker) → `Ok(CdResponse::NotRegistered)`. On `Ok(Some(key))` already-registered → bump + `Ok(CdResponse::Bumped { key })`. On not-registered → eviction trigger if at cap, insert `Spawning`, spawn `start_project_with_retries`, `Ok(CdResponse::Spawned { key })`.
- **`ls`** / **`status`**: today's bodies, returning typed.
- **`heartbeat`**: today's body minus the `{"bumped": true}` wrapper. Returns `Ok(())`.
- **`stop`**: missing key → `Err(anyhow!("unknown project: {}", key.display()))`. Otherwise `trigger_eviction` + `Ok(())`.
- **`start`**: missing key → `Err(anyhow!("unknown project: {}", key.display()))`. `Healthy`/`Spawning` → `Ok(StartResponse::AlreadyActive)`. Otherwise transition `Spawning` + spawn retries + `Ok(StartResponse::Spawning)`.

### `run.rs` (modified)

Replace `daemon.serve_uds(uds_listener)` with `beansd_rpc::serve(uds_listener, daemon.clone())`. Drop `Daemon::serve_uds` and `Daemon::handle_connection` from `control.rs` (now lives in `beansd-rpc::server`).

### `control.rs` (deleted)

Contents redistributed:

- `Daemon` struct → split: data fields move to a new `daemon.rs`, the `handle_*` methods become the `Handler` impl in `handler.rs`.
- `bind_uds`, `default_socket_path` → moved to `beansd-rpc::socket`.
- `serve_uds`, `handle_connection` → moved to `beansd-rpc::server::serve`.

### `launcher.rs` (minimal change)

Today the launcher calls `daemon.handle_heartbeat(...)` etc. and ignores the `serde_json::Value` payload. After the refactor the same call sites use the trait methods — `daemon.heartbeat(key).await`, `daemon.start(key).await`, `daemon.stop(key).await` — with three concrete behaviour changes:

- Each call now returns `Result`. Map `Err(_)` → `StatusCode::INTERNAL_SERVER_ERROR`. (In practice these errors are bad-input; the launcher's HTML form ought not produce them, but if it does, returning 500 is honest.)
- `daemon.heartbeat(...).await?` returns `()`; the route still returns `204`.
- `daemon.start/stop(...).await?` return typed values that the launcher already discards (it re-renders the partial).

The launcher's `LauncherState<S: ChildSpawner>` is unchanged. Migration to `Arc<dyn Handler>` is non-goal (filed as follow-up).

### `main.rs` (simplified)

CLI shrinks to the daemon-only subcommand. The other arms (`Cd`, `Ls`, `Start`, `Stop`, `Status`) move to `beansctl`. After this refactor `beansd`'s clap surface is just `Run` — and since `Run` is the only thing it does, drop the subcommand entirely:

```rust
fn main() -> anyhow::Result<()> {
    let _ = Cli::parse();   // accepts --config <path> in future; currently no flags
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run::run())
}
```

Service files (launchd / systemd-user, future work) invoke `beansd` directly — no `beansd run`. Update the existing `dotfiles-ottn` (home-manager module) feature's body to reflect this when that work picks up.

---

## `beansctl`

```rust
fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let client = beansd_rpc::Client::connect()?;
    match cli.command {
        Command::Cd { dir }       => client.cd(dir),
        Command::Ls               => print_ls(client.ls()?),
        Command::Start { key }    => print_start(client.start(key)?),
        Command::Stop  { key }    => print_stop(client.stop(key)?),
        Command::Status           => print_status(client.status()?),
        Command::Heartbeat { key }=> client.heartbeat(key),
    }
}
```

`print_*` helpers format the typed response for human consumption — for now, `serde_json::to_string_pretty(&resp)` to keep parity with today's output. (A nicer table layout for `ls` is filable as follow-up.)

`Heartbeat` is added as a CLI subcommand (currently only the launcher heartbeats). Useful for editor integrations and diagnostics.

`cli_client.rs` and `print_response` from today's `beansd/src/main.rs` are deleted; their functionality is in `beansd-rpc::Client` and `beansctl::print_*`.

---

## Error handling

| Boundary | Failure mode | Behavior |
|---|---|---|
| `Client::connect[_to]` | socket missing / no listener | `Err` from `UnixStream::connect`, message includes the socket path |
| `Client::<op>` open | daemon died after connect | per-call `Err` from `UnixStream::connect` |
| `Client::<op>` write | EPIPE mid-write | per-call `Err` |
| `Client::<op>` read | daemon dropped without responding | `read_line` returns `Ok(0)` → `Err(anyhow!("daemon closed connection without responding"))` |
| `Client::<op>` parse | malformed response from daemon | `Err(anyhow!("malformed response from daemon: {e}"))` |
| `WireResponse::Error` | handler returned `Err` | `Err(anyhow!("{error}").context(format!("rpc {op}")))` |
| `serve` parse | malformed line from client | write `WireResponse::Error { error: "bad request: …" }`, continue connection (per-message error, not connection-fatal) |
| `serve` write | EPIPE (client closed early, e.g. `cd`) | `let _ = wr.write_all(&buf).await;` (best-effort, today's behavior) |
| `Handler::Err` | system / bad-input | `serve` writes `WireResponse::Error { error: format!("{e:#}") }` |
| Handler panic | bug | propagates to per-connection task; tokio's `JoinHandle` triggers today's `tracing::warn!("UDS connection ended with error")` |

`{:#}` is anyhow's alternate Display — flattens the cause chain inline so `Err(io_err).context("opening foo").context("listing projects")` round-trips as `listing projects: opening foo: <io error>` in a single response line.

---

## Test plan

### Per-crate unit tests

| Module | Test | Coverage |
|---|---|---|
| `beansd-rpc::wire` | round-trip `WireRequest::Cd` | unchanged from today's `protocol::tests` |
| `beansd-rpc::wire` | round-trip `WireRequest::Ls` (empty args) | unchanged |
| `beansd-rpc::wire` | `ok` and `err` constructors serialise correctly | unchanged |
| `beansd-rpc::types` | round-trip each typed response | new — catches drift between typed shape and `serde_json::to_value` output |
| `beansd-rpc::types` | `ProjectState` snake_case wire form | new |
| `beansd-rpc::socket` | `bind_uds` perms 0600 | unchanged from `control::tests` |
| `beansd-rpc::socket` | `bind_uds` unlinks stale socket | unchanged |
| `beansd-rpc::socket` | `bind_uds` refuses live socket | unchanged |
| `beansd-rpc::client` | request round-trip via in-process echo | adapted from `cli_client::tests` |
| `beansd-rpc::client` | `cd` is silent at protocol level | new — verifies write + half-close, no read |
| `beansd-rpc::client` | empty response → "daemon closed connection" | new |
| `beansd-rpc::client` | malformed response → "malformed response from daemon" | new |
| `beansd-rpc::client` | `WireResponse::Error` → `Err` with rpc context | new |
| `beansd-rpc::server` | dispatch routes each op to the right handler method | new; uses `MockHandler` |
| `beansd-rpc::server` | handler `Err` → `WireResponse::Error` with `{:#}` chain | new |
| `beansd-rpc::server` | malformed request → continue connection | new (mirrors today's behavior) |
| `beansd::handler` | `cd` no marker → `CdResponse::NotRegistered` | adapted from `cd_tests` |
| `beansd::handler` | `cd` marked dir → `CdResponse::Spawned { key }`, eventually `Healthy` | adapted |
| `beansd::handler` | `cd` resolve I/O error → `Err` | new (today swallowed into in-band error) |
| `beansd::handler` | `ls` empty | adapted |
| `beansd::handler` | `heartbeat` bumps `last_used` | adapted |
| `beansd::handler` | `status` shape | adapted |
| `beansd::handler` | `stop` unknown → `Err` (was in-band error) | adapted |
| `beansd::handler` | `start` unknown → `Err` (was in-band error) | adapted |
| `beansd::handler` | `start` already healthy → `Ok(StartResponse::AlreadyActive)` | adapted |
| `beansd::launcher` | unchanged 8 tests, except call sites use typed returns | regression |
| `beansd::{registry,supervisor,config,...}` | unchanged | regression |

### Integration test: `crates/beansd-rpc/tests/round_trip.rs`

Real `bind_uds` + `serve(MockHandler)` + `Client::connect_to`, one test per op:

1. `cd` (fire-and-forget, asserts daemon side received the request)
2. `ls`
3. `start`
4. `stop`
5. `status`
6. `heartbeat`
7. handler error → client sees `Err` with the original message

`MockHandler` is a stub that records calls and returns canned responses.

### Migration safety net

The 61 existing tests are the regression suite. Per task:

1. **Workspace move.** No API change, only file paths. All 61 still pass.
2. **Extract `beansd-rpc` skeleton.** Wire + socket carve-out. All 61 still pass; some tests now live in the new crate.
3. **Add typed messages + `Handler` + `serve`.** Pure addition in `beansd-rpc`; daemon untouched. All 61 still pass; new mock-based `serve` tests added.
4. **Daemon implements Handler typed.** `cd_tests` and `handler_tests` rewritten to assert typed values. Net test count grows.
5. **Client + beansctl.** `cli_client::tests` migrate to `beansd-rpc::client::tests` and grow new edge-case tests. Integration round-trip test lands here.

### Out of scope

- Property-based / fuzz tests on the wire parser.
- HTTP launcher migration to `Arc<dyn Handler>`.
- Performance benchmarks.

---

## Nix integration

`packages/beans-daemon/default.nix` becomes a single `rustPlatform.buildRustPackage`. The build needs the Rust source tree, but `src = ../..` would point at the entire repo — every edit to `docs/`, `.beans/`, `home/`, `darwin/`, or sibling `packages/*` would invalidate the derivation hash and trigger an unrelated rebuild. Filter the source down with `lib.fileset.toSource` to just the workspace files:

```nix
{ lib, rustPlatform, ... }:

let
  root = ../..;
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/Cargo.toml")
      (root + "/Cargo.lock")
      (root + "/crates")
    ];
  };
in
rustPlatform.buildRustPackage {
  pname = "beans-daemon";
  version = "0.1.0";
  inherit src;
  cargoLock.lockFile = root + "/Cargo.lock";
  cargoBuildFlags = [ "--workspace" ];
  # produces $out/bin/{beansd,beansctl}
}
```

Adding/removing a workspace member requires editing the `fileset.unions` list, but for the foreseeable future this is a 3-line list.

Open question for the home-manager work (out of scope here): should `beansctl` ship as a separate Nix derivation so `home.packages` can include it without pulling the whole daemon binary into the user profile? Defer; flag in the home-manager bean.

---

## Migration plan (tasks)

Five tasks under a new feature bean (parent `dotfiles-nzsd`, sibling to `dotfiles-2ecf`):

1. **Workspace skeleton** — root `Cargo.toml`, move `packages/beans-daemon/{src,static,templates,Cargo.toml,Cargo.lock}` to `crates/beansd/`, update `packages/beans-daemon/default.nix` for the new layout. Verify `cargo test --workspace` passes (61/61) and `nix build` succeeds. No API changes.
2. **Extract `beansd-rpc` skeleton: wire + socket** — pure carve-out. Move `protocol.rs` to `crates/beansd-rpc/src/wire.rs` (renamed types stay private to the crate; re-exported via the typed step later). Move `control.rs::{default_socket_path, bind_uds}` to `crates/beansd-rpc/src/socket.rs`. `beansd` depends on `beansd-rpc`; `cli_client.rs` still in `beansd` and imports from `beansd-rpc`. All 61 tests still pass; some now run in the new crate.
3. **Add typed messages + `Handler` trait + `serve`** — define `crates/beansd-rpc/src/types.rs` (typed messages exactly as in this spec) and `crates/beansd-rpc/src/server.rs` (Handler trait + `serve` fn). Tests in this step are mock-based: `MockHandler` records calls, `serve` is exercised against an in-process listener. No daemon changes yet.
4. **Daemon implements Handler typed; `run.rs` uses `serve`** — add `crates/beansd/src/handler.rs` with `impl Handler for Daemon<S>` per this spec's bodies. Modify `run.rs` to call `beansd_rpc::serve(listener, daemon.clone())`. Delete `Daemon::serve_uds`, `Daemon::handle_connection`, and `Daemon::handle_*` methods (their bodies live in the Handler impl now). Rewrite today's `cd_tests` and `handler_tests` to assert typed values. Update `launcher.rs` call sites for the trait methods. `control.rs` reduced to nothing (file deleted, `Daemon` struct moves to a new `daemon.rs`).
5. **Add `Client`; extract `beansctl`** — implement `crates/beansd-rpc/src/client.rs` with the API in this spec, plus tests (round-trip via in-process echo, the empty-response and malformed-response edges). Add `crates/beansd-rpc/tests/round_trip.rs` integration test exercising real `bind_uds` + `serve(MockHandler)` + `Client::connect_to`, one assertion per op. Create `crates/beansctl/` with the `main.rs` from this spec. Delete `cli_client.rs` from `beansd` and the `Cd/Ls/Start/Stop/Status` arms from `beansd::main`. Reduce `beansd::main` to its single-purpose form. Add a `Heartbeat` subcommand to `beansctl`.

Each task is its own commit, runs `cargo test --workspace`, ends green.

## Acceptance

- `cargo test --workspace` green: 61 existing + new tests (~15 in `beansd-rpc`, ~7 integration round-trip, plus typed-response unit tests).
- `nix build .#beans-daemon` produces `$out/bin/beansd` and `$out/bin/beansctl`.
- `beansctl status` against a running daemon prints typed JSON.
- `beansctl cd /tmp/no-marker` exits 0 silently when wrapped in shell `2>/dev/null || true`; exits 1 with a clear "daemon not running" message when the daemon is down (the wrapper's `|| true` masks that exit code in the chpwd hook context — that's intentional, the daemon being down is not a shell-prompt-disrupting event).
- The HTTP launcher continues to serve the same content; existing 8 launcher tests pass.
