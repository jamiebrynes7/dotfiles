---
# dotfiles-zfye
title: 'claude-reauth: gray out spent cards and resend the failed message'
status: in-progress
type: task
priority: normal
created_at: 2026-10-26T10:55:08Z
updated_at: 2026-10-26T12:24:54Z
---

**Spec:** `docs/specs/2026-10-26-paseo-claude-reauth-resend.md` — whole spec

## What to build

After a successful reload, the daemon half resends the user's failed message itself, but only when the agent's timeline ends with that user message followed directly by the auth-error reply. The card then shows a resending step and finishes as "Reloaded and resent your message" or "Reloaded — send your message again". Once a recovery has finished, every card for that agent from before it finished is spent: its buttons are grayed out and can't be pressed. A newer auth error, such as the resent message failing again, still gets a card with working buttons.

## Acceptance criteria

- [x] `RecoveryState` gains a `resending` phase. `done` carries `at` (ISO time) and `resent: boolean`, and `failed.step` admits `"resend"`, matching the spec's Contracts shape. `resending` counts as running for `start` (no-op) and for card polling.
- [x] Both **Log in & reload** and **Reload only** go reload → resending → done.
- [x] With the timeline ending in a user message followed directly by the auth error, the message's text is sent once, unchanged, and the card reads "Reloaded and resent your message".
- [x] With anything else at the timeline tail, the resend is skipped and the card reads "Reloaded — send your message again". That covers a message sent by hand before pressing the button, and tool calls or reasoning between the message and the error.
- [x] A refetch or send error ends in `failed` with `step: "resend"`. The card shows "Reloaded, but resending failed: <error> — send your message again", the buttons come back on, and the resend is not retried.
- [x] A card whose timestamp is earlier than the agent's `lastDoneAt` (its latest successful recovery) renders with both buttons disabled and grayed out, on every device. It stays gray while a later run is going and after that run fails. A card newer than `lastDoneAt` keeps working buttons, and a `done` or `failed` that ended before the card appeared reads as idle on it.
- [x] `nix flake check` passes, including `paseo-plugin-claude-reauth-typecheck`.
- [ ] Manual verification on a host passes the spec's Testing seams list (`claude auth logout`, then message a live agent).

## Constraints

- Recovery state stays in memory only. After a daemon restart, old cards read `idle` and can be pressed again, as the spec accepts.
- The resend rule uses the same shared detector as the card's transformer, not a second copy of the auth-error phrases.
- Plugin RPCs still answer at once. The resend runs inside the background recovery job, never inside an RPC handler.

## Notes

- Verified at paseo 0.13.0: RPC handlers get `paseo: PaseoApi`; `agents.ref(id).send(text)` and `.timeline.refetch({ direction: "tail", limit })` exist; `user_message` timeline items carry text only. Plugins still have no agent-reload call, so the reload stays on `paseo agent reload`.
- Follows dotfiles-42qz, which built the plugin.

## Progress

Implemented. Typecheck and the plugin's flake checks pass. A scratch harness with fake `claude`/`paseo` CLIs and a fake paseo API covered the resend rule (resend, `[System Error]` prefix, user moved on, tool call between, empty tail, error only), refetch, send and reload failures, login then resend, the cutoff taken before sending, stop mid-refetch, and `lastDoneAt` surviving a later failed run. The remaining criterion needs the real app on a host after a home-manager switch; tick it, then complete the bean.

Deviations from the spec, folded into it before landing:
- `start`/`status` return `{ state, lastDoneAt? }`, and `failed` carries `at`, so an old card stays spent through later runs and a card never shows an earlier run's result (user's choice after review).
- `done.at` is taken before the send, since the reply to a resent message can be timestamped before `send` resolves.

Things to check on the host: a spent card on a second device updates without reopening the chat; whether the `[System Error]` form ever gets resent after a reload (it fails safe to 'send your message again').
