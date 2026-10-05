---
# dotfiles-khsx
title: 'paseo module: plugins option and config ownership'
status: completed
type: feature
priority: normal
created_at: 2026-09-21T17:24:09Z
updated_at: 2026-10-05T12:26:47Z
parent: dotfiles-5nj7
---

Make `home/programs/paseo.nix` own `config.json` unconditionally and add the `plugins` option that lowers into it. Covers the `creationDefaults` carry-over, the id assertion, and the desktop/service warning.

## Summary of Changes

config.json is now Nix-owned whenever the module is enabled: t17y added the creation defaults, uace the `plugins` option and its id assertion, and cdo2 the desktop-without-service warning.
