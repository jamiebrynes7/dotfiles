---
# dotfiles-zool
title: Collapse/expand all feature rows from the beans board toolbar
status: todo
type: task
priority: normal
created_at: 2026-11-12T09:51:11Z
updated_at: 2026-11-12T09:51:11Z
parent: dotfiles-us8h
blocked_by:
    - dotfiles-ty72
---

**Spec:** `docs/specs/2026-11-12-paseo-beans-feature-rows.md` — Toolbar: collapse or expand all features

## What to build

A toolbar button that collapses or expands every feature row on the board in one press, giving a one-click features-only view while still letting you reopen a single row afterwards.

## Acceptance criteria

- [ ] With any visible feature row expanded, the button reads "Collapse features" and pressing it collapses every feature row on the board
- [ ] With every feature row collapsed, it reads "Expand features" and pressing it expands them all
- [ ] After using it, an individual row can still be toggled by its chevron
- [ ] Epic lane collapse state is unaffected
- [ ] The button is disabled while a search is active and hidden when the board has no feature rows

## Constraints

- Writes only to the existing per-row collapse state; no separate mode or new tab-state field.
