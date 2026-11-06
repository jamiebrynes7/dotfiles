---
# dotfiles-dfl1
title: 'repo-skills: honour url.insteadOf when matching remotes'
status: todo
type: task
priority: low
created_at: 2026-11-06T11:11:28Z
updated_at: 2026-11-06T11:11:28Z
parent: dotfiles-l44k
---

`server/git.ts` reads raw `remote.*.url` values, so a remote written via an insteadOf alias (e.g. `gh:acme/web` with `[url \"git@github.com:\"] insteadOf = gh:`) normalises to `gh/acme/web` and silently never matches. Option: `git remote` then `git ls-remote --get-url <name>` per remote, budgeting the timeout. Deferred from the dotfiles-ki8f review (S2).
