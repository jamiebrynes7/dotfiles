---
# dotfiles-z3aj
title: beansd dev/prod coexistence via --dev flag
status: todo
type: epic
created_at: 2026-05-30T18:31:40Z
updated_at: 2026-05-30T18:31:40Z
---

**Goal:** Let a dev `beansd` run alongside the launchd-managed prod daemon, selected by an explicit `--dev` flag on both binaries.

**Architecture:** A global `--dev` flag shifts the two per-instance coordinates — socket path (`-dev` suffix) and daemon config path (repo-local `dev-config.toml`). The dev config omits `beans_serve_path`, which is then resolved from `$PATH` so it never goes stale against nix-store churn. Prod and the chpwd/prime hooks never pass `--dev`, so they're untouched.

**Tech Stack:** Rust (clap, anyhow, the `which` crate for $PATH lookup), Cargo workspace under `crates/`.

**Spec:** docs/specs/2026-05-30-beansd-dev-coexistence.md
