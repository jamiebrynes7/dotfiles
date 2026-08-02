---
# dotfiles-jali
title: Plugin library
status: todo
type: feature
created_at: 2026-08-02T12:10:37Z
updated_at: 2026-08-02T12:10:37Z
parent: dotfiles-zo7y
---

The reusable machinery: option definitions and the renderer that turns them into plugin directories. No behaviour change on its own — nothing declares a plugin until the next feature.

**Owns:** `home/lib/ai/plugins/hook-types.nix` (moved from `home/programs/claude-code/hooks/types.nix`), `home/lib/ai/plugins/module.nix` (the `dotfiles.ai.plugins.<name>` options), `home/lib/ai/plugins/default.nix` (`mkPluginFiles`), and the shared `readSkillDir` helper lifted out of `home/lib/ai/skills/default.nix`.
