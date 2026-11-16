---
# dotfiles-yq8u
title: 'Git: pick the commit email by remote URL'
status: completed
type: feature
priority: normal
created_at: 2026-11-13T13:54:32Z
updated_at: 2026-11-13T13:56:52Z
---

`dotfiles.programs.git.email` is a single global value, so a downstream layer that sets a different email for its own work also applies it to clones of personal repos.

Add a `dotfiles.programs.git.emailByRemote` option (remote URL glob → email), rendered as `includeIf "hasconfig:remote.*.url:<glob>"` blocks, so a layer can map personal remotes back to the personal email.

- [x] emailByRemote option in home/programs/git.nix
- [x] Exercised by the home-eval check
- [x] Verified with git on a scratch repo

## Summary of Changes

Added `dotfiles.programs.git.emailByRemote`, an attrset from a remote URL glob to an email, rendered as home-manager `programs.git.includes` entries with `hasconfig:remote.*.url:<glob>` conditions. The includes land after `[user]`, so a match overrides `email`. `checks/home-eval.nix` sets one entry so CI evaluates the option.

Verified against git 2.55 in scratch repos: SSH and HTTPS remotes matching their globs take the mapped email, while other remotes and repos without a remote keep `email`. SSH and HTTPS URLs need separate globs.
