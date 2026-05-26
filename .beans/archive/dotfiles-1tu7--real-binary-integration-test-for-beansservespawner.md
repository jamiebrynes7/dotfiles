---
# dotfiles-1tu7
title: Real-binary integration test for BeansServeSpawner
status: scrapped
type: task
priority: low
created_at: 2026-05-09T14:25:33Z
updated_at: 2026-05-26T17:07:56Z
parent: dotfiles-nzsd
---

**Files:**
- Create: `crates/beansd/tests/spawner_real_binary.rs` (integration test)
- Likely create: `crates/beansd/tests/fake_beans_serve/` (fixture binary crate, or a `[[bin]]` in `Cargo.toml` gated under `[[test]]`)

## Rationale

The current `spawner` unit test only exercises the failure path (`beans_serve_spawner_errors_on_missing_binary`). The success path — actually exec'ing a child, forwarding stdio, signalling it via `nix::sys::signal::kill`, awaiting its exit — is not covered by automated tests. The original design intent (see body of `dotfiles-pmk6`) was: *"Tests use a fake `beans-serve` binary built in-tree."* That fake binary was never built.

Without this, regressions in `BeansServeSpawner` / `BeansServeChild` (e.g. accidentally swapping SIGTERM/SIGKILL, dropping stdio inheritance, breaking PID extraction, kill-on-drop semantics) would only be caught by the e2e smoke test (`dotfiles-24hc`), which is a slow manual loop and runs only on the dev box.

## Sketch of approach

- Add a `[[bin]]` named `fake_beans_serve` to `crates/beansd/Cargo.toml` that:
  - parses `--port <u16>` and `--beans-path <PATH>` like the real binary,
  - binds an axum (or `tiny_http`) server on `127.0.0.1:<port>` returning 200 to `GET /`,
  - exits cleanly on SIGTERM (so the SIGTERM-grace path is exercised),
  - ignores SIGTERM on a `--ignore-sigterm` flag (so the SIGKILL path is exercised).
- Build it via `env!("CARGO_BIN_EXE_fake_beans_serve")` from the integration test (cargo sets this at compile time for sibling bins).
- Integration test cases:
  - `BeansServeSpawner` spawns the binary, child responds on the chosen port, PID is non-zero.
  - SIGTERM causes the child to exit; `wait()` returns.
  - With `--ignore-sigterm`, SIGKILL is required to terminate.

## Acceptance

- [ ] Fake `beans-serve` binary builds with the rest of the crate.
- [ ] Integration test asserts spawn → respond → SIGTERM → exit.
- [ ] Integration test asserts spawn → SIGTERM ignored → SIGKILL → exit.
- [ ] `cargo test --test spawner_real_binary` passes locally.

## Non-goals

- Not testing the supervisor or registry — that's covered by unit tests in `supervisor.rs`.
- Not testing actual `beans-serve` behavior — that's the e2e smoke test (`dotfiles-24hc`).


## Note (2026-05-10)

After `dotfiles-qwfb` (Workspace split) lands, this task's paths are under `crates/beansd/` rather than `packages/beans-daemon/` — body updated. The fake-binary approach itself is unchanged: still a `[[bin]]` in `crates/beansd/Cargo.toml` exposed via `env!("CARGO_BIN_EXE_fake_beans_serve")` to the integration test.

## Reasons for Scrapping

Low-priority follow-up never landed. The unit-test seam (mock spawner + injected `HealthChecker`) already gives confidence in child-process handling; a real-binary integration test would mostly re-exercise the OS process layer for marginal added coverage. Closing alongside the parent epic — re-open if a regression surfaces that would have been caught by a real-binary test.
