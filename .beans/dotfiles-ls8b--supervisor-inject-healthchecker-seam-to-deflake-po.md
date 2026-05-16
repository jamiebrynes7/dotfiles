---
# dotfiles-ls8b
title: 'supervisor: inject HealthChecker seam to deflake port-binding tests'
status: todo
type: task
created_at: 2026-05-16T08:12:40Z
updated_at: 2026-05-16T08:12:40Z
parent: dotfiles-nzsd
---

Today `Supervisor::wait_until_healthy` (crates/beansd/src/supervisor.rs:182) is hardcoded to `reqwest::get("http://127.0.0.1:{port}/")`. That couples three otherwise-independent concerns:

- the registry state machine (Spawning → Healthy / Dead)
- the retry loop (`start_project_with_retries`)
- the network-level liveness probe

Three tests are entangled in that coupling because they need a real reachable HTTP server to drive the state transitions:

- `supervisor::tests::start_project_marks_healthy_when_child_responds`
- `supervisor::tests::start_project_with_retries_eventually_succeeds`
- `handler::tests::cd_marked_dir_returns_spawned_then_eventually_healthy`

Each test fixture binds a `127.0.0.1:0` port via `pick_loopback_port` → `drop` → re-bind, which races with other parallel tests for the same kernel-handed-out port. The race is benign in production (beans-serve is a separate process; bind failure surfaces as exit + health-timeout retry), but in tests it surfaces as `EADDRINUSE` straight out of `start_project`. Observed flake rate ~1 in 6 in the Nix sandbox; <<1% on dev machines.

## Design

Introduce a `HealthChecker` trait:

```rust
#[async_trait]
pub trait HealthChecker: Send + Sync + 'static {
    /// Poll until the child at `port` responds healthy, or `timeout` elapses.
    /// Returns true if healthy within the window.
    async fn wait_until_healthy(&self, port: u16, timeout: Duration) -> bool;
}
```

Two implementations:
- `HttpHealthChecker` — today's `reqwest::get` polling loop, lives in supervisor.rs (or a new health.rs).
- `MockHealthChecker` (test-only) — configurable: always-ready, never-ready, fail-N-then-ready.

`Supervisor` grows an `H: HealthChecker` generic param (default to `HttpHealthChecker` to avoid touching call sites at the type level). Production wires `HttpHealthChecker` in `run.rs`. Tests inject a mock.

## Outcome on tests

- T1 (`start_project_marks_healthy_when_child_responds`): replace with mock checker; no port binding.
- T2 (`start_project_with_retries_eventually_succeeds`): replace `FlakySpawner`'s 3rd-attempt real-bind with a `FailTwiceThenReady` mock checker; no port binding.
- T3 (`handler::cd_marked_dir_returns_spawned_then_eventually_healthy`): replace `ImmediateHealthy`'s real-bind with the mock checker injected through the handler test's `build_daemon`; no port binding.
- New focused test: `supervisor::tests::http_checker_polls_until_ready` (binds one real port, runs in isolation; the only test that touches loopback ports).
- Delete `port_alloc::tests::returns_distinct_ports_across_calls` (already self-documented as fragile; tests an OS property, not our code).

## Acceptance

- [ ] `HealthChecker` trait + `HttpHealthChecker` impl + `MockHealthChecker` test helper exist
- [ ] `Supervisor` carries the checker; `run.rs` wires the HTTP impl
- [ ] T1/T2/T3 use the mock checker; no real bind
- [ ] One new test exercises `HttpHealthChecker` against a real bound port
- [ ] `port_alloc::tests::returns_distinct_ports_across_calls` deleted
- [ ] `cargo test --workspace` green
- [ ] `nix build .#beans-daemon --rebuild` succeeds 5 times in a row (smoke-check for residual flake)
