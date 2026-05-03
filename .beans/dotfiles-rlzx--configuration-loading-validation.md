---
# dotfiles-rlzx
title: Configuration loading & validation
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:16Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-m592
---

Define `Config` struct (serde + toml), load from `~/.config/beans-daemon/config.toml`, apply defaults for optional keys, validate that `beans_serve_path` points to an executable. Owns: `packages/beans-daemon/src/config.rs`.
