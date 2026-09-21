---
# dotfiles-5nj7
title: Bundle paseo plugins declaratively
status: todo
type: epic
created_at: 2026-09-21T17:23:56Z
updated_at: 2026-09-21T17:23:56Z
---

**Goal:** Install paseo plugins through a home-manager switch instead of `paseo plugin install`, with Nix owning `$PASEO_HOME/config.json` and the daemon patched to refuse overwriting it.

**Architecture:** `dotfiles.programs.paseo.plugins.<id> = { package; enable; }` lowers into config.json's `plugins` record (the only place plugins are expressible — there is no env var for them). The module stops gating config.json rendering on `settings != {}` and writes it whenever `enable` is true, reproducing the daemon's creation-time defaults. `packages/paseo` gains a `postPatch` guard that makes `savePersistedConfig` throw when the target is a symlink, and activation moves aside any daemon-written file and restarts the daemon when the config's store path changes. External plugins are packaged under `packages/paseo-plugin-<id>/`, pinned by commit SHA.

**Tech Stack:** Nix flakes, home-manager, nix-darwin/launchd + systemd user units, `substituteInPlace --replace-fail`, `fetchFromGitHub` + `runCommand`.

**Spec:** docs/specs/2026-09-21-paseo-plugins.md

Phase 2 (`ts/` tree for repo-local plugins) is specced but deferred — see the draft feature on this epic.
