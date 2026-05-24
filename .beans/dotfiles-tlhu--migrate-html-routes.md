---
# dotfiles-tlhu
title: Migrate HTML routes
status: todo
type: feature
created_at: 2026-05-24T15:05:53Z
updated_at: 2026-05-24T15:05:53Z
parent: dotfiles-n7to
---

Owns `crates/beansd/src/web/routes/html/projects.rs`: the `/` and `/partials/projects` handlers, their askama template structs (`IndexTemplate`, `ProjectListPartial`), the route-private query types, and the 4 colocated tests. Also adds the `#[cfg(test)] pub(in crate::web) mod test_utils` block in `web/mod.rs` that other route files reuse.
