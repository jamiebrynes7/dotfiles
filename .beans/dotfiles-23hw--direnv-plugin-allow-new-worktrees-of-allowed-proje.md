---
# dotfiles-23hw
title: 'direnv plugin: allow new worktrees of allowed projects'
status: in-progress
type: task
priority: normal
created_at: 2026-10-19T07:20:54Z
updated_at: 2026-10-19T07:56:16Z
parent: dotfiles-jf3q
---

**Spec:** `docs/specs/2026-10-19-paseo-direnv-worktree-allow.md` — Trust rule; Design. (Supersedes the trust non-goal of `docs/specs/2026-10-18-paseo-direnv-plugin.md`.)

## What to build

When paseo creates a worktree workspace of a project whose root checkout's `.envrc` is already allowed, the `direnv` plugin runs `direnv allow` on the new worktree, so agents launched there get the devshell with no manual step. The `agent.session_open` hook waits for that allow, so even the first agent of a freshly created workspace never races it.

## Acceptance criteria

- [ ] `paseo workspace create --isolation worktree` on a repo with an allowed root `.envrc`, immediately followed by `paseo run --workspace <id>`, launches the agent with the devshell environment and no refusal
- [ ] `paseo run --new-workspace worktree` on the same repo launches its first agent with the devshell environment
- [x] A worktree of a repo whose root `.envrc` is not allowed (or was edited and not re-allowed) is not allowed, and its create is refused as blocked, as before
- [x] Local (non-worktree) workspaces, and worktrees with no `.envrc`, get no allow attempt
- [x] Every skip or failure in the allow path is logged with directories only and leaves the worktree as it was; nothing throws back to paseo
- [x] The plugin's typecheck and sdk-version flake checks pass, and `nix flake check` is green

## Constraints

- The allow is only ever triggered by `workspace.created`, never by an agent open
- The root check compares `direnv status --json`'s `foundRC.path` to `<source>/.envrc`, so a parent directory's `.envrc` never counts as the project's
- Worktrees root honours `worktrees.root` in `$PASEO_HOME/config.json`, defaulting to `$PASEO_HOME/worktrees`
- No configuration, no warming, no revoking (see the spec's non-goals)

## Progress

Code landed (PR to follow); the two live-daemon criteria (create-then-run, `--new-workspace`) are still to verify once this is applied on a host. Verified so far with a harness of real `git worktree add` worktrees under a fake `PASEO_HOME`, firing `workspace.created` then `agent.session_open` without waiting: allowed project, agent in a subdirectory, custom `worktrees.root`, not-allowed project, local workspace, parent-only `.envrc`, stale worktree, uncommitted or ignored `.envrc`, and an already-aborted open.

Beyond the spec, from review: `workspace.created` also fires for local workspaces opened on existing worktrees and for agent-minted workspaces, so the allow additionally requires the worktree's `.git` to be under 2 minutes old and its `.envrc` to be tracked and unchanged from `HEAD`. This keeps an edited `.envrc` refused rather than re-approved.
