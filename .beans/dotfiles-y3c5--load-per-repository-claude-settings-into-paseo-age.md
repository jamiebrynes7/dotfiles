---
# dotfiles-y3c5
title: Load per-repository Claude settings into Paseo agents via --settings
status: todo
type: task
created_at: 2026-11-10T09:36:04Z
updated_at: 2026-11-10T09:36:04Z
parent: dotfiles-vg6h
blocked_by:
    - dotfiles-g2b5
---

**Spec:** `docs/specs/2026-11-10-paseo-repo-profiles.md`: §Nix surface (`settings`), §Rendering (settings.json), §Config file (`settings`), §The Paseo plugin, §Warnings, §Error handling

## What to build

`repoProfiles.<key>.settings` (JSON-typed, merged across modules) renders a per-repository `settings.json` behind a stable link, and the config entry gains a `settings` path. For a matched Claude agent, the hook sets `providerOptions.extraArgs.settings` to that path, independently of `plugin-dir`. If one field is skipped (target missing, or key already set to something else), the other is still applied. Every problem from one creation is reported in that agent's single warning row, which says which field each problem affects and what was loaded.

## Acceptance criteria

- [ ] With an `autoMode.environment` marker declared for a repository, a Claude agent created there is saved with `extraArgs.settings` set to the stable link, and `claude --settings <link> auto-mode config` shows the marker
- [ ] A repository with settings but no skills gets a `settings` entry and no `pluginDir`, and the reverse holds too; the flake check asserts both
- [ ] Settings for one repository declared in two modules render as one merged `settings.json`, with lists concatenated (flake check)
- [ ] Unit tests: for each field independently, it is set, left alone when already ours (no warning), left alone with a warning when set elsewhere, and skipped with a warning when its target is missing
- [ ] Unit test: one field skipped while the other applies yields one warning row that lists the skip and names what was loaded
- [ ] Unit test: several problems in one creation (e.g. a multi-match plus a skipped field) yield one row carrying all of them, which the client card renders as a list

## Constraints

- Agent creation never fails because of the plugin.
- The hook checks only that the settings file is readable. It does not parse it.
