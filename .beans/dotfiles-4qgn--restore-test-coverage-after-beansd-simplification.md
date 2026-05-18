---
# dotfiles-4qgn
title: Restore test coverage after beansd simplification
status: completed
type: task
priority: normal
created_at: 2026-05-18T18:25:54Z
updated_at: 2026-05-18T18:41:34Z
parent: dotfiles-nzsd
---

After a refactor of `crates/beansd/` (Supervisor → trait, ChildHandle::kill collapsed, eviction moved to background sweep), 8 tests were dropped and the new `eviction.rs` shipped without any tests. This restores equivalent coverage where the behavior still exists, against the new APIs.

Plan: `/Users/jamiebrynes/.claude/plans/if-you-look-at-iterative-stardust.md`

## Todo

- [x] Refactor `eviction.rs`: introduce `EvictorConfig` + `Evictor` struct with `spawn()` and `run_one_sweep()` methods (also fixes the down-to-cap bug — current code evicts ALL Healthy projects)
- [x] Update `run.rs` to construct `Evictor::new(...).spawn()` with `cfg.lru_cap`
- [x] Enhance `FakeSupervisor` in `supervisor::test_utils` to record `started`/`stopped` calls and transition Healthy → Dead on stop
- [x] Update `daemon.rs::build_daemon` and `launcher.rs::build_state` to pass registry into `FakeSupervisor::new(registry)`
- [x] supervisor.rs tests: `start_marks_healthy_when_child_responds`
- [x] supervisor.rs tests: `start_marks_dead_when_health_fails`
- [x] supervisor.rs tests: `stop_transitions_healthy_to_dead_and_kills_child`
- [x] supervisor.rs tests: `stop_on_unknown_key_is_noop`
- [x] supervisor.rs tests: `stop_on_non_healthy_is_noop`
- [x] eviction.rs tests: `lru_returns_none_when_empty`
- [x] eviction.rs tests: `lru_returns_none_when_no_healthy`
- [x] eviction.rs tests: `lru_picks_oldest_healthy_by_last_used`
- [x] eviction.rs tests: `lru_skips_non_healthy_states`
- [x] eviction.rs tests: `sweep_noop_when_at_or_under_cap`
- [x] eviction.rs tests: `sweep_evicts_one_when_one_over_cap`
- [x] eviction.rs tests: `sweep_evicts_down_to_cap_in_lru_order` (validates the cap-check fix)
- [x] registry.rs: collapse obsolete `mod cap_tests` into `mod registry_tests` (done by user)
- [x] `cargo test -p beansd` all green (52 passed)
- [x] `cargo build -p beansd` clean

## Summary of Changes

**Refactor** — `crates/beansd/src/eviction.rs`: replaced the free-function `run_eviction_loop` with an `Evictor` struct grouping `EvictorConfig { lru_cap, poll_interval }`. Wired `cfg.lru_cap` through `run.rs` (was hardcoded `> 5`). Fixed the cap-check bug — the inner sweep loop now exits when `active_count <= cap` instead of evicting all Healthy projects.

**Test util** — Enhanced `FakeSupervisor` in `supervisor::test_utils` to track `started`/`stopped` calls and mirror real `Healthy → Dead` transitions on stop (so eviction sweeps converge). Constructor now takes `registry`. Updated `daemon.rs::build_daemon` and `launcher.rs::build_state` to pass it.

**New tests (12 total)**:
- supervisor.rs (5): `start_marks_healthy_when_child_responds`, `start_marks_dead_when_health_fails`, `stop_transitions_healthy_to_dead_and_kills_child`, `stop_on_unknown_key_is_noop`, `stop_on_non_healthy_is_noop`. Use `FakeSpawner` (which tracks children) to verify `kill()` was invoked via the shared `Arc<SetOnce>`.
- eviction.rs (7): four `find_lru` tests (none-when-empty, none-when-no-healthy, picks-oldest, skips-non-healthy) plus three `run_one_sweep` tests (noop-at-cap, one-over-cap, down-to-cap-in-lru-order). The last one validates the cap-check fix.

**Cleanup** — removed leftover unused imports (`HealthChecker`, `HttpHealthChecker`, `ChildSpawner`) from `daemon.rs`, `launcher.rs`, `supervisor.rs` exposed by the simplification refactor.

Final: `cargo test -p beansd` → 52 passed; `cargo build -p beansd` → clean.

## Notes for follow-up

- `// TODO: Retries` in `daemon.rs:50` — retry logic was removed; no equivalent for the deleted `start_project_with_retries_eventually_succeeds` test until retries return.
- `BeansServeChild::kill()` SIGTERM→wait→SIGKILL timing is still untested — talks to real PIDs.
