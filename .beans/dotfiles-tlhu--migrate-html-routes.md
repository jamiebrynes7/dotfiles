---
# dotfiles-tlhu
title: Migrate HTML routes
status: completed
type: feature
priority: normal
created_at: 2026-05-24T15:05:53Z
updated_at: 2026-05-24T18:22:42Z
parent: dotfiles-n7to
---

Owns `crates/beansd/src/web/routes/html/projects.rs`: the `/` and `/partials/projects` handlers, their askama template structs (`IndexTemplate`, `ProjectListPartial`), the route-private query types, and the 4 colocated tests. Also adds the `#[cfg(test)] pub(in crate::web) mod test_utils` block in `web/mod.rs` that other route files reuse.

## Tasks

- [x] Fill in `web/routes/html/projects.rs` with `IndexTemplate`/`IndexQuery`/`index` and `ProjectListPartial`/`PartialQuery`/`projects_partial` plus the 4 colocated tests
- [x] `ProjectListPartial` marked `pub(in crate::web)` (api/projects.rs will reuse it)
- [x] `cargo test -p beansd` — both launcher and new html tests pass

> Note: the cross-cutting `#[cfg(test)] pub(in crate::web) mod test_utils` block mentioned in this bean's description was added in `dotfiles-prsi` (assets migration arrived first). This bean only consumes it.

## Summary of Changes

Filled `web/routes/html/projects.rs` with the `/` and `/partials/projects` handlers, their askama template structs (`IndexTemplate`, `ProjectListPartial`), file-local query types (`IndexQuery`, `PartialQuery`), and 4 colocated tests using `crate::web::test_utils`.

`ProjectListPartial` (and its two fields) marked `pub(in crate::web)` so the upcoming `dotfiles-p6a4` api migration can construct it from `api/projects.rs` (per spec). Everything else stays file-private.

`launcher.rs` untouched — same routes served by both copies until `dotfiles-th98` deletes the launcher.

`cargo test -p beansd` → 58 passed (54 + 4 new html tests). Build clean, only the two pre-existing dead-code warnings.
