---
# dotfiles-cdo6
title: CLI client subcommands
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-2ecf
---

Implement `beansd cd`, `beansd ls`, `beansd start`, `beansd stop`, `beansd status`. Each connects to the UDS, sends one newline-delimited JSON message, and (except `cd`) reads the response. `cd` is fire-and-forget: writes, closes the write half, exits without reading. Daemon-down case = silent exit 0. Owns: `packages/beans-daemon/src/cli/{cd,ls,start,stop,status}.rs` (or one `cli/mod.rs`).
