---
# dotfiles-1m4w
title: 'Beans plugin: split the viewport equally between board columns'
status: completed
type: bug
priority: normal
created_at: 2026-11-06T16:55:49Z
updated_at: 2026-11-06T17:04:38Z
---

Board columns take their width from each lane's content, so columns in different epic lanes do not line up.

- [x] Columns split the viewport equally and match in every lane, whatever the title lengths

## Summary of Changes

Board columns now use `width: 300` with `flexGrow: 1` instead of `flex: 1` with `minWidth: 300`. Content no longer sizes the columns, so they share the viewport equally and match across lanes, and below 300px each a lane scrolls. Checked by reproducing the styles in headless Chrome; a reviewer's simulation checked the Yoga layout. Not run in the Paseo app.
