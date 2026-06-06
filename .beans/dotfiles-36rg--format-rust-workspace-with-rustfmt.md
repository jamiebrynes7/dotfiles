---
# dotfiles-36rg
title: Format Rust workspace with rustfmt
status: completed
type: task
priority: normal
created_at: 2026-06-06T17:21:32Z
updated_at: 2026-06-06T17:22:31Z
---

Pre-existing rustfmt drift (5 spots across 3 files) under the pinned toolchain (rustfmt 1.9.0-stable, defaults only — no rustfmt.toml). CI never ran `cargo fmt --check`, so it accumulated. Surfaced while implementing the pre-commit hook (dotfiles-b2sy): the hook's whole-workspace `cargo fmt --all --check` would otherwise block the next `.rs` commit on unrelated drift.

Affected files:
- crates/beansd/src/eviction.rs
- crates/beansd/src/web/routes/html/projects.rs
- crates/beansd/src/web/views.rs

- [x] Run `cargo fmt --all`
- [x] Verify `cargo fmt --all --check` is clean
- [x] Verify `cargo test --workspace` still passes
- [x] Commit as a standalone formatting commit

## Summary of Changes

Ran `cargo fmt --all` to bring the workspace in line with the pinned rustfmt 1.9.0-stable defaults. Pure formatting: rustfmt collapsed/expanded a few call and assert! sites in eviction.rs, projects.rs, and views.rs. `cargo fmt --all --check` is now clean and `cargo test --workspace` passes.
