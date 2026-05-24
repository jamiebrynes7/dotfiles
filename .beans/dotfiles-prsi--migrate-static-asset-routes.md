---
# dotfiles-prsi
title: Migrate static asset routes
status: todo
type: feature
created_at: 2026-05-24T15:05:58Z
updated_at: 2026-05-24T15:05:58Z
parent: dotfiles-n7to
---

Owns `crates/beansd/src/web/routes/assets.rs`: the `/static/htmx.min.js` and `/static/app.css` handlers, the two `include_*!` consts, and the 2 colocated tests. Paths in the `include_*!` macros are `../static/...` (relative to the file at `src/web/routes/assets.rs`).
