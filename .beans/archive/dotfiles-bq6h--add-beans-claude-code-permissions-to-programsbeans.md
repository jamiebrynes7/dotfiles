---
# dotfiles-bq6h
title: Add beans Claude Code permissions to programs/beans.nix
status: completed
type: task
priority: normal
created_at: 2026-04-26T15:56:01Z
updated_at: 2026-04-26T15:58:00Z
---

Extend `home/programs/beans.nix` so that, when enabled, it registers Claude Code permissions for common read-only `beans` CLI invocations. Today the module only wires up SessionStart/PreCompact hooks (`beans prime`); read-only commands like `beans list`, `beans show`, and `beans query` still trigger permission prompts.

## Context

- Module: `home/programs/beans.nix`
- Permissions hook: `dotfiles.programs.claude-code.permissions.allow` (see `home/programs/claude-code/default.nix:55-75`)
- Existing permission patterns (e.g. `Bash(git log *)`) use a glob-style `Bash(<cmd> *)` form

## Approach

Per user direction: allow any and all beans calls (`Bash(beans *)`), not a curated read-only subset. Mirror the existing `claudeCodeHooks` toggle with a parallel `claudeCodePermissions` toggle.

## Todo

- [x] Add `claudeCodePermissions` enable option to `home/programs/beans.nix`
- [x] Wire `Bash(beans *)` into `dotfiles.programs.claude-code.permissions.allow` under that toggle
- [x] Run `nix flake check` to validate

## Summary of Changes

- Added a new `dotfiles.programs.beans.claudeCodePermissions` enable option mirroring the existing `claudeCodeHooks` toggle.
- When enabled, the module appends `Bash(beans *)` to `dotfiles.programs.claude-code.permissions.allow`, allowing any beans CLI invocation without a permission prompt.
- `nix flake check` passes; nixfmt left the file unchanged.

Note: the toggle is opt-in. To wire it on, set `dotfiles.programs.beans.claudeCodePermissions = true;` in the relevant profile/host (no profile change made here).
