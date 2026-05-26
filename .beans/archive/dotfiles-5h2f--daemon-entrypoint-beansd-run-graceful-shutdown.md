---
# dotfiles-5h2f
title: Daemon entrypoint (`beansd run`) & graceful shutdown
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-10T14:19:13Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-2ecf
    - dotfiles-60yo
---

Top-level `beansd run`: load config, set up tracing, start UDS server + HTTP launcher concurrently, wait for SIGTERM/SIGINT, drain in-flight evictions, exit cleanly. Owns: `packages/beans-daemon/src/run.rs` and the `Run` arm of the CLI dispatcher in `main.rs`.

## Summary of Changes

Daemon entrypoint feature complete. `packages/beans-daemon/src/run.rs` loads + validates config, initialises tracing, builds the registry / supervisor (with `BeansServeSpawner`) / daemon, binds the UDS via `bind_uds(default_socket_path()?)` (with stale-socket cleanup), spawns `serve_uds`, binds HTTP launcher on `127.0.0.1:cfg.launcher_port`, serves the `router_with_state`. The shutdown `tokio::select!` honours SIGTERM/SIGINT and falls through to a best-effort SIGTERM sweep of healthy children before returning. The `Run` arm of `main.rs` block_on's `run::run()`. Smoke-tested: starts cleanly, recovers from a stale socket, exits 0 on SIGTERM with the expected log line. Done across child beans `dotfiles-v7g5` and `dotfiles-kw6s`.
