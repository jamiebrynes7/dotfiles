---
# dotfiles-e2gj
title: 'direnv plugin: launch agents with their directory''s direnv environment'
status: todo
type: task
created_at: 2026-10-18T16:07:46Z
updated_at: 2026-10-18T16:07:46Z
parent: dotfiles-jf3q
---

**Spec:** `docs/specs/2026-10-18-paseo-direnv-plugin.md` — Architecture; Server half: the hook; Changed `.envrc`; Error handling summary

## What to build

A repo-local `direnv` paseo plugin, packaged and on by default wherever paseo is enabled, whose daemon half evaluates direnv on every agent open. An agent whose directory has an allowed `.envrc` runs with that environment, on create, resume after a daemon restart, import, and Reload agent. An agent whose `.envrc` is blocked, fails to evaluate, or is too slow is refused, never launched with the daemon's environment instead.

## Acceptance criteria

- [ ] With the plugin enabled, an agent created in a directory with an allowed `.envrc` sees the `.envrc`'s variables, and its `PATH` comes from the devshell
- [ ] Creating an agent in a directory whose `.envrc` is blocked (e.g. a fresh git worktree) is refused, and the message under the composer names the `.envrc` path and tells the user to run `direnv allow` in that directory
- [ ] An `.envrc` that exits non-zero refuses the launch, and the message carries the tail of direnv's stderr with ANSI escapes stripped
- [ ] An `.envrc` slower than the plugin's own timeout refuses the launch with the plugin's own message suggesting a warm-up, not paseo's generic `Plugin RPC timed out`
- [ ] A directory with no `.envrc`, a host with no `direnv` on the daemon `PATH`, and a history-only open of an archived agent all launch with the environment unchanged
- [ ] An explicit per-launch env override wins over direnv for the same variable, except `PATH`, which is merged with the override's entries first and direnv's remaining entries after
- [ ] A variable the `.envrc` unsets keeps the daemon's value, and `DIRENV_*` bookkeeping variables reach the agent
- [ ] After editing and re-allowing an `.envrc`, Reload agent on an existing agent picks up the new environment, and an edited but unallowed `.envrc` makes the reload fail
- [ ] The plugin's typecheck and sdk-version flake checks exist and pass, and `nix flake check` is green
- [ ] Hosts opt out with `dotfiles.programs.paseo.plugins.direnv.enable = false`

## Constraints

- The plugin never runs `direnv allow`, and never treats direnv's stdout as an environment when direnv exits non-zero (a blocked `.envrc` still prints `DIRENV_*` JSON)
- Logs carry outcomes, directories and variable names, never variable values
- No plugin settings screen and no server RPC
- Update `CLAUDE.md` if the plugin adds a convention the existing paseo plugin guidance doesn't cover

## Notes

The refusal messages may also name the workspace header's direnv button (Allow / Warm) that the sibling ticket adds. Until that lands, `direnv allow` / `direnv exec <dir> true` in a terminal is the fix they must name.
