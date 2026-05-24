---
# dotfiles-n7to
title: Refactor beansd launcher into web module
status: todo
type: epic
created_at: 2026-05-24T15:05:39Z
updated_at: 2026-05-24T15:05:39Z
---

**Goal:** Split `crates/beansd/src/launcher.rs` into a `crates/beansd/src/web/` module that exposes a `Server` type (bind + serve), with routes grouped by HTML vs API and resource-level files inside each group.

**Architecture:** New `web/` module under `crates/beansd/src/`. `web/mod.rs` owns the public `Server` type and a private `State`. `web/routes/` contains `html/`, `api/`, and `assets.rs`. Templates and static assets relocate to `src/web/templates/` and `src/web/static/`; askama is reconfigured via a new `crates/beansd/askama.toml`. Behavior is preserved — same routes, same handlers, same tests.

**Tech Stack:** Rust, axum 0.7, askama 0.12, tokio, tower (dev).

**Spec:** docs/specs/2026-05-24-beansd-web-module.md
