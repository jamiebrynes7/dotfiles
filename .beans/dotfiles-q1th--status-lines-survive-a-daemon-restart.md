---
# dotfiles-q1th
title: Status lines survive a daemon restart
status: completed
type: task
priority: normal
created_at: 2026-11-12T11:43:19Z
updated_at: 2026-11-12T14:42:34Z
parent: dotfiles-jpfs
blocked_by:
    - dotfiles-vkn0
---

**Spec:** `docs/specs/2026-11-12-paseo-agent-status.md` — Design → The status row (Restart, Pruning); Error handling (plugin state unreadable)

## What to build

The plugin saves each agent's latest status (summary, waiting on, set-at time, row id) in plugin state. When an agent's session opens, the plugin re-adds that agent's row under the saved row id. After a daemon restart, an idle agent's status line comes back as soon as you open its chat, and a session that reopens without a restart doesn't get a duplicate row. Records for agents that no longer exist are pruned when the plugin starts.

## Acceptance criteria

- [x] Set a status, restart the Paseo daemon and reopen the agent's chat: the line is back with its original age, counted from when it was set rather than from the restart. (Demo daemon: the row came back as the chat's last row about 1s after the chat was opened, with its original `setAt`.)
- [x] Reloading the plugin while an agent's chat is open (so its session reopens) leaves exactly one status line. (Live: `paseo plugin reload`, then another turn left one visible row. Covered by a unit test too.)
- [x] After an agent is archived or deleted and the plugin restarts, its record is gone from plugin state. (Live: archived, reloaded the plugin, and the record was pruned on the first hook call.)
- [x] If the plugin's state file is corrupt, the plugin starts with empty state, logs a warning, and `set_status` keeps working. (`node --test`: non-JSON, wrong shape and unknown version each start empty, warn, and are overwritten by the next save. Not exercised live.)

## Constraints

- The tool keeps returning success even when saving or appending fails, as ticket 1 established.


## Findings (2026-11-12)

- Confirmed that plugin rows are lost on a daemon restart: an existing chat lost both of its status rows.
- The `agent.open.before` hook runs before the daemon registers the agent (`registerSession` comes after `createSession`/`resumeSession`), so appending from inside the hook fails with "Unknown agent". The restore runs after the hook, retrying every 250 ms for up to 30 s. It shares the per-agent queue with turn-end placement and re-reads the saved row id on every attempt, so it can't re-show a replaced status.
- The server context has no Paseo handle, so pruning runs once, on the first hook call after the plugin starts. It keeps the agents `paseo.agents.list` returns, which excludes archived ones.
- State lives in `$PASEO_HOME/plugin-state/agent-status.json` (`{ version: 1, agents: { <id>: { status, rowId } } }`) and is written atomically, as `last-response` does.
