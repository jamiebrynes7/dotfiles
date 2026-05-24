---
# dotfiles-4jzf
title: Relocate templates and static assets
status: completed
type: feature
priority: normal
created_at: 2026-05-24T15:05:46Z
updated_at: 2026-05-24T18:15:58Z
parent: dotfiles-n7to
---

Owns the file move from `crates/beansd/templates/` → `crates/beansd/src/web/templates/` and `crates/beansd/static/` → `crates/beansd/src/web/static/`, plus the new `crates/beansd/askama.toml` that points askama at the relocated templates. Foundation for the refactor — every other feature assumes assets live under `src/web/`.

## Summary of Changes

Templates and static assets now live under `crates/beansd/src/web/`, and `crates/beansd/askama.toml` points askama at the relocated templates. Subsequent features (`dotfiles-p6a4`, `dotfiles-tlhu`, `dotfiles-prsi`) can assume web assets are colocated with the new module tree.

Delivered via single child task `dotfiles-tlpb`.
