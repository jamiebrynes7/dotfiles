---
# dotfiles-qwfb
title: Workspace split (rpc / daemon / ctl)
status: completed
type: feature
priority: normal
created_at: 2026-05-10T14:51:24Z
updated_at: 2026-05-16T13:49:41Z
parent: dotfiles-nzsd
---

Restructure `packages/beans-daemon/` into a Cargo workspace at the repo root with three crates: `beansd-rpc` (control surface — wire types, `Client`, `Handler` trait, `serve`), `beansd` (daemon), `beansctl` (CLI). The wire format becomes private to `beansd-rpc`; non-RPC code sees typed messages.

**Spec:** `docs/specs/2026-05-10-beansd-workspace-split.md` (approved via plannotator on 2026-05-10).

**Owns:** `Cargo.toml` (workspace root), `crates/beansd-rpc/`, `crates/beansd/`, `crates/beansctl/`, `packages/beans-daemon/default.nix`.

**Migration plan:** five sequential tasks (each blocked-by the previous). Each ends with `cargo test --workspace` green and a single commit.

## Summary of Changes

All six child tasks complete; the workspace split is fully landed.

**Migration tasks (sequential, each a single commit):**

1. `dotfiles-7zn7` — workspace skeleton: moved single crate into `crates/beansd/`.
2. `dotfiles-4f2a` — extracted `beansd-rpc` skeleton (wire types + socket helpers).
3. `dotfiles-75b5` — added typed messages, `Handler` trait, and `serve` to `beansd-rpc`.
4. `dotfiles-erte` — daemon implements `Handler` typed; `run.rs` calls `beansd_rpc::serve`. `control.rs` deleted.
5. `dotfiles-qu9y` — added `Client` to `beansd-rpc`, extracted `beansctl` CLI crate, tightened wire types to `pub(crate)`.

**Packaging follow-up:**

6. `dotfiles-dsm1` — `packages/beans-daemon/default.nix` metadata updated to reflect the two-binary output (beansd + beansctl).

**Outcome:**

- Repo layout: `crates/beansd-rpc/`, `crates/beansd/`, `crates/beansctl/`.
- Wire format (`WireRequest`/`WireResponse`) is private to `beansd-rpc`; consumers see typed messages (`CdResponse`, `LsResponse`, `StartResponse`, `StatusResponse`, `ProjectSummary`).
- `beansd` is the daemon-only binary; `beansctl` is the user-facing CLI; both ship from the same Nix derivation.
- Test count: 80 (50 beansd + 23 beansd-rpc unit + 7 beansd-rpc integration). Daemon-side dispatch tests live in `beansd-rpc::server`; daemon-side typed-handler tests live in `beansd::handler`.

**Out of scope, filed separately:**

- `dotfiles-ls8b` — supervisor `HealthChecker` injection seam (deflakes the port-binding tests uncovered by `nix flake check` during dsm1 verification). Daemon-internal concern, not part of the workspace split.
