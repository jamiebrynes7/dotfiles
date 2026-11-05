---
# dotfiles-vlz5
title: 'beans plugin: start an agent on a ready bean'
status: todo
type: task
priority: normal
created_at: 2026-11-05T14:15:53Z
updated_at: 2026-11-05T14:15:53Z
parent: dotfiles-oweh
blocked_by:
    - dotfiles-p38z
---

**Spec:** `docs/specs/2026-11-05-paseo-beans-plugin.md` — Client half (Detail panel → Start button; Start modal); Error handling summary

## What to build

From the Explorer detail of a ready bean, a Start button opens a modal to launch an agent on it — in the current workspace or in a new worktree — with an editable prompt and a provider/model picker, then navigates to the result.

## Acceptance criteria

- [ ] The Start button appears only for ready beans: not blocked (explicitly or via an ancestor), status todo or in-progress, no implicitStatus, type not epic/milestone
- [ ] The modal prefills the prompt with `Implement bean <id>.` and it is editable
- [ ] The provider/model picker defaults to the most recent agent in this workspace, else in this project, else claude's default model; mode and thinking carry over only while the provider is unchanged
- [ ] "This workspace" creates an agent titled `<id>: <bean title>` in the current workspace and navigates to it
- [ ] "New worktree" creates a worktree workspace on branch `<type>/<slug>` (editable) with that agent, and navigates to the new workspace
- [ ] A creation failure (e.g. branch already exists) is shown inline and the modal stays open; on a host without `navigation`, success shows a toast instead
