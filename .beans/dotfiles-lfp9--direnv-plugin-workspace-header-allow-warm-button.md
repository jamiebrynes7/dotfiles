---
# dotfiles-lfp9
title: 'direnv plugin: workspace header Allow / Warm button'
status: todo
type: task
priority: normal
created_at: 2026-10-18T16:07:54Z
updated_at: 2026-10-18T16:07:54Z
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
- [ ] The blocked and timeout refusal messages from the launch hook name the Allow and Warm items respectively
- [ ] The plugin's typecheck flake check covers the client half and passes

## Constraints

- No server RPC: the client half never calls the daemon half, so the button needs only `workspace.write`, not `daemon.manage`
- No per-workspace `.envrc` detection: the button shows in every workspace
