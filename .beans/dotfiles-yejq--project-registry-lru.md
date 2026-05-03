---
# dotfiles-yejq
title: Project registry & LRU
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-m592
---

In-memory project registry keyed by abs path; `ProjectState` enum (`Spawning`/`Healthy`/`Evicting`/`Dead`); LRU operations (insert, bump_last_used, find_lru_for_eviction, count_active). Pure data + methods, no I/O. Owns: `packages/beans-daemon/src/registry.rs`, `packages/beans-daemon/src/project_key.rs`.
