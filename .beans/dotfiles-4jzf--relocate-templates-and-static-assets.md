---
# dotfiles-4jzf
title: Relocate templates and static assets
status: todo
type: feature
created_at: 2026-05-24T15:05:46Z
updated_at: 2026-05-24T15:05:46Z
parent: dotfiles-n7to
---

Owns the file move from `crates/beansd/templates/` → `crates/beansd/src/web/templates/` and `crates/beansd/static/` → `crates/beansd/src/web/static/`, plus the new `crates/beansd/askama.toml` that points askama at the relocated templates. Foundation for the refactor — every other feature assumes assets live under `src/web/`.
