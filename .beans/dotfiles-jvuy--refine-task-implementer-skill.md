---
# dotfiles-jvuy
title: Refine task implementer skill
status: completed
type: task
priority: normal
created_at: 2026-06-06T17:32:09Z
updated_at: 2026-06-06T17:50:25Z
---

Changes:

1. A epic/feature/task each get a branch, as appropriate (e.g. - a feature may have multiple tasks that logically belong on a branch).
2. Once done, open a PR back into `master`.
3. Enable auto-merge once checks pass & wait for it to merge using gh CLI
4. Once merged, switch back to master and `git fomo`, then delete the feature branch

## Summary of Changes

Refined the `task-implementer` skill to land work through a branch + PR + auto-merge flow:

- **Step 3 (new) — Branch**: implement on a dedicated `<type>/<slug>` branch; sibling tasks under a shared parent reuse the parent's `<parent-type>/<parent-slug>` branch.
- **Steps 4–7 renumbered** (Implement / Subagent review / User review / Mark done & commit). Commit is now made on the branch.
- **Step 8 (new) — Open a PR and land it**: push, open a PR into `master` with a real title/body (incl. the Claude Code trailer and a `Follow-ups:` line), enable auto-merge via `gh pr merge --auto --rebase --delete-branch`, wait on `gh pr checks --watch`, then return to `master`, `git fomo`, and `git branch -D` the branch.
- CI-failure path loops back to the Implement step (re-review if non-trivial) and prefers amending commits over stacking fix commits.

Merge strategy is **rebase** (per user direction). Notable correctness fixes from review: `git branch -D` (not `-d`) since rebase/squash replays commits with new SHAs; explicit PR body instead of `--fill` to preserve the trailer convention; `--watch` non-zero exit is handled as 'fix and retry', not abort.
