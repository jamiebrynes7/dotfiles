# beansd workspace split — options

Refactoring the single `packages/beans-daemon/` crate into a Cargo workspace with three crates, encapsulating the UDS control surface behind `Client` and `Handler` types so non-RPC code (CLI, launcher, future consumers) doesn't see wire details.

**Settled decisions** (from preceding brainstorm):
- Workspace root `dotfiles/Cargo.toml`, member crates under `dotfiles/crates/`.
- Daemon crate + binary stays `beansd`. CLI is `beansctl`. RPC crate is `beansd-rpc`.
- One Nix derivation at `packages/beans-daemon/default.nix` building both binaries; `packages/beans/` (issue tracker wrapper) is unrelated.

The three approaches below differ on **how much abstraction work to take on alongside the split**.

---

## Approach 1: Split only — keep current JSON-blob API

Just restructure the existing code into three crates with no API changes. `beansd-rpc` is essentially today's `protocol.rs` plus `default_socket_path`, `bind_uds`, `cli_client::{request, send_and_close}`, and `Daemon::serve_uds` lifted out as a free function. Daemon handlers still return `serde_json::Value`. CLI still parses responses ad-hoc.

**Layout:**
```
crates/
  beansd-rpc/      Request/Response types, default_socket_path, bind_uds,
                   request(), send_and_close(), serve_uds(listener, daemon)
  beansctl/        clap CLI; calls request()/send_and_close() directly
  beansd/          Daemon, Registry, Supervisor, launcher, run, etc.
```

**Pros:**
- Smallest diff. ~all moves, near-zero new code.
- Easy to land in one or two commits.
- Tests carry over unchanged.

**Cons:**
- Doesn't address the actual motivation. CLI keeps reaching into `resp["projects"][0]["port"]`. `serde_json::Value` blobs cross every boundary.
- `serve_uds` as a free function on `&Daemon` re-exposes Daemon to the rpc crate — boundaries don't get cleaner.
- We'd be back here in a month doing approach 2 anyway.

---

## Approach 2: Split + `Client`/`Handler` abstraction (recommended)

The brief as described. `beansd-rpc` defines:

- **Wire types** — internal: `enum WireRequest`, `enum WireResponse` with serde derives. Not pub.
- **Typed message types** — pub: `LsResponse { projects: Vec<ProjectSummary> }`, `CdResponse { registered: bool, action: Option<&'static str> }`, etc.
- **Socket helpers** — `default_socket_path() -> Result<PathBuf>`, `bind_uds(&Path) -> Result<UnixListener>`.
- **`Client`** — sync UDS client. `Client::connect_default() -> Result<Client>`. Methods: `cd(PathBuf)` (fire-and-forget), `ls() -> Result<LsResponse>`, `start/stop(PathBuf) -> Result<...>`, `status() -> Result<StatusResponse>`, `heartbeat(PathBuf) -> Result<()>`.
- **`Handler` trait** — `#[async_trait] pub trait Handler: Send + Sync + 'static { async fn cd(...) -> CdResponse; async fn ls(...) -> LsResponse; ... }`.
- **`serve(listener, handler) -> Result<()>`** — accept loop + per-connection task + line framing + dispatch over the trait, returning typed responses serialised to `WireResponse`.

`beansd` then implements `Handler for Daemon` (the body of each method is what's currently inside `handle_cd`/`handle_ls`/etc., but typed), and `run.rs` calls `beansd_rpc::serve(listener, daemon)` instead of `daemon.serve_uds(listener)`.

`beansctl` becomes ~150 lines: clap, build a `Client`, dispatch, format. The whole `cli_client.rs` and `print_response` helper disappear.

**Pros:**
- Wire format is encapsulated. We can change framing or add fields without touching `beansctl` or `Daemon`.
- Typed responses make the CLI and any future consumer (editor plugin, scripts) actually pleasant to write.
- `Handler` trait lets the daemon be tested without a UDS listener — already half-true via `Daemon::handle_*` but now contractual.
- Sets up the launcher migration in approach 3 as a small follow-up rather than another refactor.

**Cons:**
- Real surface-area change: ~6 typed response structs, ~6 trait methods, plus the dispatch glue.
- The launcher keeps its current direct dependency on `Daemon::handle_heartbeat` / `handle_start` / `handle_stop` (because it needs `Arc<Daemon<S>>` for the `LauncherState`). So `Daemon` remains pub at the daemon-crate boundary even though `serve` only sees it through `Handler`. Acceptable — it's all within `beansd`.
- The fire-and-forget `cd` op is asymmetric: `Client::cd` returns `()` and never blocks, but `Handler::cd` still returns a `CdResponse` (the daemon writes it; the client just doesn't read). Documenting that asymmetry is a one-liner.

---

## Approach 3: Approach 2 + migrate launcher to consume `Handler`

Same as 2, but go further: the HTTP launcher's `LauncherState` carries `Arc<dyn Handler>` instead of `Arc<Daemon<S>>`. Drops the `S: ChildSpawner` generic propagation through `launcher.rs` (currently 6 generic functions and the manual `Clone` impl).

**Pros:**
- Single point of contact between launcher and daemon: the Handler trait. No `Arc<Daemon<S>>` plumbing.
- Removes the generic-over-`S` story from the launcher entirely. `MockSpawner` test fixture becomes a `MockHandler` (smaller surface).
- Launcher could in principle be lifted to its own crate one day with zero further coupling work.

**Cons:**
- More churn. The launcher already works; rewriting it through Handler is unrelated to the user-stated goal.
- `Arc<dyn Handler>` requires `Handler: ?Sized + Send + Sync + 'static` and may need a small dance with `async_trait` object-safety quirks (each method returning `Pin<Box<dyn Future...>>`). Workable but more friction than the typed call-sites in `beansd`.
- Mixes two concerns in one refactor (workspace split + launcher decoupling). Better to do approach 2, then file a follow-up bean for the launcher migration if it pulls its weight.

---

## Recommendation

**Approach 2.** It's the smallest scope that delivers what the user asked for: the abstraction (Client / Handler) that lets non-RPC code stop caring about the wire. Approach 1 misses the point; approach 3 mixes scopes.

Stage as five beans under the existing daemon epic (`dotfiles-nzsd`):
1. Set up workspace skeleton (root Cargo.toml, empty `crates/`, move the existing crate into `crates/beansd/` first, prove it still builds).
2. Extract `beansd-rpc` crate with wire types + socket helpers + `bind_uds`.
3. Add `Handler` trait + `serve(listener, handler)` in `beansd-rpc`; daemon implements Handler; `run.rs` uses `serve`.
4. Add `Client` in `beansd-rpc` with typed methods.
5. Extract `beansctl` crate using the new `Client`; delete `cli_client.rs` and the `cd/ls/start/stop/status` arms from `beansd`'s main.
