---
# dotfiles-42qz
title: 'paseo plugin: recover Claude agents from expired logins'
status: in-progress
type: task
priority: normal
created_at: 2026-10-22T13:03:04Z
updated_at: 2026-10-22T15:38:42Z
---

**Spec:** `docs/specs/2026-10-22-paseo-claude-reauth-plugin.md` — all sections

## What to build

A repo-local paseo plugin, `claude-reauth`, packaged like the other repo-local plugins and enabled by default. When a Claude agent replies with an expired or revoked login, the reply shows in the chat as a "Claude login expired" card. **Log in & reload** logs in on the daemon host and reloads that agent, keeping its conversation. **Reload only** just reloads it. The card shows progress and names the step if one fails, from whichever client device it was pressed.

## Acceptance criteria

- [x] A reply containing one of the known phrases renders as the card, both when it arrives live and when the chat is reopened; a reply still streaming renders as plain text unless it is exactly a known auth-error message, and one with no known phrase renders as plain text.
- [ ] After **Log in & reload**, the card stays a card while the reload re-streams the agent's history, rather than reverting to plain text until the next message.
- [ ] **Reload only** reloads the agent through `paseo agent reload`; the card moves through reloading to "Reloaded — send your message again", and the conversation survives.
- [x] **Log in & reload** runs `claude auth login` on the host (browser opens on the host), and after the login finishes the card reaches done without any shell step.
- [x] Two cards that start a login at the same time share one `claude auth login` process.
- [x] A login that exits non-zero, or is still running after 5 minutes, leaves the card failed at the login step with the error; the first URL the login printed, if any, shows as an "Open login page" link.
- [x] A failed reload, including an unknown agent id or a missing `paseo` binary, leaves the card failed at the reload step with the error.
- [ ] A card opened on a second device while a job is running shows the in-flight phase and follows it to the end.
- [x] The flake's `paseo-plugin-claude-reauth-typecheck`, `paseo-plugin-claude-reauth-sdk-version` and `paseo-plugin-requirements` checks pass.

## Constraints

- No RPC waits on the login or the reload: plugin RPCs time out at 30 s, so both run as daemon-side jobs that the card polls (`start` / `status`, shapes in the spec's Contracts section).
- The plugin only automates the documented workaround — no re-sending the failed message, no persisted state, no other providers (spec Non-goals).
- Stopping or reloading the plugin kills any running login or reload child.

## Notes

- Reproduce on demand with `claude auth logout` on the host, then message a live Claude agent.

## Progress

Plugin implemented and landed. The server job runner was exercised against fake `claude`/`paseo` CLIs: reload ok/unknown agent, shared login (one process for two agents), login failure with URL, a URL split across writes, stop, login timeout, and a missing binary. The four unchecked criteria need the real app on a host after a home-manager switch; tick them once verified, then complete the bean.

Deviations from the spec:
- Children are spawned in their own process group and killed as a group, not via the SDK's `terminateProcess`, which only signals the direct child on POSIX.
- The detector also caps the message at 500 chars, so a reply that merely quotes a phrase stays plain text.
- `agentId` is validated as a GUID, since it reaches `paseo agent reload`'s argv.
