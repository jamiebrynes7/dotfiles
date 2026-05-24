---
# dotfiles-c7ss
title: Create web/mod.rs with Server, State, and private router
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:06:39Z
updated_at: 2026-05-24T15:09:12Z
parent: dotfiles-j2qx
blocked_by:
    - dotfiles-tlpb
---

**Files:**
- Create: `crates/beansd/src/web/mod.rs`
- Modify: `crates/beansd/src/main.rs` (add `mod web;`)

This task creates the public `Server` surface and the private `State` type. The `router(state)` function is wired to an empty router for now; dotfiles-j2qx's other tasks (views, routes scaffold) populate it.

- [ ] **Step 1: Create `crates/beansd/src/web/mod.rs`**

```rust
use crate::daemon::Daemon;
use crate::registry::Registry;
use axum::Router;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::Mutex;

#[derive(Clone)]
pub(in crate::web) struct State {
    pub(in crate::web) registry: Arc<Mutex<Registry>>,
    pub(in crate::web) daemon: Arc<Daemon>,
}

#[allow(dead_code)]
fn router(state: State) -> Router {
    Router::new().with_state(state)
}

pub struct Server {
    listener: TcpListener,
    router: Router,
}

impl Server {
    pub async fn bind(
        registry: Arc<Mutex<Registry>>,
        daemon: Arc<Daemon>,
        port: u16,
    ) -> anyhow::Result<Self> {
        let addr = SocketAddr::from(([127, 0, 0, 1], port));
        let listener = TcpListener::bind(addr).await?;
        let state = State { registry, daemon };
        Ok(Self {
            listener,
            router: router(state),
        })
    }

    pub fn local_addr(&self) -> std::io::Result<SocketAddr> {
        self.listener.local_addr()
    }

    pub async fn serve(self) -> std::io::Result<()> {
        axum::serve(self.listener, self.router).await
    }
}
```

Notes:
- `pub(in crate::web)` on `State` and its fields means descendant modules (views.rs, routes/**/*.rs) can name and construct `State`, but nothing outside `web/` can.
- `local_addr` returns `std::io::Result<SocketAddr>` because `TcpListener::local_addr` is fallible — that's the honest signature.
- `#[allow(dead_code)]` on the private `router` is removed in the task that wires it to `routes::router()`.
- `Server` is `pub` (not `pub(in crate::web)`) because `run.rs` calls it.

- [ ] **Step 2: Add `mod web;` to `crates/beansd/src/main.rs`**

Append after `mod supervisor;` so the module list stays alphabetical:

```rust
mod config;
mod daemon;
mod eviction;
mod health;
mod launcher;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;
mod web;
```

- [ ] **Step 3: Verify the crate builds**

```bash
cargo build -p beansd
```

Expected: clean build. There may be `dead_code` warnings on `Server::local_addr`/`Server::serve` since nothing calls them yet — that's expected; dotfiles-th98 wires them in.

- [ ] **Step 4: Run tests to confirm no regression**

```bash
cargo test -p beansd
```

Expected: all 8 launcher tests still pass.

- [ ] **Step 5: Commit**

```bash
git add crates/beansd/src/web/mod.rs crates/beansd/src/main.rs
git commit -m "beansd: scaffold web::Server with private State"
```
