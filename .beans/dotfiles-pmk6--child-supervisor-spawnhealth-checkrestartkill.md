---
# dotfiles-pmk6
title: Child supervisor (spawn/health-check/restart/kill)
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-m592
---

Spawn `beans-serve` children on a fresh loopback port; health-check via HTTP poll; restart-on-crash with exponential backoff (3 retries / 60s); SIGTERM→SIGKILL eviction with bounded wait and orphan-on-timeout fallback. Owns: `packages/beans-daemon/src/supervisor.rs`, `packages/beans-daemon/src/port_alloc.rs`. Tests use a fake `beans-serve` binary built in-tree.
