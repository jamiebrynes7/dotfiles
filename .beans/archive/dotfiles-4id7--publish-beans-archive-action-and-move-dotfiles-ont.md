---
# dotfiles-4id7
title: Publish beans-archive-action and move dotfiles onto it
status: completed
type: task
priority: normal
created_at: 2026-11-06T17:27:58Z
updated_at: 2026-11-06T17:59:07Z
---

**Spec:** `docs/specs/2026-11-06-beans-archive-action.md`: all sections, except adopting the action in `nimbus`, which is tracked in that repo

## What to build

A public `jamiebrynes7/beans-archive-action` repo holds a composite action that archives completed and scrapped beans through a PR, and `dotfiles`' weekly archive job calls it instead of carrying that logic itself.

## Acceptance criteria

- [x] `jamiebrynes7/beans-archive-action` is public, with an open-source license and a README covering the inputs and the token requirement
- [x] The action takes the `token`, `auto-merge` and `merge-method` inputs, with the spec's required status and defaults
- [x] Third-party actions and the `dotfiles` flake reference inside the action are pinned by full commit SHA
- [x] `dotfiles`' archive workflow keeps its cron and manual trigger, generates the poppet bot token, and calls the action by full commit SHA, with no archive logic of its own
- [x] A manual run with beans to archive opens a PR from `beans/archive`, which merges by rebase after `flake-check` passes
- [x] A manual run with nothing to archive opens no PR and passes

## Notes

Creating the public repo needs the user's confirmation at implementation time; the spec's approval settled the design, not that action.

The local `nimbus` clone had unrelated uncommitted work on a feature branch on 2026-11-06. File the bean without disturbing that work, on its own branch from `main`.

The spec must be on `dotfiles` master before the `nimbus` bean links to it.

Completed beans accumulate between weekly runs, so the merge test should normally have real beans to archive. If none exist, ask the user rather than creating a throwaway bean; that question was left unanswered at breakdown review.

## Summary of Changes

Published `jamiebrynes7/beans-archive-action` (MIT) and moved `dotfiles`' weekly job onto it at `510470a`, with the job reduced to `contents: read`. The action always archives the default branch, so a manual run from another branch can't push that branch's commits into an open archive PR.

Filing the `nimbus` adoption bean was dropped from this ticket at the user's request and still needs doing in that repo.

Verified with manual runs from the task branch:

- With beans to archive: #439 opened from `beans/archive`, passed `flake-check` and rebase-merged, moving 16 beans.
- With nothing to archive: no PR, and the job passed.

A run that started before #439 merged and finished after it opened #440, which had no changes against `master`, so it was closed. Re-running while an archive PR stays open, including re-enabling auto-merge, was not exercised because #439 merged too quickly.
