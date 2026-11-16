---
# dotfiles-vg6h
title: Per-repository Claude profiles for Paseo agents
status: completed
type: epic
priority: normal
created_at: 2026-11-10T09:35:43Z
updated_at: 2026-11-10T10:09:18Z
---

**Goal:** Generalise the repo-skills Paseo plugin into repo-profiles, so a Claude agent in a matched repository gets both that repository's skills and its Claude Code settings (via `--settings`, e.g. `autoMode` rules).

**Spec:** docs/specs/2026-11-10-paseo-repo-profiles.md

**Testing seam:** the renamed renderer flake check (fixture rendering), the plugin's `node:test` unit tests and typecheck/sdk-version checks, plus a manual run on the demo daemon.

Motivated by the mirador bean on auto mode blocking lease-pinned pushes to `jbrynes/*`. The samsara-dev rule text, the `dotfiles-samsara` declaration and the rollout on devbox/devbox-1 stay with that bean.

## Summary of Changes

Landed in three PRs: #452 (spec and plan), #453 (dotfiles-g2b5: rename repo-skills to repo-profiles and key skills by repository) and #455 (dotfiles-y3c5: per-repository settings via --settings). Downstream, `dotfiles-samsara` still needs to migrate `repoSkills` to `repoProfiles` and declare the samsara-dev autoMode rules. That work, and the devbox rollout, belongs to the mirador bean.
