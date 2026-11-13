---
# dotfiles-5v20
title: 'Beans detail panel: copy bean ID'
status: completed
type: feature
priority: normal
created_at: 2026-11-13T13:19:21Z
updated_at: 2026-11-13T13:25:55Z
---

Add a copy button to the beans plugin detail panel that copies the selected bean's ID to the clipboard, with a toast confirming it.

- [x] Copy button beside the bean ID in the detail panel header
- [x] Toast on success / error
- [x] Typecheck passes

- [x] Tried in the paseo demo

## Summary of Changes

The detail panel shows the bean ID under the title as a pressable row with a copy icon. Pressing it copies the ID via `copyText` and confirms with a toast, or shows an error toast if the clipboard is unavailable. The ID moved out of the footer, which can sit below the fold on long beans.
