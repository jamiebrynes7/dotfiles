---
# dotfiles-5gsf
title: Codex hook declarations
status: todo
type: feature
created_at: 2026-06-04T12:56:49Z
updated_at: 2026-06-04T12:56:49Z
parent: dotfiles-wxve
---

Give the codex home module a hook-declaration mechanism. Owns: home/programs/codex/default.nix (moved from home/programs/codex.nix) and a new home/programs/codex/hooks/types.nix. Adds codex-local hook submodule types + mergeHooks, renames the bool `hooks` option to `enableHooks`, adds a `hooks` attrset, renders ~/.codex/hooks.json from it (only when non-empty), and asserts that declared hooks require enableHooks=true.
