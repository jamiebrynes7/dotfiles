---
# dotfiles-zl1c
title: Check external plugins' requirements.paseo against the pinned daemon
status: todo
type: task
priority: low
created_at: 2026-09-21T17:32:18Z
updated_at: 2026-09-21T17:32:18Z
parent: dotfiles-5nj7
blocked_by:
    - dotfiles-m8y6
---

Follow-up from `docs/specs/2026-09-21-paseo-plugins.md`.

A plugin manifest may declare `requirements.paseo` as an npm semver range, and the daemon enforces it at load via `assertPluginCompatibility` — on install, on startup, on enable and on reload. A plugin that no longer admits the pinned paseo version therefore fails at *runtime*, showing up as `failed` in `paseo plugin ls` on the host rather than as a red check.

`packages/paseo-plugin-catppuccin-theme` declares `>=0.8.0` against a pinned 0.8.0, so it is fine today. The risk is asymmetric: bumping `packages/paseo` is what breaks it, and that bump arrives as an auto-update PR whose diff says nothing about plugins.

Sketch: a check derivation that reads each plugin package's `paseo-plugin.json` and the `version` from `packages/paseo/hashes.json`, then evaluates the range. Semver range matching is the awkward part — `nodejs` with `require("semver")` is the honest implementation, and `pkgs.nodePackages.semver` is available. A plugin with no `requirements.paseo` means "predates 0.8" and must fail.

Blocked until at least one external plugin package exists to check.
