---
# dotfiles-60yo
title: HTTP launcher (axum + askama + HTMX)
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-2ecf
---

axum server on `127.0.0.1:9000` (configurable). Server-rendered HTML via askama templates; HTMX for polling/heartbeat/actions; no JS bundle. Routes: `GET /`, `GET /partials/projects`, `POST /api/heartbeat`, `POST /api/projects/stop`, `POST /api/projects/start`. Bookmark URL: `?project=<encoded>`. Owns: `packages/beans-daemon/src/launcher.rs`, `packages/beans-daemon/templates/*.html`, `packages/beans-daemon/static/{htmx.min.js,app.css}`.
