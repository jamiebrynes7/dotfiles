---
# dotfiles-1afe
title: 'claude-code: add defaultMode permission setting'
status: completed
type: feature
priority: normal
created_at: 2026-06-30T16:15:29Z
updated_at: 2026-06-30T18:29:42Z
---

Add a `defaultMode` option to the claude-code module's permissions submodule, written to settings.json as `permissions.defaultMode`. Defaults to "auto".

Docs: https://code.claude.com/docs/en/permission-modes#switch-permission-modes

## Tasks

- [x] Add `defaultMode` field (nullOr enum, default "auto") to the permissions submodule in home/programs/claude-code/default.nix
- [x] Emit permissions with defaultMode stripped when null (settingsJson builder)
- [x] nixfmt + nix flake check

## Summary of Changes

Added a `defaultMode` field to the `permissions` submodule in `home/programs/claude-code/default.nix` (type `nullOr (enum [...6 modes])`, default `"auto"`). The `settingsJson` builder now constructs `permissions` from `allow`/`deny` and merges in `defaultMode` only when non-null (via `lib.optionalAttrs`), so it serializes to `permissions.defaultMode` in `~/.claude/settings.json`. Verified by evaluating the module: the default config emits `"defaultMode":"auto"`.
