---
# dotfiles-j2qx
title: Scaffold web module skeleton
status: completed
type: feature
priority: normal
created_at: 2026-05-24T15:05:50Z
updated_at: 2026-05-24T15:50:49Z
parent: dotfiles-n7to
---

Owns the new module skeleton: `crates/beansd/src/web/mod.rs` (public `Server`, private `State`, private `router`), `crates/beansd/src/web/views.rs` (`ProjectView` + `project_views`), and the routes-tree stubs at `crates/beansd/src/web/routes/{mod.rs,html/mod.rs,html/projects.rs,api/mod.rs,api/projects.rs,api/heartbeat.rs,assets.rs}`. Stubs are empty axum routers so the crate builds at every step; subsequent features replace each stub with its real handlers.

## Tasks

- [x] Add `mod web;` to `crates/beansd/src/main.rs` (keep `mod launcher;`)
- [x] Create `web/mod.rs`: `Server`, `State`, private `router`, `#![allow(dead_code)]` for scaffold phase
- [x] Create `web/views.rs`: `ProjectView` + `project_views` (`pub(in crate::web)`)
- [x] Create `web/routes/mod.rs` merging html/api/assets
- [x] Create `web/routes/html/{mod.rs,projects.rs}` stubs
- [x] Create `web/routes/api/{mod.rs,projects.rs,heartbeat.rs}` stubs
- [x] Create `web/routes/assets.rs` stub
- [x] `cargo build -p beansd` clean
- [x] `cargo test --workspace` passes (existing launcher tests still green)

## Summary of Changes

Scaffolded the `web/` module tree alongside the existing `launcher.rs` (which stays wired into `run.rs` until `dotfiles-th98` swaps it). The crate builds clean and all 82 tests (incl. the 8 launcher tests) pass.

Files created:

- `crates/beansd/src/web/mod.rs` — public `Server` (`bind` / `local_addr` / `serve`), `pub(in crate::web)` `State`, private `router(state)` wrapping `routes::router().with_state(state)`. `#![allow(dead_code)]` at module top since nothing outside `web/` consumes `Server` yet; the allow is removed in `dotfiles-th98` when `run.rs` is swapped over.
- `crates/beansd/src/web/views.rs` — `ProjectView` + `project_views(&Registry)`, both `pub(in crate::web)`. Real implementation copied verbatim from `launcher.rs` (the launcher copy remains the active one until handlers migrate).
- `crates/beansd/src/web/routes/{mod.rs, html/mod.rs, html/projects.rs, api/mod.rs, api/projects.rs, api/heartbeat.rs, assets.rs}` — every `router()` returns `Router<State>`; leaf stubs are `Router::new()`, parents `.merge` their children. Empty merges compile and serve a 404-only router today, which is what later beans will fill in.

File modified:

- `crates/beansd/src/main.rs` — added `mod web;` after `mod supervisor;`. `mod launcher;` is untouched.

Validation:

- `cargo build -p beansd` — clean (only the two pre-existing dead-code warnings in `config.rs` and `registry.rs`).
- `cargo test --workspace` — 82 passed, 0 failed.
- rustfmt clean on the new files (the only pre-existing fmt drift is in `eviction.rs`, unrelated).
