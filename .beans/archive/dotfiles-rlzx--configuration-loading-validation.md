---
# dotfiles-rlzx
title: Configuration loading & validation
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-09T13:46:42Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-m592
---

Define `Config` struct (serde + toml), load from `~/.config/beans-daemon/config.toml`, apply defaults for optional keys, validate that `beans_serve_path` points to an executable. Owns: `packages/beans-daemon/src/config.rs`.

## Summary of Changes

Feature delivered via four child tasks:

- `dotfiles-ky6g` — `Config` struct (`launcher_port`, `lru_cap`, `heartbeat_secs`, `log_level`, `beans_serve_path`) with serde defaults and `deny_unknown_fields`.
- `dotfiles-yqai` — `Config::default_path()` (XDG-aware) and `Config::load(&Path)` with file-path embedded errors.
- `dotfiles-x108` — Refactored `default_path` onto the `xdg` crate; dropped the env-mutating test.
- `dotfiles-btt9` — `Config::validate()` checking that `beans_serve_path` exists, is a file, and is executable (`0o111` mode bits).

9 unit tests pass under `cargo test config::`. Production wiring (calling `default_path` → `load` → `validate` from the daemon `run` subcommand) is deferred to the daemon entrypoint feature.
