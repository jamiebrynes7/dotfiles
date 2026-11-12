---
# dotfiles-zool
title: Collapse/expand all feature rows from the beans board toolbar
status: completed
type: task
priority: normal
created_at: 2026-11-12T09:51:11Z
updated_at: 2026-11-12T11:06:04Z
parent: dotfiles-us8h
blocked_by:
    - dotfiles-ty72
---

**Spec:** `docs/specs/2026-11-12-paseo-beans-feature-rows.md` — Toolbar: collapse or expand all features

## What to build

A toolbar button that collapses or expands every feature row on the board in one press, giving a one-click features-only view while still letting you reopen a single row afterwards.

## Acceptance criteria

- [x] With any visible feature row expanded, the button reads "Collapse features" and pressing it collapses every feature row on the board
- [x] With every feature row collapsed, it reads "Expand features" and pressing it expands them all
- [x] After using it, an individual row can still be toggled by its chevron
- [x] Epic lane collapse state is unaffected
- [x] The button is disabled while a search is active and hidden when the board has no feature rows

## Constraints

- Writes only to the existing per-row collapse state; no separate mode or new tab-state field.

## Summary of Changes

The beans board toolbar has a "Collapse features" / "Expand features" button that sets every feature row's collapse state in one press. With every row collapsed, the board reads as a list of feature headers.

- `shared/layout.ts` gains `featureRows`, `isRowSaved`, `anyFeatureRowExpanded` and `withFeatureRowsCollapsed`.
  - The label looks only at rows in expanded lanes, and falls back to every row when all lanes are collapsed.
  - A press writes to every feature row on the board and never touches lane keys. When the new value matches a row's default, the row's key is dropped, so the row keeps following its default if its status changes later.
- The button's label and visibility come from the unsearched board, so a search only disables it, never hides or relabels it. It is hidden when the board has no feature rows.
- Unit tests cover the write rules and the label rules. You checked it by hand in `ts/paseo-demo.sh beans`.
