---
# dotfiles-ki8f
title: Load a repository's skills into Paseo Claude agents created in it
status: completed
type: task
priority: normal
created_at: 2026-11-04T15:36:09Z
updated_at: 2026-11-06T11:11:28Z
parent: dotfiles-l44k
blocked_by:
    - dotfiles-v7fb
---

**Spec:** `docs/specs/2026-11-04-paseo-repo-skills.md` — Upstream facts, Repository matching, The Paseo plugin (Server half, except warning rows), Error handling, Testing seams

## What to build

A new repo-local Paseo plugin, `repo-skills`, that the Paseo module enables whenever `repoSkills` is non-empty. When a Claude agent is created through Paseo in a checkout or worktree of a declared repository, its `agent.create.before` hook sets `providerOptions.extraArgs["plugin-dir"]` to that repository's stable plugin link, so the agent starts with that repository's skills. Agents anywhere else, and non-Claude agents, are untouched. Failures are made safe and logged here; making them visible in chat is the next ticket.

## Acceptance criteria

- [x] (Moved to dotfiles-1p9i, which runs the end-to-end pass together with its warning rows.) Manual end-to-end: a Claude agent created through Paseo in a worktree of a declared repository lists that repository's skills as `<owner>-<repo>:<skill>`. This confirms the Agent SDK passes `--plugin-dir` through. An agent created in an undeclared repository lists none of them.
- [x] A Codex agent created in a declared repository is created with its request unchanged.
- [x] SSH (`git@host:o/r.git`, `ssh://git@host/o/r`) and HTTPS (`https://host/o/r`, with or without `.git` or a trailing `/`) remotes all normalise to the same key, with the host lowercased; covered by `node:test` unit tests that run as a flake check.
- [x] A repository whose `origin` is a personal fork but whose `upstream` remote is the declared repository matches.
- [x] When remotes match several keys, the first match in remote order is used and the others are named in the daemon log.
- [x] Each failure in the spec's error-handling table (config file missing or invalid, `git` failing, plugin folder missing) leaves the agent created with its request unchanged and logs the reason. A `cwd` outside any git repository, or with no matching remote, is silent.
- [x] An agent whose `extraArgs["plugin-dir"]` is already set keeps that value, and the skip is logged.
- [x] A `git` call that hangs is cut off by the plugin's own timeout. Agent creation still succeeds well inside Paseo's 30-second hook limit.
- [x] Other `providerOptions` keys and `extraArgs` entries on the request are preserved.

## Constraints

- Registers hooks only through `server.addHook` with 0.15.0 names, not the deprecated `server.before`/`server.on` registrations.
- Agent creation never fails because of this plugin.
- Follows the repo's existing Paseo plugin packaging conventions (root `CLAUDE.md`, "Packages"), so the existing typecheck and SDK-version checks cover it.

## Notes from dotfiles-v7fb

- Keys are validated in `home/lib/paseo-repo-skills/default.nix` as `[a-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+` with no trailing `.git`: exactly three segments, owner/repo case preserved. The TS normaliser must agree. Decide how it treats owner/repo case (GitHub is case-insensitive, so `Acme/Web` declared against an `acme/web` remote won't match an exact compare), and what it does with more than three path segments (GitLab subgroups), which the key rule rejects.

## Summary of Changes

- New repo-local Paseo plugin `ts/paseo-plugin-repo-skills/` (id `repo-skills`, server-only, `requirements.paseo >=0.15.0`), packaged as `packages/paseo-plugin-repo-skills` over `buildPaseoPlugin`. `home/programs/paseo.nix` enables it whenever `repoSkills` is non-empty.
- Its `agent.create.before` hook (`addHook` only) sets `providerOptions.extraArgs["plugin-dir"]` for `claude` agents whose repository has a remote matching a key in `config.json`. Every other key is preserved. Any failure returns the request unchanged and is logged.
- `server/remote-url.ts` normalises SSH, scp-like and HTTPS URLs to `host/owner/repo`. Matching is case-insensitive, and subgroup paths never match. `server/git.ts` reads remotes in config order with `git config --local --includes`, so worktrees and forks with an `upstream` remote match. It gets a 5 s timeout per call, honours the hook's signal, and strips `GIT_*`. Only git's "not a git repository (or any…)" is silent; a broken worktree link or dubious ownership is logged. `server/resolve.ts` is the pure decision; it lists remotes before reading the config, so an agent outside any git repo stays silent.
- `ts/default.nix`: `typecheck` became `npmScriptCheck`, which also gives any plugin with a `test` script a `<dir>-test` check. The new plugin has 26 `node:test` cases, run on Node 24 type stripping with git available.
- I verified in the bundled Agent SDK (0.3.246) that `extraArgs` entries become `--<key> <value>`. The live end-to-end check moves to dotfiles-1p9i.
