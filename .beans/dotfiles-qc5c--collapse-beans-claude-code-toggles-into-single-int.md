---
# dotfiles-qc5c
title: Collapse beans Claude Code toggles into single integration option
status: completed
type: task
priority: normal
created_at: 2026-04-26T16:03:18Z
updated_at: 2026-04-26T16:03:48Z
---

Replace the two Claude Code toggles in `home/programs/beans.nix` (`claudeCodeHooks`, `claudeCodePermissions`) with a single `enableClaudeCodeIntegration` option that gates both the SessionStart/PreCompact hooks and the `Bash(beans *)` permission allowlist entry.

## Rationale

The two pieces always travel together for personal use; splitting them was over-engineering. No external consumers reference the old names yet (they were added moments ago in `dotfiles-bq6h`), so this is a safe rename.

## Todo

- [x] Replace both options with `enableClaudeCodeIntegration` in `home/programs/beans.nix`
- [x] Gate both `permissions.allow` and `hooks` blocks on the new toggle
- [x] Run `nix flake check`

## Summary of Changes

- Removed `claudeCodeHooks` and `claudeCodePermissions` from `home/programs/beans.nix`.
- Added `enableClaudeCodeIntegration` (single toggle) gating both the `Bash(beans *)` allowlist entry and the SessionStart/PreCompact prime hooks.
- `nix flake check` passes; nixfmt reformatted the hooks block (cosmetic).
