---
# dotfiles-zl1c
title: Check external plugins' requirements.paseo against the pinned daemon
status: completed
type: task
priority: low
created_at: 2026-09-21T17:32:18Z
updated_at: 2026-10-05T13:44:54Z
parent: dotfiles-5nj7
blocked_by:
    - dotfiles-m8y6
---

Follow-up from `docs/specs/2026-09-21-paseo-plugins.md`.

A plugin manifest may declare `requirements.paseo` as an npm semver range, and the daemon enforces it at load via `assertPluginCompatibility` — on install, on startup, on enable and on reload. A plugin that no longer admits the pinned paseo version therefore fails at *runtime*, showing up as `failed` in `paseo plugin ls` on the host rather than as a red check.

`packages/paseo-plugin-catppuccin-theme` declares `>=0.8.0` against a pinned 0.8.0, so it is fine today. The risk is asymmetric: bumping `packages/paseo` is what breaks it, and that bump arrives as an auto-update PR whose diff says nothing about plugins.

Sketch: a check derivation that reads each plugin package's `paseo-plugin.json` and the `version` from `packages/paseo/hashes.json`, then evaluates the range. Semver range matching is the awkward part — `nodejs` with `require("semver")` is the honest implementation, and `pkgs.nodePackages.semver` is available. A plugin with no `requirements.paseo` means "predates 0.8" and must fail.

Blocked until at least one external plugin package exists to check.

## Summary of Changes

Added a `paseo-plugin-requirements` flake check on both systems (`mkPaseoPluginRequirementsCheck` in flake.nix), and a line about it in CLAUDE.md.
- **What it checks:** every `paseo-plugin-*` package's `requirements.paseo` against `version` from `packages/paseo/hashes.json`, read at eval time with no IFD.
- **Semantics:** it mirrors upstream's `assertPluginCompatibility`. A missing range means `<0.8.0`, invalid ranges fail, and a prerelease passes if its stable core does.
- **Deviation:** `pkgs.nodePackages` has been removed from nixpkgs, so semver comes from the npm bundled in the full `nodejs_22` build (`NODE_PATH=${nodejs}/lib/node_modules/npm/node_modules`). This was agreed with the user on 2026-10-05.

Verified:
- **Passes on the real pin:** catppuccin-theme `>=0.9.0` against 0.10.3.
- **Fails when it should:** a temporary pin of 0.8.5 fails, naming the plugin and both versions.
- **Missing requirement:** a plugin without `requirements.paseo` fails against 0.10.3.


**Review follow-up:**
- Empty or whitespace-only ranges are now rejected, matching upstream's `validatePluginRequirements`.
- Uses unversioned `pkgs.nodejs`, which also bundles npm's semver, instead of pinning `nodejs_22`.
- Moved out of flake.nix into `packages/paseo/plugin-requirements.nix`, which flake.nix `callPackage`s into `checks`. This was the user's review request.
- The spec now records the check as implemented instead of as an out-of-scope follow-up.
