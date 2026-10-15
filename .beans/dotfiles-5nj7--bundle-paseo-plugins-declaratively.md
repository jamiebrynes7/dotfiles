---
# dotfiles-5nj7
title: Bundle paseo plugins declaratively
status: completed
type: epic
priority: normal
created_at: 2026-09-21T17:23:56Z
updated_at: 2026-10-15T10:00:58Z
---

**Goal:** Install paseo plugins through a home-manager switch instead of `paseo plugin install`, with Nix owning `$PASEO_HOME/config.json` and the daemon patched to refuse overwriting it.

**Architecture:** `dotfiles.programs.paseo.plugins.<id> = { package; enable; }` lowers into config.json's `plugins` record (the only place plugins are expressible — there is no env var for them). The module stops gating config.json rendering on `settings != {}` and writes it whenever `enable` is true, reproducing the daemon's creation-time defaults. `packages/paseo` gains a `postPatch` guard that makes `savePersistedConfig` throw when the target is a symlink, and activation moves aside any daemon-written file and restarts the daemon when the config's store path changes. External plugins are packaged under `packages/paseo-plugin-<id>/`, pinned by commit SHA.

**Tech Stack:** Nix flakes, home-manager, nix-darwin/launchd + systemd user units, `substituteInPlace --replace-fail`, `fetchFromGitHub` + `runCommand`.

**Spec:** docs/specs/2026-09-21-paseo-plugins.md

Phase 2 (`ts/` tree for repo-local plugins) is specced but deferred — see the draft feature on this epic.

## Summary of Changes

paseo plugins are bundled declaratively. External plugins are packaged as `packages/paseo-plugin-<id>/`, pinned by commit SHA with no auto-update (catppuccin-theme is the first). `dotfiles.programs.paseo.plugins` lowers into a store-owned `config.json`. A `postPatch` guard makes the daemon refuse to overwrite that symlink. Activation moves a daemon-written config aside and restarts the daemon when the config changes. The `paseo-plugin-requirements` flake check holds every plugin's `requirements.paseo` against the pinned daemon. All of this was validated on a real host, and the conventions are documented in CLAUDE.md.

Phase 2, repo-local plugins under `ts/` (dotfiles-vxsd), was detached and left as a standalone draft. It is deliberately deferred until a first repo-local plugin exists, and closing this epic with it still a child would have marked it completed implicitly.
