---
# dotfiles-wxve
title: Codex hook declarations + top-level plannotator module
status: completed
type: epic
priority: normal
created_at: 2026-06-04T12:56:41Z
updated_at: 2026-06-04T13:12:19Z
---

**Goal:** Let the codex home module declare lifecycle hooks (rendered to ~/.codex/hooks.json) and add a plannotator plan-review option, inverted into a single top-level module shared by codex and claude-code.

**Architecture:** Codex gets its own local hook types module (event enum + mergeHooks) — no shared hooks-types abstraction with claude-code. The codex module renames its bool `hooks` option to `enableHooks` and adds a `hooks` attrset that renders ~/.codex/hooks.json. A new top-level `home/programs/plannotator/` module owns the shared wrapper/package/skill and injects the correct plan-review hook into each enabled assistant (claude-code: PermissionRequest/ExitPlanMode; codex: Stop). The old `home/programs/claude-code/plannotator/` is removed.

**Tech Stack:** Nix flakes, home-manager, pkgs.formats.toml, builtins.toJSON.

**Spec:** docs/specs/2026-06-04-codex-plannotator.md

**Validation:** `nix flake check` (what CI runs) + `nixfmt` on changed files. No unit-test framework for these modules; the build + assertions are the gate.

**Migration (breaking, downstream only):** `dotfiles.programs.claude-code.plannotator.{enable,remote,port}` becomes `dotfiles.programs.plannotator.{claude-code.enable, remote, port}`; codex via `dotfiles.programs.plannotator.codex.enable`. No alias provided.
