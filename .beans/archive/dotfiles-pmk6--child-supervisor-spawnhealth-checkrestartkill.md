---
# dotfiles-pmk6
title: Child supervisor (spawn/health-check/restart/kill)
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-09T14:19:15Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-m592
---

Spawn `beans-serve` children on a fresh loopback port; health-check via HTTP poll; restart-on-crash with exponential backoff (3 retries / 60s); SIGTERM→SIGKILL eviction with bounded wait and orphan-on-timeout fallback. Owns: `packages/beans-daemon/src/supervisor.rs`, `packages/beans-daemon/src/port_alloc.rs`. Tests use a fake `beans-serve` binary built in-tree.

## Summary of Changes

Feature complete — all 7 child tasks done in this order:

1. dotfiles-5kme — ChildSpawner / ChildHandle traits + BeansServeSpawner (signals via nix::sys::signal::kill).
2. dotfiles-u222 — pick_loopback_port() in port_alloc.rs (binds 127.0.0.1:0, reads assigned port, drops listener).
3. dotfiles-5q83 — Supervisor::start_project (port pick -> spawn -> health-check via reqwest poll -> Healthy/Dead transition). Created supervisor.rs.
4. dotfiles-v74e — Supervisor::evict (SIGTERM grace -> SIGKILL grace -> orphan + WARN log).
5. dotfiles-wj32 — children: Arc<Mutex<HashMap<PathBuf, Box<dyn ChildHandle>>>> field + insert_child + trigger_eviction (fire-and-forget, &Arc<Self>).
6. dotfiles-qlj3 — start_project_with_retries (max_attempts; backoff *= 4; reset to Spawning between attempts).
7. dotfiles-mcs1 — watch_for_exit (awaits child.wait, transitions Dead, retries within MAX_ATTEMPTS=3 with backoff doubling, re-watches on success).

Final test count: 34 passed (5 in supervisor::, 2 in spawner::, 2 in port_alloc::, plus the pre-existing registry/project_key/config/cli/logging tests).

Bean spec corrections made along the way (called out in each child bean summary):
- dotfiles-wj32 test: needed Arc::new(Supervisor{...}) + remove .await on the sync trigger_eviction call.
- dotfiles-mcs1 test: original attempts_used=0 raced the auto-restart and would observe Healthy at 500ms instead of Dead. Used attempts_used=2 to disable retry and isolate the Dead-marking assertion.
- Cleaned no-op .map(|s| s) before unwrap_or_else in watch_for_exit.

Follow-up beans worth filing (not urgent):
- Wiring of watch_for_exit into the daemon entrypoint (already noted in dotfiles-5h2f / F5).
- Real-binary integration test for BeansServeSpawner once a fake beans-serve binary is built in-tree (currently only the missing-binary error path is exercised).
