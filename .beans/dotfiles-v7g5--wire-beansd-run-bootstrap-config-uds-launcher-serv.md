---
# dotfiles-v7g5
title: 'Wire `beansd run`: bootstrap config + UDS + launcher servers'
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:41:45Z
updated_at: 2026-05-10T14:04:10Z
parent: dotfiles-5h2f
---

**Files:**
- Create: `packages/beans-daemon/src/run.rs`
- Modify: `packages/beans-daemon/src/main.rs` (replace the `Run` arm + add `mod run;`)

This is the integration step that ties together everything from F2–F6.

- [x] **Step 1: Implement `run`**

Create `packages/beans-daemon/src/run.rs`:
```rust
use crate::config::Config;
use crate::control::{Daemon, bind_uds, default_socket_path};
use crate::launcher::{LauncherState, router_with_state};
use crate::registry::Registry;
use crate::spawner::BeansServeSpawner;
use crate::supervisor::Supervisor;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub async fn run() -> anyhow::Result<()> {
    let cfg = Config::load(&Config::default_path()?)?;
    cfg.validate()?;

    crate::logging::init(&cfg.log_level)?;
    tracing::info!(version = env!("CARGO_PKG_VERSION"), "beansd starting");
    tracing::info!(?cfg.beans_serve_path, port = cfg.launcher_port, lru_cap = cfg.lru_cap, "loaded config");

    let registry = Arc::new(Mutex::new(Registry::new()));
    let supervisor = Arc::new(Supervisor {
        registry: registry.clone(),
        spawner:  BeansServeSpawner { binary: cfg.beans_serve_path.clone() },
        health_timeout: Duration::from_secs(5),
    });
    let daemon = Arc::new(Daemon {
        registry: registry.clone(),
        supervisor: supervisor.clone(),
        lru_cap: cfg.lru_cap,
        sigterm_grace: Duration::from_secs(5),
        sigkill_grace: Duration::from_secs(5),
        start_max_attempts: 3,
        start_base_backoff: Duration::from_secs(1),
    });

    // UDS server
    let uds_path = default_socket_path()?;
    let uds_listener = bind_uds(&uds_path)?;
    tracing::info!(path = %uds_path.display(), "UDS bound");
    let uds_task = {
        let d = daemon.clone();
        tokio::spawn(async move { d.serve_uds(uds_listener).await })
    };

    // HTTP launcher
    let launcher_addr = std::net::SocketAddr::from(([127,0,0,1], cfg.launcher_port));
    let tcp = tokio::net::TcpListener::bind(launcher_addr).await?;
    let app = router_with_state(LauncherState {
        registry: registry.clone(),
        daemon:   daemon.clone(),
    });
    tracing::info!(%launcher_addr, "HTTP launcher bound");
    let http_task = tokio::spawn(async move { axum::serve(tcp, app).await });

    // Wait for either to exit (or for shutdown — see follow-up task in F8 for signal handling).
    tokio::select! {
        r = uds_task  => { tracing::error!(?r, "UDS server exited"); }
        r = http_task => { tracing::error!(?r, "HTTP server exited"); }
    }
    Ok(())
}
```

- [x] **Step 2: Wire into main.rs**

Add `mod run;` near the top, then replace the `cli::Command::Run` arm with:
```rust
        cli::Command::Run => {
            let rt = tokio::runtime::Runtime::new()?;
            rt.block_on(run::run())
        }
```

- [x] **Step 3: Smoke build**

Run: `cargo build`
Expected: PASS.

- [x] **Step 4: Commit**

```
git add packages/beans-daemon/src/run.rs packages/beans-daemon/src/main.rs
git commit -m 'packages/beans-daemon: wire beansd run entrypoint'
```

## Summary of Changes

Added `packages/beans-daemon/src/run.rs` wiring the full daemon: load and validate `Config`, init tracing, build `Registry` + `Supervisor` (with `BeansServeSpawner`) + `Daemon`, bind UDS via `bind_uds(default_socket_path()?)`, spawn `serve_uds`, bind HTTP launcher on `127.0.0.1:cfg.launcher_port`, and `axum::serve` the `router_with_state(LauncherState { registry, daemon })`. `tokio::select!` returns when either server exits. Wired the `Run` arm in `main.rs` to spin up a fresh `tokio::runtime::Runtime` and `block_on(run::run())`. Spec's `Supervisor` literal omitted `children: Arc<Mutex<HashMap>>` — added since the existing API requires it. Builds clean.
