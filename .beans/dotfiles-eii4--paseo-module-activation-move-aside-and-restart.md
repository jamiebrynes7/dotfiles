---
# dotfiles-eii4
title: 'paseo module: activation move-aside and restart'
status: in-progress
type: feature
priority: normal
created_at: 2026-09-21T17:24:10Z
updated_at: 2026-10-05T12:40:51Z
parent: dotfiles-5nj7
---

Two `home.activation` entries in `home/programs/paseo.nix` straddling the write boundary: move a daemon-written `config.json` aside before linking, and restart the daemon afterwards when the config store path changed.
