---
# dotfiles-ms85
title: Scaffold web/routes tree and shared KeyForm
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:07:06Z
updated_at: 2026-05-24T15:10:02Z
parent: dotfiles-j2qx
blocked_by:
    - dotfiles-flje
---

**Files:**
- Create: `crates/beansd/src/web/routes/mod.rs`
- Create: `crates/beansd/src/web/routes/html/mod.rs`
- Create: `crates/beansd/src/web/routes/html/projects.rs` (empty stub)
- Create: `crates/beansd/src/web/routes/api/mod.rs` (holds shared `KeyForm`)
- Create: `crates/beansd/src/web/routes/api/projects.rs` (empty stub)
- Create: `crates/beansd/src/web/routes/api/heartbeat.rs` (empty stub)
- Create: `crates/beansd/src/web/routes/assets.rs` (empty stub)
- Modify: `crates/beansd/src/web/mod.rs` (declare `mod routes;`, wire `router()` to `routes::router()`)

Every stub returns an empty `Router<State>`. The crate builds end-to-end at every step. Subsequent migration tasks (dotfiles-tlhu, dotfiles-p6a4, dotfiles-prsi) replace each stub with real handlers.

- [ ] **Step 1: Create `crates/beansd/src/web/routes/mod.rs`**

```rust
mod api;
mod assets;
mod html;

pub(super) fn router() -> axum::Router<super::State> {
    html::router()
        .merge(api::router())
        .merge(assets::router())
}
```

- [ ] **Step 2: Create `crates/beansd/src/web/routes/html/mod.rs`**

```rust
pub(in crate::web) mod projects;

pub(super) fn router() -> axum::Router<crate::web::State> {
    projects::router()
}
```

The `projects` submodule is declared `pub(in crate::web)` so `web/routes/api/projects.rs` can import `ProjectListPartial` from it via `crate::web::routes::html::projects::ProjectListPartial`.

- [ ] **Step 3: Create `crates/beansd/src/web/routes/html/projects.rs` (stub)**

```rust
pub(super) fn router() -> axum::Router<crate::web::State> {
    axum::Router::new()
}
```

- [ ] **Step 4: Create `crates/beansd/src/web/routes/api/mod.rs` with shared KeyForm**

```rust
use std::path::PathBuf;

mod heartbeat;
mod projects;

#[derive(serde::Deserialize)]
pub(super) struct KeyForm {
    pub(super) key: PathBuf,
}

pub(super) fn router() -> axum::Router<crate::web::State> {
    projects::router().merge(heartbeat::router())
}
```

`KeyForm` is `pub(super)` so both `api/projects.rs` and `api/heartbeat.rs` (its sibling and child modules) can use it.

- [ ] **Step 5: Create `crates/beansd/src/web/routes/api/projects.rs` (stub)**

```rust
pub(super) fn router() -> axum::Router<crate::web::State> {
    axum::Router::new()
}
```

- [ ] **Step 6: Create `crates/beansd/src/web/routes/api/heartbeat.rs` (stub)**

```rust
pub(super) fn router() -> axum::Router<crate::web::State> {
    axum::Router::new()
}
```

- [ ] **Step 7: Create `crates/beansd/src/web/routes/assets.rs` (stub)**

```rust
pub(super) fn router() -> axum::Router<crate::web::State> {
    axum::Router::new()
}
```

- [ ] **Step 8: Wire `routes` into `web/mod.rs`**

Add `mod routes;` after `mod views;`. Replace the existing `router` function. Before:

```rust
#[allow(dead_code)]
fn router(state: State) -> Router {
    Router::new().with_state(state)
}
```

After:

```rust
fn router(state: State) -> Router {
    routes::router().with_state(state)
}
```

(The `#[allow(dead_code)]` goes away because `Server::bind` reaches `router` via the constructor call chain.)

- [ ] **Step 9: Verify the crate builds**

```bash
cargo build -p beansd
```

Expected: clean build. Empty routers cause no routing collisions with launcher.rs's routes — launcher.rs is wired through `run.rs`, not through `web::Server`, so there are two routers in the binary but only the launcher one is reachable at runtime.

- [ ] **Step 10: Run tests**

```bash
cargo test -p beansd
```

Expected: all 8 launcher tests still pass.

- [ ] **Step 11: Commit**

```bash
git add crates/beansd/src/web/routes crates/beansd/src/web/mod.rs
git commit -m "beansd: scaffold web::routes module tree with shared KeyForm"
```
