# Agent status line — spec

Date: 2026-11-12

This spec adds a Paseo plugin, `agent-status`. Each agent keeps a one-line status at the bottom of
its chat saying what it is doing and what it is waiting on. A Claude Code `Stop` hook makes the
agent update the status before every turn ends.

## Problem

With many parallel agents in one workspace, it's easy to forget what each one is doing or
waiting on. To find out, you have to scroll back through its chat. Paseo shows whether an agent
is running and `last-response` shows how long ago it answered, but neither says *what* it is
working on.

## Goals

- Every agent chat ends with a short, italic line: `<summary> — waiting on <x> · 12m ago`.
- The agent writes the line itself, so it carries intent ("waiting on your call on the
  schema"), not just a description of activity.
- Claude agents can't end a turn without refreshing it.
- The line survives a daemon restart.

## Non-goals

- **No composer slot.** Paseo 0.15.4 has no plugin surface above the composer; the line is a
  timeline row that sits above the composer when the agent is idle. An upstream slot is a
  separate piece of work.
- **No automatic fallback summary.** If the agent didn't set a status, nothing is generated for
  it.
- **No enforcement for Codex.** Codex agents get the tool but no `Stop` hook.
- **No change to `last-response`.** Its pill stays as is.
- **No workspace overview panel.** It may come later; this spec covers only the in-chat line.

## Verified upstream facts (Paseo 0.15.4)

Read from the installed daemon source, since the online reference doesn't cover these:

- `defineAgentTool({ name, title?, description, input: <zod schema>, execute(input, { agent,
  paseo, signal }) })` returns `{ text?, structuredContent?, isError? }`. The name must match
  `^[a-z][a-z0-9_]*$` and be at most 64 characters. A thrown error or a failed parse comes back
  to the model as `isError`.
- Tools and `env` are returned from `server.before("agent.session_open")` (internally
  `agent.open.before`), and that hook may change only `env`, `tools` and `mcpServers`. Tools are
  attached only to interactive agents.
- Paseo serves plugin tools through its own MCP server, named `paseo`, so Claude sees the tool as
  `mcp__paseo__set_status`.
- The Claude provider loads the `user`, `project` and `local` setting sources, so hooks from
  `~/.claude/settings.json` run for Paseo's Claude agents. Hooks are turned off only for Paseo's
  internal agents.
- `paseo.agents.ref(id).timeline.append({ type: "plugin", id, kind, version, data })` adds a
  row. Re-appending with the same `id` replaces it. Rows live in daemon memory and are lost on a
  daemon restart.
- A timeline transformer sees one *built-in* item at a time, and returning `[]` removes it. Plugin
  rows can't be transformed.

## Design

### The tool: `set_status`

The input has two fields:

```ts
z.object({
  summary: z.string().min(1).max(80),    // what the agent is doing, in one line
  waiting_on: z.string().max(60).optional(), // e.g. "CI on #1234", "you: schema choice"
})
```

Input over the limits fails validation. The agent sees the error and retries with shorter text.

The tool description tells the agent to:
- call `set_status` when it starts a task and whenever its phase changes;
- always call it before ending a turn;
- set `waiting_on` whenever it is blocked on something, including "you" when it needs input or
  has finished.

`execute` saves the status, updates the chat row (see below) and returns "Status updated."

The plugin attaches the tool to every interactive agent, whatever its provider. In the same hook
it sets `PASEO_STATUS=1` in the agent's env.

### The status row

Plugin state stores one record per agent: `{ summary, waitingOn?, setAt, rowId }`.

On `set_status`:

1. If the agent already has a record, re-append its old `rowId` with `{ superseded: true }`.
   The renderer draws nothing for superseded rows.
2. Append a new row with a fresh `rowId` and `{ summary, waitingOn, setAt }`.
3. Save the new record.

The client renderer draws the row as one line of `foregroundMuted` italic text:
`summary — waiting on X · <age>`. The "waiting on" part appears only when it is set. The age is
formatted like `last-response`'s and refreshed by a shared client-side ticker.

A client transformer removes the `set_status` tool-call items from the chat. That keeps one
status line per update.

**Restart.** In the `agent.session_open` hook, if the agent has a stored record, the plugin
re-appends its row under the stored `rowId`. Opening a stored agent's chat loads the agent, so
the line reappears when you look at it. Re-appending the same id also means a session reopened
without a restart (for example, after a plugin reload) doesn't duplicate the row.

**Pruning.** When the plugin starts, it drops records for agents that `paseo.agents.list` no
longer returns, the way `last-response` does.

### The `Stop` hook

The hook is a small TypeScript script shipped in the plugin package and run with Nix's
`node`. It is registered through `dotfiles.programs.claude-code.hooks` whenever the paseo module
and the `agent-status` plugin are both enabled.

Its behaviour:

1. If `PASEO_STATUS` is not set → exit 0 (allow).
2. If the hook input has `stop_hook_active: true` → exit 0, so it can't loop.
3. Read the JSONL transcript at `transcript_path`. Find the last *real* user prompt, meaning a
   `user` entry that is not purely `tool_result` blocks. If an assistant `tool_use` block named
   `mcp__paseo__set_status` comes after it → exit 0.
4. Otherwise print `{"decision": "block", "reason": "Call set_status with your current summary
   (and waiting_on, if blocked) before ending your turn."}`.

This applies to every turn, including trivial ones. On those the agent re-confirms its status.

### Packaging

- Source: `ts/paseo-plugin-agent-status/`, built and checked through the existing `ts/` overlay
  like `last-response`.
- Exposed as `pkgs.dotfiles.paseo-plugin-agent-status`. `home/programs/paseo.nix` sets the
  package with `mkDefault`, like the other repo plugins, so it is on wherever paseo is enabled.
  A host opts out with `plugins.agent-status.enable = false`, which also removes the hook.

## Error handling

- **Timeline append fails** (the host lacks `pluginTimelineItems`, or the agent was removed):
  `execute` still saves the record and returns success, and logs the error to stderr. The agent
  shouldn't retry because of a display failure.
- **Plugin state is unreadable or corrupt:** start with empty state and log a warning.
- **Hook can't read or parse the transcript:** allow the stop and write the reason to stderr.
  The hook fails open, so a bug in it never wedges an agent.
- **Plugin stopped but a session still has `PASEO_STATUS`:** an agent would be told to call a
  tool it no longer has. Stopping or reloading a plugin with a session-open hook marks open
  sessions stale, and they reopen without the env var before the next prompt. The fail-open rule
  covers whatever window remains, because `stop_hook_active` allows the second stop.

## Spike items (check first when building)

1. A renderer can draw nothing (`null`) for a superseded row without leaving blank space. If not,
   collapse it to zero height. If re-appending the same `id` moves the row to the end of the
   chat, use one id per agent instead and drop the superseded step.
2. How a plugin tool call appears as a timeline `tool_call` item (which field holds
   `set_status`), so the transformer can match it.
3. `PASEO_STATUS` from `agent.session_open` reaches the environment of hook subprocesses.

## Testing seams

- **`node --test`** (the existing `npmScriptCheck` wiring):
  - the hook's transcript check, using fixture JSONL: status set after the prompt, set only
    before it, not set, tool-result-only user entries, `stop_hook_active`, env var missing;
  - row-text formatting.
- **Typecheck** through the existing `tsChecks`.
- **Manual check in Paseo**, following the plugin skill's checklist:
  - run a Claude agent turn and confirm the line appears and updates;
  - confirm the tool call is hidden;
  - restart the daemon and reopen the chat to confirm the line comes back;
  - confirm the hook blocks a turn that skipped the call.
