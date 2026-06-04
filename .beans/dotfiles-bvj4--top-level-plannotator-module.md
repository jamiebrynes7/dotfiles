---
# dotfiles-bvj4
title: Top-level plannotator module
status: todo
type: feature
created_at: 2026-06-04T12:56:49Z
updated_at: 2026-06-04T12:56:49Z
parent: dotfiles-wxve
---

Invert plannotator into one shared module. Owns: new home/programs/plannotator/default.nix and home/programs/plannotator/skills/ (the plannotator-user-code-review skill, moved here). Removes home/programs/claude-code/plannotator/ and drops it from claude-code's imports. Exposes dotfiles.programs.plannotator.{remote,port,claude-code.enable,codex.enable} and injects the plan-review hook into each enabled assistant.
