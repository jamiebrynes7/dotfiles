---
# dotfiles-zr0x
title: Cover paseo repoProfiles module wiring in the home-eval check
status: todo
type: task
priority: low
created_at: 2026-11-04T18:20:58Z
updated_at: 2026-11-10T09:53:16Z
blocked_by:
    - dotfiles-d6t2
---

The `paseo-repo-profiles` flake check renders the library directly. The module layer was only verified by hand-run home-manager evals. Unchecked by CI: nothing is installed when every profile is empty; `repoProfiles` errors surface as assertions; the disabled-paseo warning fires; link names under `xdg.dataFile` match the manifest names; `repoSkills` fails with the removed-option message. The home-eval harness (dotfiles-d6t2) now exists, so add cases for these.

## Acceptance criteria

- [ ] The home-eval check fails if a non-empty `repoProfiles` stops installing `paseo-repo-profiles/<owner>-<repo>/…` links and `config.json`, or if profiles that are all empty install any
- [ ] It fails if a bad repository key no longer surfaces as a failed assertion
