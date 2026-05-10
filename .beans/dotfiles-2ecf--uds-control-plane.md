---
# dotfiles-2ecf
title: UDS control plane
status: in-progress
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-10T13:35:21Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-rlzx
    - dotfiles-yejq
    - dotfiles-pmk6
---

axum server bound to a Unix socket (`$XDG_RUNTIME_DIR/beans-daemon.sock` Linux / `~/Library/Caches/beans-daemon/sock` macOS), 0600 perms, stale-socket cleanup. Newline-delimited JSON request/response envelope. Ops: `cd`, `ls`, `start`, `stop`, `status`, `heartbeat`. Owns: `packages/beans-daemon/src/control.rs`, `packages/beans-daemon/src/protocol.rs`.
