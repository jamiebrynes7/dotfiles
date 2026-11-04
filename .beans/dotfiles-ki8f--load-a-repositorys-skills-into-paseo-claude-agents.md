---
# dotfiles-ki8f
title: Load a repository's skills into Paseo Claude agents created in it
status: todo
type: task
priority: normal
created_at: 2026-11-04T15:36:09Z
updated_at: 2026-11-04T18:20:58Z
parent: dotfiles-l44k
blocked_by:
    - dotfiles-v7fb
---

**Spec:** `docs/specs/2026-11-04-paseo-repo-skills.md` — Upstream facts, Repository matching, The Paseo plugin (Server half, except warning rows), Error handling, Testing seams

## What to build

A new repo-local Paseo plugin, `repo-skills`, that the Paseo module enables whenever `repoSkills` is non-empty. When a Claude agent is created through Paseo in a checkout or worktree of a declared repository, its `agent.create.before` hook sets `providerOptions.extraArgs["plugin-dir"]` to that repository's stable plugin link, so the agent starts with that repository's skills. Agents anywhere else, and non-Claude agents, are untouched. Failures are made safe and logged here; making them visible in chat is the next ticket.

## Acceptance criteria

- [ ] Manual end-to-end: a Claude agent created through Paseo in a worktree of a declared repository lists that repository's skills as `<owner>-<repo>:<skill>`. This confirms the Agent SDK passes `--plugin-dir` through. An agent created in an undeclared repository lists none of them.
- [ ] A Codex agent created in a declared repository is created with its request unchanged.
- [ ] SSH (`git@host:o/r.git`, `ssh://git@host/o/r`) and HTTPS (`https://host/o/r`, with or without `.git` or a trailing `/`) remotes all normalise to the same key, with the host lowercased; covered by `node:test` unit tests that run as a flake check.
- [ ] A repository whose `origin` is a personal fork but whose `upstream` remote is the declared repository matches.
- [ ] When remotes match several keys, the first match in remote order is used and the others are named in the daemon log.
- [ ] Each failure in the spec's error-handling table (config file missing or invalid, `git` failing, plugin folder missing) leaves the agent created with its request unchanged and logs the reason. A `cwd` outside any git repository, or with no matching remote, is silent.
- [ ] An agent whose `extraArgs["plugin-dir"]` is already set keeps that value, and the skip is logged.
- [ ] A `git` call that hangs is cut off by the plugin's own timeout. Agent creation still succeeds well inside Paseo's 30-second hook limit.
- [ ] Other `providerOptions` keys and `extraArgs` entries on the request are preserved.

## Constraints

- Registers hooks only through `server.addHook` with 0.15.0 names, not the deprecated `server.before`/`server.on` registrations.
- Agent creation never fails because of this plugin.
- Follows the repo's existing Paseo plugin packaging conventions (root `CLAUDE.md`, "Packages"), so the existing typecheck and SDK-version checks cover it.

## Notes from dotfiles-v7fb

- Keys are validated in `home/lib/paseo-repo-skills/default.nix` as `[a-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+` with no trailing `.git`: exactly three segments, owner/repo case preserved. The TS normaliser must agree. Decide how it treats owner/repo case (GitHub is case-insensitive, so `Acme/Web` declared against an `acme/web` remote won't match an exact compare), and what it does with more than three path segments (GitLab subgroups), which the key rule rejects.
