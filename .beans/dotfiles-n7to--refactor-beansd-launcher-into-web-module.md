---
# dotfiles-n7to
title: Refactor beansd launcher into web module
status: completed
type: epic
priority: normal
created_at: 2026-05-24T15:05:39Z
updated_at: 2026-05-24T18:28:04Z
---

**Goal:** Split `crates/beansd/src/launcher.rs` into a `crates/beansd/src/web/` module that exposes a `Server` type (bind + serve), with routes grouped by HTML vs API and resource-level files inside each group.

**Architecture:** New `web/` module under `crates/beansd/src/`. `web/mod.rs` owns the public `Server` type and a private `State`. `web/routes/` contains `html/`, `api/`, and `assets.rs`. Templates and static assets relocate to `src/web/templates/` and `src/web/static/`; askama is reconfigured via a new `crates/beansd/askama.toml`. Behavior is preserved — same routes, same handlers, same tests.

**Tech Stack:** Rust, axum 0.7, askama 0.12, tokio, tower (dev).

**Spec:** docs/specs/2026-05-24-beansd-web-module.md

## Summary of Changes

Epic complete via 5 child features:

1. `dotfiles-j2qx` — scaffolded the `web/` module tree (empty stubs).
2. `dotfiles-4jzf` (via task `dotfiles-tlpb`) — relocated templates and static assets under `src/web/`, added `crates/beansd/askama.toml`.
3. `dotfiles-prsi` — migrated static asset routes + lifted `build_state`/`empty_state` test helpers into `web/test_utils.rs`.
4. `dotfiles-tlhu` — migrated HTML routes (`/` + `/partials/projects`).
5. `dotfiles-p6a4` — migrated API routes (start/stop/heartbeat), introduced shared `KeyForm` in `api/mod.rs`.
6. `dotfiles-th98` — swapped `run.rs` to `web::Server::bind` + `server.serve()`, deleted `launcher.rs`, dropped `mod launcher;` from `main.rs`.

End state matches spec `docs/specs/2026-05-24-beansd-web-module.md`. Behavior preserved (same routes, same handlers); `cargo test --workspace` → 82 passed; build clean apart from two pre-existing unrelated dead-code warnings.
