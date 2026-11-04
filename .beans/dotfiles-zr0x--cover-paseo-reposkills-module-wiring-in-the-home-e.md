---
# dotfiles-zr0x
title: Cover paseo repoSkills module wiring in the home-eval check
status: todo
type: task
priority: low
created_at: 2026-11-04T18:20:58Z
updated_at: 2026-11-04T18:20:58Z
blocked_by:
    - dotfiles-d6t2
---

dotfiles-v7fb's `paseo-repo-skills` flake check renders the library directly. The module layer was only verified by hand-run home-manager evals: nothing installed when `repoSkills` is empty; `repoSkills.errors` surfacing as assertions; the disabled-paseo warning; link names matching manifest names under `xdg.dataFile`. Once the home-eval harness (dotfiles-d6t2) exists, add cases for these.

## Acceptance criteria

- [ ] The home-eval check fails if a non-empty `repoSkills` stops installing `paseo-repo-skills/<name>` links and `config.json`, or an empty one installs any
- [ ] It fails if a bad repository key no longer surfaces as a failed assertion
