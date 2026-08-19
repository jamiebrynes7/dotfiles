---
# dotfiles-7043
title: paseo home-manager module
status: todo
type: epic
priority: normal
created_at: 2026-08-19T10:54:25Z
updated_at: 2026-08-19T11:00:24Z
---

**Goal:** Expose paseo as `pkgs.dotfiles.paseo` plus a `dotfiles.programs.paseo` home-manager module that runs the daemon as a user service on both Linux (systemd user unit) and macOS (launchd agent).

**Architecture:** A flake input pinned to `v0.3.1` feeds `overlays/paseo.nix`, which `callPackage`s upstream's `nix/package.nix` with our own `npmDepsHash` and a `node-pty` prebuilds fix, landing the result at `pkgs.dotfiles.paseo`. `home/programs/paseo.nix` follows the repo's program-module pattern and drives both launchers through one shared `writeShellScript` launcher — the only way `passwordFile` can behave identically on macOS (launchd has no `EnvironmentFile`). A `paseo-module` flake check evaluates a scratch home-manager config with a stub package and greps the rendered unit/agent.

**Tech Stack:** Nix flakes, nixpkgs 26.05, home-manager (release-26.05), buildNpmPackage.

**Spec:** docs/specs/2026-08-19-paseo-home-manager-module.md

## Notes

- `sys-warbird` is explicitly **not** migrated here. That is deferred follow-up work.
- Relay is hardcoded off (`--no-relay`, no options). No `settings`/`config.json` rendering.
- One refinement over the spec: the `paseo-module` check is defined for **both** systems, not Linux-only. CI still only builds the `x86_64-linux` one, but a darwin definition lets the implementer verify the launchd path locally. Verified working during planning.

## Relationship to the home-eval harness (dotfiles-6f5q)

A separate epic plans a `home-eval` check (`checks/home-eval.nix` + `mkHomeEvalCheck`, bean dotfiles-d6t2) that evaluates a home-manager config and forces `config.assertions` for the AI-assistant modules.

That is **complementary**, not a duplicate, and the two are expected to coexist in `checks`:

- `home-eval` — broad, eval-only, forces assertions across many modules. Answers "does `home/` still evaluate".
- `paseo-module` — narrow, builds a tiny derivation, greps the *rendered* unit and launcher. Answers "does the module actually emit the wiring it promises".

Neither blocks the other. Whichever lands second simply sits beside the first in the `checks` attribute. If `home-eval` is already present when this epic starts, add `mkPaseoModuleCheck` next to `mkHomeEvalCheck` and follow whatever placement convention that work established.
