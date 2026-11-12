---
# dotfiles-g7kb
title: Claude agents can't end a turn without updating their status
status: todo
type: task
priority: normal
created_at: 2026-11-12T11:43:19Z
updated_at: 2026-11-12T11:43:22Z
parent: dotfiles-jpfs
blocked_by:
    - dotfiles-vkn0
---

**Spec:** `docs/specs/2026-11-12-paseo-agent-status.md` — Design → The tool (`PASEO_STATUS` env), The `Stop` hook, Packaging (hook wiring); Error handling (hook failures, plugin stopped); Spike item 3

## What to build

The plugin sets `PASEO_STATUS=1` in every interactive agent's env at session open. A Claude Code `Stop` hook ships with the plugin and runs on Nix's `node`. It is registered automatically through `dotfiles.programs.claude-code.hooks` when both the paseo module and the `agent-status` plugin are enabled. The hook blocks a turn that has no `mcp__paseo__set_status` call since the last real user prompt, so the agent updates its status and then stops. Outside Paseo, or when the plugin is off, it does nothing.

## Acceptance criteria

- [ ] In Paseo, telling a Claude agent "reply 'hi' and don't call any tools" makes the hook block. The agent then calls `set_status` and ends the turn.
- [ ] A turn that already called `set_status` after the latest user prompt ends without being blocked.
- [ ] A Claude Code session outside Paseo (no `PASEO_STATUS`) is never blocked.
- [ ] Setting `plugins.agent-status.enable = false` removes the hook from the generated Claude settings.
- [ ] `node --test` fixture tests cover:
  - a status set after the prompt;
  - a status set only before the prompt;
  - no status set;
  - user entries made only of tool results (these don't count as a prompt);
  - `stop_hook_active: true`, which allows the stop;
  - the env var missing;
  - an unreadable transcript, which allows the stop and writes to stderr.

## Notes

- Settle spike item 3 first: confirm that env from `agent.session_open` reaches hook subprocesses. If it doesn't, stop and raise it, because the gating design depends on it.
