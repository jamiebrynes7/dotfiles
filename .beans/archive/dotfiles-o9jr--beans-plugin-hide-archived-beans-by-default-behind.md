---
# dotfiles-o9jr
title: 'Beans plugin: hide archived beans by default behind a toggle'
status: completed
type: feature
priority: normal
created_at: 2026-11-06T16:40:07Z
updated_at: 2026-11-06T16:46:15Z
---

The beans paseo plugin's board shows every bean, archived ones included. Hide archived beans by default, with a 'Show archived' toggle in the toolbar alongside 'Show scrapped'.

- [x] Expose whether a bean is archived on the board RPC
- [x] Filter archived cards in layout, keeping archived epics as lanes for live children
- [x] Add the toolbar toggle
- [x] Seed an archived bean in the demo

## Summary of Changes

The board RPC now reports `archived`, derived server-side from the bean path being under `archive/`. `layout` hides archived cards unless `showArchived` is set, while archived epics still head lanes for unarchived cards. The toolbar has a Show archived switch, off by default and independent of Show scrapped; the tab-state field has a schema default so saved tabs keep their state. The demo seed includes archived beans. Tested with unit tests, typecheck and the seed against the real CLI; the UI has not been checked in the Paseo app.
