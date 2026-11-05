---
# dotfiles-p38z
title: 'beans plugin: bean detail in the Explorer'
status: todo
type: task
priority: normal
created_at: 2026-11-05T14:15:53Z
updated_at: 2026-11-05T14:15:53Z
parent: dotfiles-oweh
blocked_by:
    - dotfiles-khut
---

**Spec:** `docs/specs/2026-11-05-paseo-beans-plugin.md` — Server half (RPC contracts: bean; Board and detail queries); Client half (Shared store and selection; Detail panel)

## What to build

Pressing a card on the board selects that bean for the workspace and reveals a "Bean" panel in the Explorer showing its detail; relationship rows in the panel navigate the selection. The panel stays current using the same fingerprint polling as the board.

## Acceptance criteria

- [ ] Pressing a card reveals the Explorer with the "Bean" panel showing that bean's title, id, status, type, priority, timestamps and rendered markdown body
- [ ] Parent, blockers and children are listed as rows; pressing one shows that bean in the panel
- [ ] With nothing selected the panel shows a hint to pick a card; selection is per workspace (selecting in one workspace does not change another's panel)
- [ ] Editing the selected bean via the CLI updates the panel within ~10 s
- [ ] A selected bean that is deleted shows "Bean <id> not found"
- [ ] The detail panel is offered only in the Explorer location, not as a workspace tab
