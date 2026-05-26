---
# dotfiles-2ecf
title: UDS control plane
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-10T13:46:21Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-rlzx
    - dotfiles-yejq
    - dotfiles-pmk6
---

axum server bound to a Unix socket (`$XDG_RUNTIME_DIR/beans-daemon.sock` Linux / `~/Library/Caches/beans-daemon/sock` macOS), 0600 perms, stale-socket cleanup. Newline-delimited JSON request/response envelope. Ops: `cd`, `ls`, `start`, `stop`, `status`, `heartbeat`. Owns: `packages/beans-daemon/src/control.rs`, `packages/beans-daemon/src/protocol.rs`.

## Summary of Changes

Implemented the UDS control plane for `beansd`. `packages/beans-daemon/src/protocol.rs` defines the newline-delimited JSON envelope (`Request` enum tagged on `op` with `args` content for `cd`/`ls`/`start`/`stop`/`status`/`heartbeat`; `Response` with `ok`/`err` constructors). `packages/beans-daemon/src/control.rs` provides `default_socket_path()`, `bind_uds()` (stale-file cleanup + 0600 + refusal to clobber a live daemon), the `Daemon<S: ChildSpawner>` struct, all six op handlers, and the `serve_uds` accept loop with per-connection task and per-line dispatch. 13 unit/integration tests cover bind perms, every handler's happy and error paths, and end-to-end UDS round-trips. Done across child beans `dotfiles-1w3a`, `dotfiles-rpa4`, `dotfiles-78t7`, `dotfiles-1dhn`, `dotfiles-bl8w`.
