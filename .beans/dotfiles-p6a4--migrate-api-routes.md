---
# dotfiles-p6a4
title: Migrate API routes
status: completed
type: feature
priority: normal
created_at: 2026-05-24T15:05:56Z
updated_at: 2026-05-24T18:25:48Z
parent: dotfiles-n7to
---

Owns `crates/beansd/src/web/routes/api/projects.rs` (start/stop handlers + 1 test) and `crates/beansd/src/web/routes/api/heartbeat.rs` (heartbeat handler + 1 test). The shared `KeyForm` extractor lives in `crates/beansd/src/web/routes/api/mod.rs` (created in Feature 2). `projects.rs` imports `ProjectListPartial` from the html module to re-render the project list.

## Tasks

- [x] `api/mod.rs`: add shared `pub(super) struct KeyForm { key: PathBuf }` (serde-derived)
- [x] `api/projects.rs`: `start_project` + `stop_project` handlers, import `ProjectListPartial` via `super::super::html::projects`, 1 test (`stop_returns_partial_html`)
- [x] `api/heartbeat.rs`: `heartbeat` handler + 1 test (`heartbeat_returns_204_and_bumps_last_used`)
- [x] `cargo test -p beansd` — new api tests + existing launcher tests pass

## Summary of Changes

Filled in the three api files:

- `web/routes/api/mod.rs` — shared `pub(super) struct KeyForm { key: PathBuf }` (serde-derived), plus the merge of `projects` + `heartbeat`.
- `web/routes/api/projects.rs` — `start_project` and `stop_project` handlers, both render `ProjectListPartial` (imported via `super::super::html::projects` per spec) on success, return 500 on supervisor error. 1 test (`stop_returns_partial_html`).
- `web/routes/api/heartbeat.rs` — `heartbeat` handler returning 204 / 500. 1 test (`heartbeat_returns_204_and_bumps_last_used`).

Adjacent change required: relaxed `mod projects;` → `pub(super) mod projects;` in `web/routes/html/mod.rs` so the api migration could resolve `html::projects::ProjectListPartial`. The submodule was previously private to `html`; `pub(super)` lifts visibility to the routes/ subtree, which is the minimum needed.

`launcher.rs` still serves identical routes — both copies coexist until `dotfiles-th98`. `cargo test -p beansd` → 60 passed (was 58, +2 new api tests). Build clean apart from the two pre-existing dead-code warnings.
