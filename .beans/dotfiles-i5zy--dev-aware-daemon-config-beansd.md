---
# dotfiles-i5zy
title: Dev-aware daemon config (beansd)
status: todo
type: feature
created_at: 2026-05-30T18:31:49Z
updated_at: 2026-05-30T18:31:49Z
parent: dotfiles-z3aj
---

Teach `beansd` to load a repo-local dev config and resolve `beans-serve` from $PATH when unset. Owns `crates/beansd/src/config.rs` (`default_path(dev)`, optional `beans_serve_path`, `resolve_beans_serve()`), the new `crates/beansd/dev-config.toml`, and the `which` dependency wiring in `Cargo.toml` + `crates/beansd/Cargo.toml`.
