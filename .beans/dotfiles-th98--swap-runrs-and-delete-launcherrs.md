---
# dotfiles-th98
title: Swap run.rs and delete launcher.rs
status: todo
type: feature
created_at: 2026-05-24T15:06:01Z
updated_at: 2026-05-24T15:06:01Z
parent: dotfiles-n7to
---

Owns the cutover: `crates/beansd/src/run.rs` switches from the freestanding bind + `router_with_state` block to `web::Server::bind(...).await?` + `tokio::spawn(server.serve())`. `crates/beansd/src/main.rs` drops `mod launcher;`. `crates/beansd/src/launcher.rs` is deleted. Final validation (cargo test, nix flake check, smoke test in a browser) runs here.
