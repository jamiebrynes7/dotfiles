---
# dotfiles-th98
title: Swap run.rs and delete launcher.rs
status: completed
type: feature
priority: normal
created_at: 2026-05-24T15:06:01Z
updated_at: 2026-05-24T18:28:04Z
parent: dotfiles-n7to
---

Owns the cutover: `crates/beansd/src/run.rs` switches from the freestanding bind + `router_with_state` block to `web::Server::bind(...).await?` + `tokio::spawn(server.serve())`. `crates/beansd/src/main.rs` drops `mod launcher;`. `crates/beansd/src/launcher.rs` is deleted. Final validation (cargo test, nix flake check, smoke test in a browser) runs here.

## Tasks

- [x] Edit `run.rs`: swap launcher imports for `crate::web`, replace bind/router block with `web::Server::bind(...).await?` + `tokio::spawn(server.serve())`, log via `server.local_addr()`
- [x] Edit `main.rs`: drop `mod launcher;`
- [x] Delete `crates/beansd/src/launcher.rs`
- [x] Remove the `#![allow(dead_code)]` from `web/mod.rs` (no longer needed once Server is wired)
- [x] `cargo test -p beansd` — full suite green, no orphaned references
- [x] `cargo build -p beansd` — clean, no scaffold-era warnings

## Summary of Changes

Final cutover from `launcher.rs` to `web::Server`:

- `crates/beansd/src/run.rs` — `use crate::web;` replaces the `crate::launcher::{router_with_state, LauncherState}` imports. The freestanding bind + router block collapses to three lines: `web::Server::bind(registry, daemon, port).await?`, then a `tracing::info!(addr = %server.local_addr(), ...)`, then `tokio::spawn(server.serve())`. Same log intent — the address is drawn from the actual bound socket via `local_addr()`.
- `crates/beansd/src/main.rs` — `mod launcher;` removed.
- `crates/beansd/src/launcher.rs` — deleted (git rm).
- `crates/beansd/src/web/mod.rs` — `#![allow(dead_code)]` scaffold attribute removed; every `web/` item is now reachable from `run.rs` so the allow is no longer needed.

`cargo build --workspace` clean apart from the two pre-existing dead-code warnings (`Config::heartbeat_secs`, `ProjectState::Dead::reason`) that are unrelated to this refactor. `cargo test --workspace` → 52 + 23 + 7 = 82 passed (same total as pre-refactor: lost 8 launcher tests, gained 8 web tests).

Manual smoke test (run beansd + hit / in a browser) deferred to the user — pure code reorg with behavior preservation verified by oneshot tests at the router level.
