---
# dotfiles-yejq
title: Project registry & LRU
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-09T13:52:59Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-m592
---

In-memory project registry keyed by abs path; `ProjectState` enum (`Spawning`/`Healthy`/`Evicting`/`Dead`); LRU operations (insert, bump_last_used, find_lru_for_eviction, count_active). Pure data + methods, no I/O. Owns: `packages/beans-daemon/src/registry.rs`, `packages/beans-daemon/src/project_key.rs`.

## Summary of Changes

Feature delivered via four child tasks:

- `dotfiles-y2t0` — `Project` struct + `ProjectState` enum (`Spawning`/`Healthy`/`Evicting`/`Dead`) with `counts_toward_cap()`.
- `dotfiles-xdxz` — `Registry` struct with `new`, `get`, `insert_spawning`, `bump_last_used`.
- `dotfiles-g09v` — `Registry::count_active`, `find_lru_for_eviction`, `transition_state`, `remove`, `iter`.
- `dotfiles-6rb8` — `project_key::resolve` (canonicalize + upward `.beans.yml` search).

`cargo test registry:: project_key::` runs 14 passing tests. All path-taking accessors use `&Path` (not `&PathBuf`) for clippy compliance. Production wiring (the daemon `cd`/`start` handlers) is deferred to the supervisor and CLI features.
