---
# dotfiles-s76n
title: Scheduled GitHub Action to archive completed beans
status: todo
type: feature
created_at: 2026-05-31T19:21:06Z
updated_at: 2026-05-31T19:21:06Z
---

Add a scheduled GitHub Actions workflow that periodically archives completed (and scrapped) beans by running `beans archive`, then commits and pushes the resulting changes.

## Motivation

Completed and scrapped beans accumulate in the working set over time. The `beans archive` command moves them out, but it currently has to be run manually. A scheduled action would keep the active bean set tidy without manual intervention.

## Todo

- [ ] Decide on a schedule (e.g. daily/weekly cron) and whether to also allow manual `workflow_dispatch` triggering
- [ ] Add a GitHub Actions workflow that installs/provides the `beans` CLI in CI
- [ ] Run `beans archive` in the workflow
- [ ] Commit and push any resulting changes (archived bean files) back to the repo, with an appropriate commit message and author
- [ ] Handle the no-op case (no beans to archive) so the workflow doesn't fail or create empty commits
- [ ] Ensure the workflow has the permissions needed to push to the repo

## Open Questions

- How is the `beans` binary made available in CI — built from `crates/` via Nix, or installed some other way?
- What commit area/message convention should the automated commit use (e.g. `beans: archive completed beans`)?
