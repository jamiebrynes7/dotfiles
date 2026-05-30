---
# dotfiles-a93p
title: '[beans daemon] tweak wrapper UI'
status: todo
type: feature
priority: normal
created_at: 2026-05-26T19:56:15Z
updated_at: 2026-05-26T20:08:06Z
---

**Goal:** Replace the 280px left sidebar in the beans daemon launcher with a thin top bar containing a custom rich dropdown (project name + path + status badge per row) and an always-visible detail strip for the active project.

**Architecture:** Server stays an axum + askama + htmx wrapper. `<nav>` becomes `<header id="topbar">` containing a `<details>` switcher and a detail strip. The 5s htmx poll switches from `/partials/projects` to `/partials/topbar`, which renders both regions atomically. The heartbeat form stays in `<main>` so the 5s swap can't destroy its 15s trigger.

**Tech Stack:** Rust, axum, askama, htmx, plain CSS.

**Spec:** docs/specs/2026-05-26-beans-daemon-wrapper-topbar.md
