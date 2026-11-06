---
# dotfiles-3gsq
title: Close superseded nightly package-update PRs
status: completed
type: task
priority: normal
created_at: 2026-11-04T14:59:48Z
updated_at: 2026-11-04T15:00:21Z
---

auto-update.yml opens a new timestamped PR each night without closing the previous one, so unmerged (usually red) PRs pile up. After opening a new PR, close older open update-packages-* PRs with a 'superseded by' comment and delete their branches.

- [x] Add close-superseded step to .github/workflows/auto-update.yml

## Summary of Changes

Added a 'Close superseded pull requests' step to auto-update.yml. After a new update PR is created, it closes every other open update-packages-* PR with a 'Superseded by #N.' comment and deletes its branch.
