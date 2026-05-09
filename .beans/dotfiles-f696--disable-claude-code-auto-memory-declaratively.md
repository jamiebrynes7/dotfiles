---
# dotfiles-f696
title: Disable Claude Code auto-memory declaratively
status: completed
type: task
priority: normal
created_at: 2026-04-27T20:11:22Z
updated_at: 2026-05-09T12:29:29Z
---

Claude Code's auto-memory feature is currently active for this project (writing to ~/.claude/projects/-home-jamiebrynes-workspace-dotfiles/memory/). Disable it declaratively via the nix module at home/programs/claude-code/default.nix so the setting persists across rebuilds rather than relying on runtime state.

## Context

- Settings are generated in `home/programs/claude-code/default.nix` (settingsJson) and written to `~/.claude/settings.json`.
- Currently the module sets `alwaysThinkingEnabled`, `hooks`, `permissions`, and optionally `statusLine`.
- Auto-memory is governed by Claude Code's settings (likely `autoMemory` / `autoMemoryEnabled` or similar — verify exact key against Claude Code docs before implementing).

## Todo

- [x] Identify the exact settings.json key that disables auto-memory (check Claude Code docs/source)
- [x] Add the disabling key to the `settingsJson` builder in `home/programs/claude-code/default.nix`
- [x] Decide whether to expose this as an option (`dotfiles.programs.claude-code.autoMemory.enable`) or hard-disable it — default to hard-disable unless there's a reason to make it configurable
- [x] Run `nix flake check` to validate
- [x] Rebuild and confirm `~/.claude/settings.json` contains the disabling key
- [x] Optionally clean up the existing memory directory at `~/.claude/projects/-home-jamiebrynes-workspace-dotfiles/memory/`

## Notes

- Setting: `autoMemoryEnabled = false` added to the `settingsJson` builder. Per Claude Code docs, this disables both reads and writes of auto-memory. Hard-disabled (no option exposed).
- Validated with `nix flake check --impure`.
- Remaining: user-driven `darwin-rebuild switch` to apply, then verify `~/.claude/settings.json` contains the key. Memory directory cleanup is optional and deferred to user.

## Summary of Changes

Added `autoMemoryEnabled = false` to the `settingsJson` builder in `home/programs/claude-code/default.nix`. Hard-disabled (no Nix option exposed) per the bean's default. Verified via `nix flake check --impure`. User confirmed completion; rebuild + optional memory-directory cleanup are user-driven follow-ups.
