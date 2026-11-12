---
# dotfiles-vkn0
title: Agents can set a status line that shows at the bottom of their chat
status: in-progress
type: task
priority: normal
created_at: 2026-11-12T11:43:07Z
updated_at: 2026-11-12T12:18:36Z
parent: dotfiles-jpfs
---

**Spec:** `docs/specs/2026-11-12-paseo-agent-status.md` — Design → The tool, The status row (not Restart or Pruning); Packaging; Error handling (timeline append fails); Spike items 1–2

## What to build

A new repo-local `agent-status` Paseo plugin, on by default wherever paseo is enabled. Every interactive agent gets a `set_status` tool (`mcp__paseo__set_status` to Claude) taking a `summary` and an optional `waiting_on`. Each call adds a one-line status row to the agent's chat in muted italic text, `summary — waiting on X · <age>`, with the age kept current. Earlier status rows draw nothing, and the raw `set_status` tool calls are hidden from the chat, so the chat holds a single status line, the newest one.

## Acceptance criteria

- [ ] With the plugin enabled, a new Claude agent in Paseo can call `mcp__paseo__set_status`, and the call returns "Status updated."
- [ ] A `summary` over 80 characters or a `waiting_on` over 60 is rejected with a validation error returned to the agent.
- [ ] After two calls, the chat shows only the second status line, with no blank gap where the first was. The `set_status` tool calls themselves don't appear.
- [ ] The line shows "— waiting on X" only when `waiting_on` was given, and its age advances without a page reload.
- [ ] If the timeline append fails, the tool still returns success and the plugin logs the error to stderr.
- [ ] `plugins.agent-status.enable = false` on a host removes the plugin from the generated Paseo config.
- [ ] Row-text formatting is covered by a `node --test` test, and the plugin passes the overlay's typecheck and test checks.

## Notes

- Settle spike items 1 and 2 first. Record what you find in the epic or this ticket: whether a renderer can return `null` cleanly, whether re-appending the same id moves the row to the end, and which `tool_call` field identifies `set_status`. If the same id moves to the end, use one row id per agent and drop the superseded step, as the spec allows.
- Keep the record of each agent's current row id in memory for now. Saving it so it survives a restart is a separate ticket.


## Findings (2026-11-12)

- **Spike 1:** re-appending a row with the same id keeps its *original* position (the daemon's timeline projection collapses by identity at the first `seqStart`). So the superseded-row approach stays. Plugin rows can't be transformed on the client either. Whether a `null` render leaves a visible gap still needs a look in the app.
- **Spike 2:** Claude's tool call shows up as a `tool_call` item with `name: "mcp__paseo__set_status"`; the transformer matches on `name`.
- **Not in the spec:** plugin agent tools only reach agents when `daemon.mcp.injectIntoAgents` is on, and Paseo 0.15.4 defaults it to off. Decided with the user: turn injection on and deny every Paseo built-in tool per provider. The list is generated from the pinned Paseo source minus a repo allowlist (`dotfiles.programs.paseo.builtinTools.allow`, empty by default), so new upstream tools are denied automatically. Providers that `requiresConfiguration` (hoplite) get the policy only once configured, because a policy entry would make them show up in the provider list.
- `mcp__paseo__set_status` is added to Claude's permission allowlist whenever the plugin is enabled. Paseo launches agents in `permissionMode: default`, so without it every update prompts.
- `plugins.agent-status.enable = false` leaves the plugin in config.json with `enabled: false`, as the module does for any disabled plugin, and removes the allowlist entry.
