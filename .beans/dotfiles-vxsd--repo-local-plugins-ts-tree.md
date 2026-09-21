---
# dotfiles-vxsd
title: 'Repo-local plugins: ts/ tree'
status: draft
type: feature
priority: deferred
created_at: 2026-09-21T17:24:10Z
updated_at: 2026-09-21T17:24:10Z
parent: dotfiles-5nj7
---

Phase 2, deferred until a repo-local plugin exists. `ts/default.nix` as an overlay fragment in `crates/default.nix`'s slot exporting `buildPaseoPlugin` and `dotfiles.internal.tsChecks`; source at `ts/paseo-plugin-<name>/`; `packages/paseo-plugin-<name>/default.nix` as a one-liner; `typecheck` (tsc --noEmit) and `sdk-version` (devDependency vs packages/paseo/hashes.json) checks; `flake.nix` gains the checks merge and `nodejs` in the devShell. Designed in docs/specs/2026-09-21-paseo-plugins.md; building it before a first inhabitant means an npm toolchain and a lockfile with nothing to check.
