---
# dotfiles-cdo6
title: CLI client subcommands
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-10T13:52:24Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-2ecf
---

Implement `beansd cd`, `beansd ls`, `beansd start`, `beansd stop`, `beansd status`. Each connects to the UDS, sends one newline-delimited JSON message, and (except `cd`) reads the response. `cd` is fire-and-forget: writes, closes the write half, exits without reading. Daemon-down case = silent exit 0. Owns: `packages/beans-daemon/src/cli/{cd,ls,start,stop,status}.rs` (or one `cli/mod.rs`).

## Summary of Changes

CLI client subcommands done. `cli_client.rs` provides sync UDS helpers (`request` for ls/start/stop/status; `send_and_close` for cd). All five `Command` arms in `main.rs` are wired: `cd` is fire-and-forget; the others read one response line and pretty-print the `data` payload via `print_response`. The `Run` arm remains an `unimplemented!` stub pending the daemon entrypoint feature (`dotfiles-5h2f`). 2 cli_client tests + 53/53 daemon tests green.
