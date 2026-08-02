---
# dotfiles-75un
title: Generalise task-implementer away from beans
status: todo
type: feature
priority: low
created_at: 2026-08-02T12:18:09Z
updated_at: 2026-08-02T12:18:24Z
blocked_by:
    - dotfiles-zo7y
---

`task-implementer` drives the full implement → review → land loop but is written against beans specifically (bean ids, `beans update` calls, `beans next`). That coupling is why it and `whats-next` stayed in this repository's `.claude/skills/` when the beans hooks became the `df-beans` plugin: shipping `whats-next` globally without `task-implementer` would break its handoff in other repositories.

Split it into a tracker-agnostic core plus a beans-specific variant, then move both skills into plugins:

- the generic implementation loop (branch, implement, subagent review, user review, PR with auto-merge) belongs in `df-base`, working from a plain task description
- the beans-specific parts (resolving a bean id, status transitions, the `Bean:` commit trailer, `beans next` handoff) belong in `df-beans`, alongside `whats-next`

Once that lands, `df-beans` carries skills as well as hooks, and this repository's `.claude/skills/` can be emptied.

Blocked on the plugin epic landing first (dotfiles-zo7y).
