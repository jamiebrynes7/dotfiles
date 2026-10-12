---
# dotfiles-eii4
title: 'paseo module: activation move-aside and restart'
status: completed
type: feature
priority: normal
created_at: 2026-09-21T17:24:10Z
updated_at: 2026-10-05T12:44:20Z
parent: dotfiles-5nj7
---

Two `home.activation` entries in `home/programs/paseo.nix` straddling the write boundary: move a daemon-written `config.json` aside before linking, and restart the daemon afterwards when the config store path changed.

## Summary of Changes

Activation moves a daemon-written config.json aside before `checkLinkTargets` (t4ve) and restarts the daemon through `home.file.onChange` when the config content changes (cxg5). Both differ from the original plan; see each task's summary.
