---
# dotfiles-23hw
title: 'direnv plugin: allow new worktrees of allowed projects'
status: todo
type: task
created_at: 2026-10-19T07:20:54Z
updated_at: 2026-10-19T07:20:54Z
parent: dotfiles-jf3q
---

**Spec:** `docs/specs/2026-10-19-paseo-direnv-worktree-allow.md` — Trust rule; Design. (Supersedes the trust non-goal of `docs/specs/2026-10-18-paseo-direnv-plugin.md`.)

## What to build

When paseo creates a worktree workspace of a project whose root checkout's `.envrc` is already allowed, the `direnv` plugin runs `direnv allow` on the new worktree, so agents launched there get the devshell with no manual step. The `agent.session_open` hook waits for that allow, so even the first agent of a freshly created workspace never races it.

## Acceptance criteria

- [ ] `paseo workspace create --isolation worktree` on a repo with an allowed root `.envrc`, immediately followed by `paseo run --workspace <id>`, launches the agent with the devshell environment and no refusal
- [ ] `paseo run --new-workspace worktree` on the same repo launches its first agent with the devshell environment
- [ ] A worktree of a repo whose root `.envrc` is not allowed (or was edited and not re-allowed) is not allowed, and its create is refused as blocked, as before
- [ ] Local (non-worktree) workspaces, and worktrees with no `.envrc`, get no allow attempt
- [ ] Every skip or failure in the allow path is logged with directories only and leaves the worktree as it was; nothing throws back to paseo
- [ ] The plugin's typecheck and sdk-version flake checks pass, and `nix flake check` is green

## Constraints

- The allow is only ever triggered by `workspace.created`, never by an agent open
- The root check compares `direnv status --json`'s `foundRC.path` to `<source>/.envrc`, so a parent directory's `.envrc` never counts as the project's
- Worktrees root honours `worktrees.root` in `$PASEO_HOME/config.json`, defaulting to `$PASEO_HOME/worktrees`
- No configuration, no warming, no revoking (see the spec's non-goals)
