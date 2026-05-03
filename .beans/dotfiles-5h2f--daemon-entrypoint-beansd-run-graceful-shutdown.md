---
# dotfiles-5h2f
title: Daemon entrypoint (`beansd run`) & graceful shutdown
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-2ecf
    - dotfiles-60yo
---

Top-level `beansd run`: load config, set up tracing, start UDS server + HTTP launcher concurrently, wait for SIGTERM/SIGINT, drain in-flight evictions, exit cleanly. Owns: `packages/beans-daemon/src/run.rs` and the `Run` arm of the CLI dispatcher in `main.rs`.
