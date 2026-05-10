---
# dotfiles-qwfb
title: Workspace split (rpc / daemon / ctl)
status: todo
type: feature
created_at: 2026-05-10T14:51:24Z
updated_at: 2026-05-10T14:51:24Z
parent: dotfiles-nzsd
---

Restructure `packages/beans-daemon/` into a Cargo workspace at the repo root with three crates: `beansd-rpc` (control surface — wire types, `Client`, `Handler` trait, `serve`), `beansd` (daemon), `beansctl` (CLI). The wire format becomes private to `beansd-rpc`; non-RPC code sees typed messages.

**Spec:** `docs/specs/2026-05-10-beansd-workspace-split.md` (approved via plannotator on 2026-05-10).

**Owns:** `Cargo.toml` (workspace root), `crates/beansd-rpc/`, `crates/beansd/`, `crates/beansctl/`, `packages/beans-daemon/default.nix`.

**Migration plan:** five sequential tasks (each blocked-by the previous). Each ends with `cargo test --workspace` green and a single commit.
