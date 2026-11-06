---
# dotfiles-1p9i
title: Show repository-skill warnings in the agent's chat
status: completed
type: task
priority: normal
created_at: 2026-11-04T15:36:09Z
updated_at: 2026-11-06T11:59:35Z
parent: dotfiles-l44k
blocked_by:
    - dotfiles-ki8f
---

**Spec:** `docs/specs/2026-11-04-paseo-repo-skills.md` — The Paseo plugin (Warnings, Client half), Error handling

## What to build

Every warning case the `repo-skills` hook already logs also adds a warning row to the affected agent's chat, so a broken setup is visible where the user is working. The hook has no agent id, so warnings are held by the agent's `cwd` and posted from `agent.create.after`. The plugin's client half renders the row.

## Acceptance criteria

- [x] For each warning case in the spec's error-handling table (config missing or invalid, `git` failing or timing out, plugin folder missing, `plugin-dir` already set, several matching keys), the created agent's chat shows a warning row naming the reason.
- [x] Silent cases (non-Claude agent, not a git repository, no matching remote) add no row.
- [x] Manual end-to-end (carried over from dotfiles-ki8f): a Claude agent created through Paseo in a worktree of a declared repository lists that repository's skills as `<owner>-<repo>:<skill>`, confirming the live `--plugin-dir` passthrough; an agent in an undeclared repository lists none of them.
- [x] A successful load adds no row.
- [x] A warning recorded for an agent whose creation then failed is not attached to the next agent created in the same directory.
- [x] The row renders in theme colours on desktop and in the browser.

## Notes

- Toasts are client-only (`useToast`); the daemon side can't trigger one, which is why this is a chat row (`paseo.agents.ref(id).timeline.append` plus a client timeline renderer).

## Summary of Changes

- Warning rows. `agent.create.before` records each warning under a one-off token in the request env (`PASEO_REPO_SKILLS_WARNING`). `agent.open.before`, which has the agent id, claims the token and strips it. `agent.create.after` posts the row with `timeline.append`. The token replaces the spec's cwd-keyed pairing, so a failed creation's warning can't reach a retry in the same directory. The design and its costs (registering an open hook makes plugin restarts reload live agents' sessions; the token sits in the stored `launchEnv`) are recorded in docs/specs/2026-11-06-paseo-repo-skills-warning-pairing.md.
- The hook wiring moved to `server/hooks.ts` behind injected deps, with `server/warnings.ts` for the ledger. A re-created stored agent that already carries our own `plugin-dir` is treated as unchanged rather than as a warning. A leftover per-agent entry is cleared on the next create open for that id.
- Warnings carry `reason` plus an optional `detail` (the path or value involved). The client half (`index.client.tsx`, `client/warning-card.tsx`) renders a theme-coloured card with a `TriangleAlert` icon and the detail in monospace on its own line (tagged `pmono` so the web app keeps the font).
- 42 `node:test` cases, including all three hooks driven end to end.
- Verified live on a scratch daemon: skills load in a worktree as `jamiebrynes7-dotfiles:e2e-marker`; an undeclared repo gets none; a missing plugin folder gives exactly one row on that agent; the card was checked by hand in the desktop app and the browser.
- Upstream limitation: Paseo doesn't keep `timeline.append` rows across a daemon restart. The warning shows at creation and stays in the daemon log.
