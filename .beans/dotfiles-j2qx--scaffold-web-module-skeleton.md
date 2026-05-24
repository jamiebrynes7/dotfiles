---
# dotfiles-j2qx
title: Scaffold web module skeleton
status: todo
type: feature
created_at: 2026-05-24T15:05:50Z
updated_at: 2026-05-24T15:05:50Z
parent: dotfiles-n7to
---

Owns the new module skeleton: `crates/beansd/src/web/mod.rs` (public `Server`, private `State`, private `router`), `crates/beansd/src/web/views.rs` (`ProjectView` + `project_views`), and the routes-tree stubs at `crates/beansd/src/web/routes/{mod.rs,html/mod.rs,html/projects.rs,api/mod.rs,api/projects.rs,api/heartbeat.rs,assets.rs}`. Stubs are empty axum routers so the crate builds at every step; subsequent features replace each stub with its real handlers.
