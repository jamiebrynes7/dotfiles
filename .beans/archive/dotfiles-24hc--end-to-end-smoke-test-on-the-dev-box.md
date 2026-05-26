---
# dotfiles-24hc
title: End-to-end smoke test on the dev box
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:50Z
updated_at: 2026-05-26T17:06:38Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-ottn
---

After packaging, build via `nix flake check`, install via the user's host config, restart the user service, cd into a beans project, observe registration in `beansctl ls` and the launcher at `http://localhost:9000`. Owns: no source files; produces a checklist of manual verification steps that the implementer walks through.

## Summary of Changes

Closed alongside child `dotfiles-7r70`. Launchd agent verified loading cleanly on the dev box; deeper checklist items deferred to organic use.
