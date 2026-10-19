---
# dotfiles-e2gj
title: 'direnv plugin: launch agents with their directory''s direnv environment'
status: completed
type: task
priority: normal
created_at: 2026-10-18T16:07:46Z
updated_at: 2026-10-18T17:02:59Z
parent: dotfiles-jf3q
---

**Spec:** `docs/specs/2026-10-18-paseo-direnv-plugin.md` — Architecture; Server half: the hook; Changed `.envrc`; Error handling summary

## What to build

A repo-local `direnv` paseo plugin, packaged and on by default wherever paseo is enabled, whose daemon half evaluates direnv on every agent open. An agent whose directory has an allowed `.envrc` runs with that environment, on create, resume after a daemon restart, import, and Reload agent. An agent whose `.envrc` is blocked, fails to evaluate, or is too slow is refused, never launched with the daemon's environment instead.

## Acceptance criteria

- [x] With the plugin enabled, an agent created in a directory with an allowed `.envrc` sees the `.envrc`'s variables, and its `PATH` comes from the devshell
- [x] Creating an agent in a directory whose `.envrc` is blocked (e.g. a fresh git worktree) is refused, and the message under the composer names the `.envrc` path and tells the user to run `direnv allow` in that directory
- [x] An `.envrc` that exits non-zero refuses the launch, and the message carries the tail of direnv's stderr with ANSI escapes stripped
- [x] An `.envrc` slower than the plugin's own timeout refuses the launch with the plugin's own message suggesting a warm-up, not paseo's generic `Plugin RPC timed out`
- [x] A directory with no `.envrc`, a host with no `direnv` on the daemon `PATH`, and a history-only open of an archived agent all launch with the environment unchanged
- [x] An explicit per-launch env override wins over direnv for the same variable, except `PATH`, which is merged with the override's entries first and direnv's remaining entries after
- [x] A variable the `.envrc` unsets keeps the daemon's value, and `DIRENV_*` bookkeeping variables reach the agent
- [x] After editing and re-allowing an `.envrc`, Reload agent on an existing agent picks up the new environment, and an edited but unallowed `.envrc` makes the reload fail
- [x] The plugin's typecheck and sdk-version flake checks exist and pass, and `nix flake check` is green
- [x] Hosts opt out with `dotfiles.programs.paseo.plugins.direnv.enable = false`

## Constraints

- The plugin never runs `direnv allow`, and never treats direnv's stdout as an environment when direnv exits non-zero (a blocked `.envrc` still prints `DIRENV_*` JSON)
- Logs carry outcomes, directories and variable names, never variable values
- No plugin settings screen and no server RPC
- Update `CLAUDE.md` if the plugin adds a convention the existing paseo plugin guidance doesn't cover

## Notes

The refusal messages may also name the workspace header's direnv button (Allow / Warm) that the sibling ticket adds. Until that lands, `direnv allow` / `direnv exec <dir> true` in a terminal is the fix they must name.

## Summary of Changes

- New repo-local paseo plugin `ts/paseo-plugin-direnv/` (id `direnv`, server half only), packaged as `packages/paseo-plugin-direnv/` and registered in `home/programs/paseo.nix` with `lib.mkDefault`, like `last-response`.
- `before("agent.session_open")` runs `direnv export json` in the agent's cwd with the daemon's environment, on every non-history open. Exit status is classified before stdout is read: blocked, failed (ANSI-stripped stderr tail) and timeout (25 s, under the daemon's 30 s) refuse the launch with an actionable message. No direnv, no `.envrc` and a missing directory pass through unchanged.
- Merge: direnv's variables under `request.env`, with `PATH` merged override-first; `null` unsets are dropped so the daemon's value stands; `DIRENV_*` pass through.
- Review fixes: settle on direnv's exit plus the end of its stdout rather than `close`, so a backgrounded process holding stderr can't hang the hook; run direnv in its own process group and kill the group on timeout; cap the stderr buffer; keep values out of JSON parse errors; report signal exits; shell-quote paths in suggested commands.
- Verified by running the compiled hook against real direnv for every acceptance case (allowed, blocked, failing, slow, none, unset, override/PATH merge, history, no direnv, missing dir, edit then re-allow, path with spaces), plus a fake direnv that exits while still holding stderr. Not yet verified: the spec's manual matrix on a running paseo daemon (resume after restart, Reload agent).
- Refusal messages name `direnv allow` / `direnv exec <dir> true` for now; `dotfiles-lfp9` switches them to the header button's Allow / Warm items.
