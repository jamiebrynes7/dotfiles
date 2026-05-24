---
# dotfiles-p6a4
title: Migrate API routes
status: todo
type: feature
created_at: 2026-05-24T15:05:56Z
updated_at: 2026-05-24T15:05:56Z
parent: dotfiles-n7to
---

Owns `crates/beansd/src/web/routes/api/projects.rs` (start/stop handlers + 1 test) and `crates/beansd/src/web/routes/api/heartbeat.rs` (heartbeat handler + 1 test). The shared `KeyForm` extractor lives in `crates/beansd/src/web/routes/api/mod.rs` (created in Feature 2). `projects.rs` imports `ProjectListPartial` from the html module to re-render the project list.
