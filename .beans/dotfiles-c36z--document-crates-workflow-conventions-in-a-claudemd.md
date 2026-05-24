---
# dotfiles-c36z
title: Document crates/ workflow & conventions in a CLAUDE.md
status: completed
type: task
priority: normal
created_at: 2026-05-24T14:35:39Z
updated_at: 2026-05-24T14:39:21Z
---

Add a CLAUDE.md under `crates/` that captures the actual Rust workspace conventions
(anyhow, tokio + async_trait, tracing, colocated tests + `mod test_utils`, etc.) in
extractable form, and update the root CLAUDE.md so the Rust subtree is discoverable.

Plan file: /Users/jamiebrynes/.claude/plans/can-we-write-a-clever-sprout.md

## Todo
- [x] Write `crates/CLAUDE.md` (Purpose, Layout, Workspace config, Commands, Conventions, Boundaries)
- [x] Update root `CLAUDE.md`: add Rust to Tech Stack, add `crates/` + `packages/` to Project Structure, add `cargo test --workspace` to Commands, bump Freshness date
- [x] Verify line count (< 100 lines for crates/CLAUDE.md) and that all referenced file paths/line numbers resolve
- [x] Run `nix flake check` to confirm no incidental breakage
- [x] Offer follow-up bean: remove unused `thiserror` dep from `crates/beansd/Cargo.toml` (filed as dotfiles-ldpo)

## Summary of Changes

Created `crates/CLAUDE.md` (68 lines) documenting the Rust workspace: layout (beansd / beansctl / beansd-rpc), workspace config (resolver 2, edition 2021, shared `[workspace.dependencies]`), commands (`cargo`/`nix flake check`), conventions (anyhow, tokio + async_trait, tracing + EnvFilter, flat-or-mod.rs module style, colocated `#[cfg(test)]` tests + `mod test_utils` for mocks, no rustfmt/clippy/lints config), and boundaries (Nix `cargoBuildFlags = ["--workspace"]`, prefer workspace-inherited deps).

Updated root `CLAUDE.md`: added Rust to Tech Stack, added `crates/` + `packages/` to Project Structure, added `cargo test --workspace` to Commands, bumped Freshness to 2026-05-24.

Verified all referenced file paths / line numbers resolve (`crates/beansd-rpc/src/client.rs:27`, `crates/beansd-rpc/src/lib.rs:7-10`, `crates/beansd-rpc/tests/round_trip.rs`, `crates/beansd/src/logging.rs`, `.github/workflows/ci.yml`, `packages/beans-daemon/default.nix`). `nix flake check` passed (exit 0).

Follow-up filed: `dotfiles-ldpo` — remove the unused `thiserror` dep from `crates/beansd/Cargo.toml`.
