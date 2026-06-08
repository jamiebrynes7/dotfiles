---
# dotfiles-e8zz
title: Shared extraSessionPaths option on the zsh module
status: completed
type: feature
priority: normal
created_at: 2026-06-04T10:10:28Z
updated_at: 2026-06-04T10:29:24Z
parent: dotfiles-ywp9
---

Pre-work refactor. Adds a de-duplicating `dotfiles.programs.zsh.extraSessionPaths` option (list of str) on `home/programs/zsh.nix` that feeds `home.sessionPath` via `lib.unique`, so any module can request a PATH entry exactly once. Migrates `home/programs/claude-code/default.nix` off its raw `programs.zsh.envExtra` PATH export onto this option. Owns: home/programs/zsh.nix, home/programs/claude-code/default.nix. Lands as one commit.
