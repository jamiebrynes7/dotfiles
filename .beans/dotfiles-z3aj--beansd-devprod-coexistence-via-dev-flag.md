---
# dotfiles-z3aj
title: beansd dev/prod coexistence via --dev flag
status: completed
type: epic
priority: normal
created_at: 2026-05-30T18:31:40Z
updated_at: 2026-05-31T14:39:11Z
---

**Goal:** Let a dev `beansd` run alongside the launchd-managed prod daemon, selected by an explicit `--dev` flag on both binaries.

**Architecture:** A global `--dev` flag shifts the two per-instance coordinates — socket path (`-dev` suffix) and daemon config path (repo-local `dev-config.toml`). The dev config omits `beans_serve_path`, which is then resolved from `$PATH` so it never goes stale against nix-store churn. Prod and the chpwd/prime hooks never pass `--dev`, so they're untouched.

**Tech Stack:** Rust (clap, anyhow, the `which` crate for $PATH lookup), Cargo workspace under `crates/`.

**Spec:** docs/specs/2026-05-30-beansd-dev-coexistence.md

## Summary of Changes

A dev `beansd` can now run alongside the launchd-managed prod daemon, selected by an explicit `--dev` flag on both binaries. `--dev` shifts two per-instance coordinates: the socket path (`-dev` suffix, via `default_socket_path(dev)`) and the daemon config path (repo-local `crates/beansd/dev-config.toml`, via `Config::default_path(dev)`). The dev config omits `beans_serve_path`, which `resolve_beans_serve()` then resolves from `$PATH` (new `which` dep) so it never goes stale against nix-store churn. Prod and the chpwd/prime hooks never pass `--dev`, so they are untouched. Verified end-to-end at runtime and via `nix flake check`.
