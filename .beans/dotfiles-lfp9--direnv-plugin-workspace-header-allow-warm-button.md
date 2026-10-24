---
# dotfiles-lfp9
title: 'direnv plugin: workspace header Allow / Warm button'
status: in-progress
type: task
priority: normal
created_at: 2026-10-18T16:07:54Z
updated_at: 2026-10-24T15:35:50Z
parent: dotfiles-jf3q
blocked_by:
    - dotfiles-e2gj
---

**Spec:** `docs/specs/2026-10-18-paseo-direnv-plugin.md` — Client half: the header button

## What to build

Every workspace's header gets a `direnv` menu button with two items, each opening a visible workspace terminal in the workspace directory (the worktree directory for worktrees): **Allow** runs `direnv allow`, and **Warm** runs `direnv exec . true` with no time limit, so a slow `.envrc` (e.g. a cold nix devshell) is cached before the next launch. The launch hook's refusal messages point at these items.

## Acceptance criteria

- [ ] Every workspace header shows a `direnv` menu button with Allow and Warm items, including workspaces created after the client loaded, and the button goes away when its workspace does
- [ ] Allow opens a terminal in the workspace directory running `direnv allow` with no confirmation step. Demo: in a new worktree an agent create is refused as blocked, then Allow, then retry succeeds
- [ ] Warm opens a terminal in the workspace directory running `direnv exec . true` with its output visible. Demo: a slow `.envrc` is refused on timeout, then Warm, then retry succeeds
- [ ] Failing to open the terminal surfaces as paseo's error toast
- [x] The blocked and timeout refusal messages from the launch hook name the Allow and Warm items respectively
- [x] The plugin's typecheck flake check covers the client half and passes

## Constraints

- No server RPC: the client half never calls the daemon half, so the button needs only `workspace.write`, not `daemon.manage`
- No per-workspace `.envrc` detection: the button shows in every workspace

## Progress

Code landed (PR to follow); the four in-app criteria (button lifecycle, Allow then retry, Warm then retry, error toast) are still to verify once this is applied on a host. Verified so far: both halves typecheck, `nix flake check` is green, and the `sh` wrapper keeps direnv's output and exit status on screen for both a blocked and an allowed `.envrc`.

From review against paseo 0.12.0: the daemon removes a terminal as soon as its process exits, so each item runs direnv under `sh`, prints its exit status, and hands over to an interactive shell. The app adds plugin-opened terminals without focusing them, so the user picks the `direnv allow` / `direnv warm` tab. A failed re-subscribe after a reconnect is retried rather than stopping observation, and the plugin now requires paseo >= 0.12.0, the client SDK it is typed against.
