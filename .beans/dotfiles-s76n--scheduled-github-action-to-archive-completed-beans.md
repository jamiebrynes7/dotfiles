---
# dotfiles-s76n
title: Scheduled GitHub Action to archive completed beans
status: completed
type: feature
priority: normal
created_at: 2026-05-31T19:21:06Z
updated_at: 2026-06-01T17:09:22Z
---

Add a scheduled GitHub Actions workflow that periodically archives completed (and scrapped) beans by running `beans archive`, then commits and pushes the resulting changes.

## Motivation

Completed and scrapped beans accumulate in the working set over time. The `beans archive` command moves them out, but it currently has to be run manually. A scheduled action would keep the active bean set tidy without manual intervention.

## Todo

- [x] Decide on a schedule (e.g. daily/weekly cron) and whether to also allow manual `workflow_dispatch` triggering
- [x] Add a GitHub Actions workflow that installs/provides the `beans` CLI in CI
- [x] Run `beans archive` in the workflow
- [x] Commit and push any resulting changes (archived bean files) back to the repo, with an appropriate commit message and author
- [x] Handle the no-op case (no beans to archive) so the workflow doesn't fail or create empty commits
- [x] Ensure the workflow has the permissions needed to push to the repo

## Open Questions

- How is the `beans` binary made available in CI — built from `crates/` via Nix, or installed some other way?
- What commit area/message convention should the automated commit use (e.g. `beans: archive completed beans`)?

## Summary of Changes

Added `.github/workflows/archive-beans.yml`, a scheduled + manually-dispatchable workflow that archives completed/scrapped beans.

- **Trigger:** weekly cron (Mondays 05:00 UTC) plus `workflow_dispatch`.
- **beans CLI:** built from this repo's flake and run via `nix run .#beans -- archive` (no external install).
- **Land strategy:** mirrors `auto-update.yml` — POPPET_BOT GitHub App token, then `peter-evans/create-pull-request` + `gh pr merge --auto --rebase`. PR title/commit: `beans: archive completed beans`.
- **No-op handling:** gated on `git status --porcelain -- .beans` (not `git diff --quiet`) because `beans archive` *moves* files — the new `.beans/archive/` files are untracked, which `git diff` would miss.
- **Permissions:** `contents: write` + `pull-requests: write`.

Verified end-to-end via a manual `workflow_dispatch` run: it archived 21 beans, opened PR #173 with auto-merge, `flake-check` passed, and the PR merged.
