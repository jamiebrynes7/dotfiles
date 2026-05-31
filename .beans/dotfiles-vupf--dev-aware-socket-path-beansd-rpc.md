---
# dotfiles-vupf
title: Dev-aware socket path (beansd-rpc)
status: completed
type: feature
priority: normal
created_at: 2026-05-30T18:31:49Z
updated_at: 2026-05-31T14:25:32Z
parent: dotfiles-z3aj
---

Make the shared socket-path helper flavor-aware so both binaries resolve the same dev path. Owns `crates/beansd-rpc/src/socket.rs` (the `default_socket_path` contract) and the one internal caller in `crates/beansd-rpc/src/client.rs`.

## Summary of Changes

`default_socket_path` is now flavor-aware (`dev: bool`), appending a `-dev` suffix so a dev daemon and dev CLI resolve the same dev socket independently. Both internal callers updated.
