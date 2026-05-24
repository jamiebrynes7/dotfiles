---
# dotfiles-ldpo
title: Remove unused thiserror dep from crates/beansd/Cargo.toml
status: completed
type: task
priority: normal
created_at: 2026-05-24T14:39:06Z
updated_at: 2026-05-24T18:32:09Z
---

`thiserror` is declared as a dependency in `crates/beansd/Cargo.toml` (line 21) but is not used anywhere in the crate — no `#[derive(thiserror::Error)]`, no custom error enum. The convention in this workspace is `anyhow` (see `crates/CLAUDE.md`), so the dep is just noise / cargo bloat.

## Todo
- [x] Remove the `thiserror` line from `crates/beansd/Cargo.toml`
- [x] Run `cargo build --workspace` and `cargo test --workspace` to confirm nothing breaks
- [x] Commit (will also update `Cargo.lock`)

## Summary of Changes

Removed the unused `thiserror = "1"` line from `crates/beansd/Cargo.toml`. No code referenced it (no `#[derive(thiserror::Error)]`, no `use thiserror`), so removal was safe.

`cargo build --workspace` clean. `cargo test --workspace` → 82 passed. `Cargo.lock` shrank by 25 lines (thiserror + its proc-macro `thiserror-impl` dropped from the dep tree).
