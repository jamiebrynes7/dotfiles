---
# dotfiles-q1th
title: Status lines survive a daemon restart
status: todo
type: task
priority: normal
created_at: 2026-11-12T11:43:19Z
updated_at: 2026-11-12T11:43:22Z
parent: dotfiles-jpfs
blocked_by:
    - dotfiles-vkn0
---

**Spec:** `docs/specs/2026-11-12-paseo-agent-status.md` — Design → The status row (Restart, Pruning); Error handling (plugin state unreadable)

## What to build

The plugin saves each agent's latest status (summary, waiting on, set-at time, row id) in plugin state. When an agent's session opens, the plugin re-adds that agent's row under the saved row id. After a daemon restart, an idle agent's status line comes back as soon as you open its chat, and a session that reopens without a restart doesn't get a duplicate row. Records for agents that no longer exist are pruned when the plugin starts.

## Acceptance criteria

- [ ] Set a status, restart the Paseo daemon and reopen the agent's chat: the line is back with its original age, counted from when it was set rather than from the restart.
- [ ] Reloading the plugin while an agent's chat is open (so its session reopens) leaves exactly one status line.
- [ ] After an agent is archived or deleted and the plugin restarts, its record is gone from plugin state.
- [ ] If the plugin's state file is corrupt, the plugin starts with empty state, logs a warning, and `set_status` keeps working.

## Constraints

- The tool keeps returning success even when saving or appending fails, as ticket 1 established.
