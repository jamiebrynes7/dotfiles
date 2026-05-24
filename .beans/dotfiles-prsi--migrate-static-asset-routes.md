---
# dotfiles-prsi
title: Migrate static asset routes
status: completed
type: feature
priority: normal
created_at: 2026-05-24T15:05:58Z
updated_at: 2026-05-24T18:19:33Z
parent: dotfiles-n7to
---

Owns `crates/beansd/src/web/routes/assets.rs`: the `/static/htmx.min.js` and `/static/app.css` handlers, the two `include_*!` consts, and the 2 colocated tests. Paths in the `include_*!` macros are `../static/...` (relative to the file at `src/web/routes/assets.rs`).

## Tasks

- [x] Add `pub(in crate::web) mod test_utils;` (cfg(test)) to `web/mod.rs`
- [x] Create `web/test_utils.rs` with `build_state` / `empty_state` helpers returning `State`
- [x] Fill in `web/routes/assets.rs` with HTMX_JS/APP_CSS consts, serve_htmx/serve_css handlers, router, and the 2 colocated tests
- [x] `cargo test -p beansd` — both new assets tests + the 8 launcher tests (still parallel copies) pass

## Summary of Changes

Filled `web/routes/assets.rs` with the real `/static/htmx.min.js` and `/static/app.css` handlers + `include_*!` consts (paths `../static/...` relative to the file) + colocated tests. `launcher.rs` is untouched and still serves the same routes — both copies coexist until `dotfiles-th98` deletes the launcher.

Also introduced `crates/beansd/src/web/test_utils.rs` (gated on `#[cfg(test)]`, `pub(in crate::web)`) hosting `build_state` / `empty_state` so the upcoming `dotfiles-tlhu` (html) and `dotfiles-p6a4` (api) migrations can reuse them without duplication. Per the spec's "if more than one file needs them, lift to a `pub(super) mod test_utils`" guidance, but scoped `pub(in crate::web)` for tighter visibility.

`cargo test -p beansd` → 54 passed (52 + 2 new `web::routes::assets` tests). Build clean apart from the two pre-existing unrelated warnings (`Config::heartbeat_secs`, `ProjectState::Dead::reason`).
