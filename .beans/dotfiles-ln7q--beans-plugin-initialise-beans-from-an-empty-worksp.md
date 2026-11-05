---
# dotfiles-ln7q
title: 'beans plugin: initialise beans from an empty workspace'
status: todo
type: task
priority: normal
created_at: 2026-11-05T14:15:53Z
updated_at: 2026-11-05T14:15:53Z
parent: dotfiles-oweh
blocked_by:
    - dotfiles-khut
---

**Spec:** `docs/specs/2026-11-05-paseo-beans-plugin.md` — Server half (Init); Client half (Board panel → States); Error handling summary

## What to build

In a workspace whose directory has no `.beans.yml` up the tree, the board shows an empty state naming the directory with an **Initialise beans** button that runs `beans init` there, after which the board loads.

## Acceptance criteria

- [ ] In a git repo with no `.beans.yml` up the tree, the board shows "No beans project in <directory>" and an Initialise beans button
- [ ] Pressing it creates `.beans/` and `.beans.yml` in the workspace directory (left uncommitted) and the board then loads the empty project
- [ ] The init RPC refuses with an error when a `.beans.yml` is already found from the directory, and a failed init surfaces as a toast
