---
# dotfiles-ldpo
title: Remove unused thiserror dep from crates/beansd/Cargo.toml
status: todo
type: task
created_at: 2026-05-24T14:39:06Z
updated_at: 2026-05-24T14:39:06Z
---

`thiserror` is declared as a dependency in `crates/beansd/Cargo.toml` (line 21) but is not used anywhere in the crate — no `#[derive(thiserror::Error)]`, no custom error enum. The convention in this workspace is `anyhow` (see `crates/CLAUDE.md`), so the dep is just noise / cargo bloat.

## Todo
- [ ] Remove the `thiserror` line from `crates/beansd/Cargo.toml`
- [ ] Run `cargo build --workspace` and `cargo test --workspace` to confirm nothing breaks
- [ ] Commit (will also update `Cargo.lock`)
