---
# dotfiles-ec92
title: 'Beans detail panel: show the beans a bean blocks'
status: completed
type: feature
priority: normal
created_at: 2026-11-20T10:34:12Z
updated_at: 2026-11-20T10:34:37Z
---

The detail panel lists "Blocked by" but not the reverse. Add a "Blocks" section from the `blocking` relation so the link reads both ways.

- [x] Query and schema carry `blocking`
- [x] Panel renders a Blocks section
- [x] Tests and typecheck pass

## Summary of Changes

`readBean` now also queries `blocking { id title status type }`, `BeanDetail` carries it, and the detail panel renders it as a "Blocks" section directly under "Blocked by".
