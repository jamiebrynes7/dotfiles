---
# dotfiles-42qz
title: 'paseo plugin: recover Claude agents from expired logins'
status: todo
type: task
created_at: 2026-10-22T13:03:04Z
updated_at: 2026-10-22T13:03:04Z
---

**Spec:** `docs/specs/2026-10-22-paseo-claude-reauth-plugin.md` — all sections

## What to build

A repo-local paseo plugin, `claude-reauth`, packaged like the other repo-local plugins and enabled by default. When a Claude agent replies with an expired or revoked login, the reply shows in the chat as a "Claude login expired" card. **Log in & reload** logs in on the daemon host and reloads that agent, keeping its conversation. **Reload only** just reloads it. The card shows progress and names the step if one fails, from whichever client device it was pressed.

## Acceptance criteria

- [ ] A reply containing one of the spec's known phrases renders as the card, both when it arrives live and when the chat is reopened; a reply still streaming, or one with no known phrase, renders as plain text.
- [ ] **Reload only** reloads the agent through `paseo agent reload`; the card moves through reloading to "Reloaded — send your message again", and the conversation survives.
- [ ] **Log in & reload** runs `claude auth login` on the host (browser opens on the host), and after the login finishes the card reaches done without any shell step.
- [ ] Two cards that start a login at the same time share one `claude auth login` process.
- [ ] A login that exits non-zero, or is still running after 5 minutes, leaves the card failed at the login step with the error; the first URL the login printed, if any, shows as an "Open login page" link.
- [ ] A failed reload, including an unknown agent id or a missing `paseo` binary, leaves the card failed at the reload step with the error.
- [ ] A card opened on a second device while a job is running shows the in-flight phase and follows it to the end.
- [ ] The flake's `paseo-plugin-claude-reauth-typecheck`, `paseo-plugin-claude-reauth-sdk-version` and `paseo-plugin-requirements` checks pass.

## Constraints

- No RPC waits on the login or the reload: plugin RPCs time out at 30 s, so both run as daemon-side jobs that the card polls (`start` / `status`, shapes in the spec's Contracts section).
- The plugin only automates the documented workaround — no re-sending the failed message, no persisted state, no other providers (spec Non-goals).
- Stopping or reloading the plugin kills any running login or reload child.

## Notes

- Reproduce on demand with `claude auth logout` on the host, then message a live Claude agent.
