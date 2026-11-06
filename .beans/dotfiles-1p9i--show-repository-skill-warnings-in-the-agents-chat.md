---
# dotfiles-1p9i
title: Show repository-skill warnings in the agent's chat
status: todo
type: task
priority: normal
created_at: 2026-11-04T15:36:09Z
updated_at: 2026-11-06T11:11:28Z
parent: dotfiles-l44k
blocked_by:
    - dotfiles-ki8f
---

**Spec:** `docs/specs/2026-11-04-paseo-repo-skills.md` — The Paseo plugin (Warnings, Client half), Error handling

## What to build

Every warning case the `repo-skills` hook already logs also adds a warning row to the affected agent's chat, so a broken setup is visible where the user is working. The hook has no agent id, so warnings are held by the agent's `cwd` and posted from `agent.create.after`. The plugin's client half renders the row.

## Acceptance criteria

- [ ] For each warning case in the spec's error-handling table (config missing or invalid, `git` failing or timing out, plugin folder missing, `plugin-dir` already set, several matching keys), the created agent's chat shows a warning row naming the reason.
- [ ] Silent cases (non-Claude agent, not a git repository, no matching remote) add no row.
- [ ] Manual end-to-end (carried over from dotfiles-ki8f): a Claude agent created through Paseo in a worktree of a declared repository lists that repository's skills as `<owner>-<repo>:<skill>`, confirming the live `--plugin-dir` passthrough; an agent in an undeclared repository lists none of them.
- [ ] A successful load adds no row.
- [ ] A warning recorded for an agent whose creation then failed is not attached to the next agent created in the same directory.
- [ ] The row renders in theme colours on desktop and in the browser.

## Notes

- Toasts are client-only (`useToast`); the daemon side can't trigger one, which is why this is a chat row (`paseo.agents.ref(id).timeline.append` plus a client timeline renderer).
