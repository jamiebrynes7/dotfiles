---
# dotfiles-f696
title: Disable Claude Code auto-memory declaratively
status: todo
type: task
created_at: 2026-04-27T20:11:22Z
updated_at: 2026-04-27T20:11:22Z
---

Claude Code's auto-memory feature is currently active for this project (writing to ~/.claude/projects/-home-jamiebrynes-workspace-dotfiles/memory/). Disable it declaratively via the nix module at home/programs/claude-code/default.nix so the setting persists across rebuilds rather than relying on runtime state.

## Context

- Settings are generated in `home/programs/claude-code/default.nix` (settingsJson) and written to `~/.claude/settings.json`.
- Currently the module sets `alwaysThinkingEnabled`, `hooks`, `permissions`, and optionally `statusLine`.
- Auto-memory is governed by Claude Code's settings (likely `autoMemory` / `autoMemoryEnabled` or similar — verify exact key against Claude Code docs before implementing).

## Todo

- [ ] Identify the exact settings.json key that disables auto-memory (check Claude Code docs/source)
- [ ] Add the disabling key to the `settingsJson` builder in `home/programs/claude-code/default.nix`
- [ ] Decide whether to expose this as an option (`dotfiles.programs.claude-code.autoMemory.enable`) or hard-disable it — default to hard-disable unless there's a reason to make it configurable
- [ ] Run `nix flake check` to validate
- [ ] Rebuild and confirm `~/.claude/settings.json` contains the disabling key
- [ ] Optionally clean up the existing memory directory at `~/.claude/projects/-home-jamiebrynes-workspace-dotfiles/memory/`
