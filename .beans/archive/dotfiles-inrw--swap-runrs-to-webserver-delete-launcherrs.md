---
# dotfiles-inrw
title: Swap run.rs to web::Server; delete launcher.rs
status: completed
type: task
priority: normal
created_at: 2026-05-24T15:08:47Z
updated_at: 2026-05-26T17:10:32Z
parent: dotfiles-th98
blocked_by:
    - dotfiles-bqzh
    - dotfiles-gzr8
    - dotfiles-n25o
---

**Files:**
- Modify: `crates/beansd/src/run.rs`
- Modify: `crates/beansd/src/main.rs` (drop `mod launcher;`)
- Delete: `crates/beansd/src/launcher.rs`

By this point all handlers and tests exist in their new `web/` locations. This task removes the now-duplicate copies in `launcher.rs` and switches the runtime wire-up.

- [ ] **Step 1: Update `crates/beansd/src/run.rs`**

Replace the import (currently `crates/beansd/src/run.rs:5`):

```rust
use crate::launcher::{router_with_state, LauncherState};
```

with:

```rust
use crate::web;
```

(`crate::registry::Registry` and `crate::spawner::BeansServeSpawner` stay; only the launcher import goes.)

Then replace the bind / spawn block (currently `crates/beansd/src/run.rs:45-52`):

```rust
let launcher_addr = std::net::SocketAddr::from(([127, 0, 0, 1], cfg.launcher_port));
let tcp = tokio::net::TcpListener::bind(launcher_addr).await?;
let app = router_with_state(LauncherState {
    registry: registry.clone(),
    daemon: daemon.clone(),
});
tracing::info!(%launcher_addr, "HTTP launcher bound");
let http_task = tokio::spawn(async move { axum::serve(tcp, app).await });
```

with:

```rust
let server = web::Server::bind(
    registry.clone(),
    daemon.clone(),
    cfg.launcher_port,
).await?;
let launcher_addr = server.local_addr()?;
tracing::info!(%launcher_addr, "HTTP launcher bound");
let http_task = tokio::spawn(server.serve());
```

The `launcher_addr` local is preserved (it feeds the `tracing::info!` line); it now comes from the bound listener rather than being constructed up front. `server.serve()` returns an `async fn`-style future that `tokio::spawn` accepts directly (no extra `async move` wrapper needed).

- [ ] **Step 2: Remove `mod launcher;` from `crates/beansd/src/main.rs`**

Delete the line `mod launcher;` (currently line 5). The remaining `mod` list:

```rust
mod config;
mod daemon;
mod eviction;
mod health;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;
mod web;
```

- [ ] **Step 3: Delete `crates/beansd/src/launcher.rs`**

```bash
git rm crates/beansd/src/launcher.rs
```

- [ ] **Step 4: Build and run beansd tests**

```bash
cargo test -p beansd
```

Expected: 8 tests pass — 4 in `web::routes::html::projects::tests`, 1 in `web::routes::api::projects::tests`, 1 in `web::routes::api::heartbeat::tests`, 2 in `web::routes::assets::tests`. The previous 8 launcher tests are gone (their bodies are now in the corresponding web/ test modules; no new tests were added).

- [ ] **Step 5: Run the full workspace check**

```bash
cargo test --workspace
```

Expected: all workspace tests pass.

- [ ] **Step 6: Run `nix flake check` (CI parity)**

```bash
nix flake check
```

Expected: passes. This is what CI runs (`packages/beans-daemon/default.nix`).

- [ ] **Step 7: Smoke test in a browser**

Run beansd locally:

```bash
cargo run -p beansd
```

(or whatever you normally use; the daemon reads config from its default path). Then in a browser, visit `http://127.0.0.1:<launcher_port>/` and confirm:

- The index page renders ("Select a project" or registered projects show).
- `/static/htmx.min.js` and `/static/app.css` load with `application/javascript` and `text/css` content types respectively (check DevTools).
- `GET /partials/projects` returns the partial.
- If a project is registered and healthy, start/stop API round-trips work (HTMX-driven from the page).

- [ ] **Step 8: Commit**

```bash
git add crates/beansd/src/run.rs crates/beansd/src/main.rs
git rm crates/beansd/src/launcher.rs
git commit -m "beansd: switch run.rs to web::Server and delete launcher.rs"
```

## Summary of Changes

Rolled up into parent `dotfiles-th98`; shipped in commit `b140a91` (beansd: swap run.rs to web::Server, delete launcher.rs).
