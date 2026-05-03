---
# dotfiles-nzsd
title: Beans daemon (multiplexes beans-serve across projects)
status: todo
type: epic
created_at: 2026-05-03T14:31:08Z
updated_at: 2026-05-03T14:31:08Z
---

**Goal:** Build `beansd`, a long-lived per-user daemon that multiplexes `beans-serve` instances across many projects on one dev box. cd into a project tree → daemon ensures beans-serve is running for it. A unified web launcher on `localhost:9000` lists projects and embeds the active one in an iframe.

**Architecture:** Single Rust binary (axum + tokio + clap). In-memory project registry with LRU cap. Per-project beans-serve children spawned on random loopback ports. UDS control plane for cd-hook and CLI; HTTP launcher for the browser (askama + HTMX, no SPA). Concurrent eviction: kill of LRU project runs on a background task while spawn of new project proceeds in parallel.

**Tech Stack:** Rust, tokio, axum, clap, serde + toml, askama, htmx, tracing, rust's `nix` crate for SIGTERM/SIGKILL. Packaged via `rustPlatform.buildRustPackage` and wired into home-manager via launchd (Darwin) and systemd-user (Linux).

**Spec:** `docs/specs/2026-05-03-beans-daemon.md`

**Out of scope (deferred to v1.x / v2):**
- Reverse-proxy mode replacing the iframe
- Per-project log capture and in-launcher viewer
- SSE/WebSocket push for registry updates
- "Add by path" UI to register without cd
- bash/fish cd-hook integrations
