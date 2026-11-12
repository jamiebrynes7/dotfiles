---
# dotfiles-g7kb
title: Claude agents can't end a turn without updating their status
status: completed
type: task
priority: normal
created_at: 2026-11-12T11:43:19Z
updated_at: 2026-11-12T14:34:00Z
parent: dotfiles-jpfs
blocked_by:
    - dotfiles-vkn0
---

**Spec:** `docs/specs/2026-11-12-paseo-agent-status.md` — Design → The tool (`PASEO_STATUS` env), The `Stop` hook, Packaging (hook wiring); Error handling (hook failures, plugin stopped); Spike item 3

## What to build

The plugin sets `PASEO_STATUS=1` in every interactive agent's env at session open. A Claude Code `Stop` hook ships with the plugin and runs on Nix's `node`. It is registered automatically through `dotfiles.programs.claude-code.hooks` when both the paseo module and the `agent-status` plugin are enabled. The hook blocks a turn that has no `mcp__paseo__set_status` call since the last real user prompt, so the agent updates its status and then stops. Outside Paseo, or when the plugin is off, it does nothing.

## Acceptance criteria

- [x] In Paseo, telling a Claude agent "reply 'hi' and don't call any tools" makes the hook block. The agent then calls `set_status` and ends the turn. (Demo daemon, hook from a project settings file pointing at the packaged plugin.)
- [x] A turn that already called `set_status` after the latest user prompt ends without being blocked. (Live: the hook ran once and didn't block.)
- [x] A Claude Code session outside Paseo (no `PASEO_STATUS`) is never blocked. (Live `claude -p` in the same repo with the hook active.)
- [x] Setting `plugins.agent-status.enable = false` removes the hook from the generated Claude settings. (Evaluated against the macbook config.)
- [x] `node --test` fixture tests cover:
  - a status set after the prompt;
  - a status set only before the prompt;
  - no status set;
  - user entries made only of tool results (these don't count as a prompt);
  - `stop_hook_active: true`, which allows the stop;
  - the env var missing;
  - an unreadable transcript, which allows the stop and writes to stderr.
  - Also covered: meta and subagent entries, a subagent's own `set_status`, a torn last line, malformed hook input.

## Notes

- Settle spike item 3 first: confirm that env from `agent.session_open` reaches hook subprocesses. If it doesn't, stop and raise it, because the gating design depends on it.


## Findings (2026-11-12)

- **Spike 3 settled:** `PASEO_STATUS`, set in the plugin's `agent.open.before` hook, reaches Claude Code's hook subprocesses.
- Claude records the hook's block reason as a user text entry ("Stop hook feedback: …"). The check treats it as a new prompt, and that's harmless: the follow-up stop has `stop_hook_active` set, so it's allowed.
- With the first block reason, agents told the user about the reminder. The reason now says it's automatic and not to be mentioned, and the agent's final reply was just "Hi."
- The hook can't import `zod`, since the packaged plugin has no `node_modules`. The tool name and env var moved to a dependency-free `shared/tool-contract.ts`.
- Claude ignores `permissions.allow` from an untrusted project's `.claude/settings.json`, while still running that project's hooks. That's why the demo still prompted for `set_status`. The real allow rule lives in user settings, which workspace trust doesn't affect; it's only confirmed once a host switches.

- **Closing line:** Claude Code (2.1.322) won't let a turn end on a silent tool call. It adds an `isMeta` note ("Your previous response had no visible output…"), and the agent then repeats its answer. Decided with the user to accept a fixed closer: the block reason has the agent call `set_status` and then end with exactly "Status updated.". Three runs of the no-tools prompt ended "hi" → status update → "Status updated.", with no forced-reply note.
