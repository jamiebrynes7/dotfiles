---
# dotfiles-24hc
title: End-to-end smoke test on the dev box
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:50Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-ottn
---

After packaging, build via `nix flake check`, install via the user's host config, restart the user service, cd into a beans project, observe registration in `beansd ls` and the launcher at `http://localhost:9000`. Owns: no source files; produces a checklist of manual verification steps that the implementer walks through.
