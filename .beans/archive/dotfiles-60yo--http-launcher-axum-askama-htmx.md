---
# dotfiles-60yo
title: HTTP launcher (axum + askama + HTMX)
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-10T14:01:40Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-2ecf
---

axum server on `127.0.0.1:9000` (configurable). Server-rendered HTML via askama templates; HTMX for polling/heartbeat/actions; no JS bundle. Routes: `GET /`, `GET /partials/projects`, `POST /api/heartbeat`, `POST /api/projects/stop`, `POST /api/projects/start`. Bookmark URL: `?project=<encoded>`. Owns: `packages/beans-daemon/src/launcher.rs`, `packages/beans-daemon/templates/*.html`, `packages/beans-daemon/static/{htmx.min.js,app.css}`.

## Summary of Changes

HTTP launcher feature complete. `launcher.rs` exposes `LauncherState<S: ChildSpawner>` and `router_with_state` wiring up: `GET /` (index with iframe panel + `?project=` query), `GET /partials/projects` (HTMX 5s polling fragment), `POST /api/heartbeat` (204, bumps `last_used`), `POST /api/projects/start` and `POST /api/projects/stop` (return refreshed project-list partial), and `GET /static/{htmx.min.js,app.css}` (assets embedded via `include_bytes!`/`include_str!`). htmx 1.9.12 vendored under `static/`. Templates `index.html` and `project_list.html` use askama 0.12 (with `[package.metadata.askama] dirs = ["templates"]`). 8 launcher tests + 61/61 daemon tests green. Done across child beans `dotfiles-jf1c`, `dotfiles-2186`, `dotfiles-a1vr`, `dotfiles-8grr`.
