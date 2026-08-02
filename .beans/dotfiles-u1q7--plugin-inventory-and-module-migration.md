---
# dotfiles-u1q7
title: Plugin inventory and module migration
status: todo
type: feature
created_at: 2026-08-02T12:10:37Z
updated_at: 2026-08-02T12:10:37Z
parent: dotfiles-zo7y
---

Declares the three plugins and moves every existing consumer onto them, ending with the removal of the per-assistant `skillsDirs` options so `dotfiles.ai.plugins` is the only entry point.

**Owns:** `home/lib/ai/plugins/module.nix` (the `df-base` declaration), `home/programs/claude-code/default.nix`, `home/programs/claude-code/hooks/skill-reinforcement.nix`, `home/programs/plannotator/default.nix`, `home/programs/beans.nix`, `home/programs/codex/default.nix`, `home/programs/cursor/default.nix`, and this repository's `.claude/settings.json`.
