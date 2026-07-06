---
# dotfiles-ytfy
title: '[beansd] Add nice little favicon'
status: completed
type: task
priority: normal
created_at: 2026-06-16T09:29:25Z
updated_at: 2026-07-04T20:56:34Z
---

## Plan

Add a small SVG favicon to the beansd launcher web UI, matching the existing Catppuccin-themed static-asset pattern.

- [x] Add `static/favicon.svg` — a bean-themed icon in the UI palette
- [x] Serve it from `routes/assets.rs` at `/static/favicon.svg` with `image/svg+xml`
- [x] Link it in `templates/index.html` `<head>`
- [x] Add an asset test for the favicon route
- [ ] Validate with `cargo test --workspace` / `nix flake check`

## Summary of Changes

Added a small SVG favicon to the beansd launcher web UI.

- `crates/beansd/src/web/static/favicon.svg` — a coffee-bean glyph in the UI's Catppuccin palette (`#1e1e2e` rounded base, `#fab387` bean with a dark seam), rasterized and eyeballed at small sizes.
- `routes/assets.rs` — embeds it via `include_str!` and serves `/static/favicon.svg` as `image/svg+xml`, mirroring the htmx/css handlers; added a matching route test.
- `templates/index.html` — linked it in `<head>` via `<link rel="icon" type="image/svg+xml">`.

Kept dependency-free; the whole-directory embed refactor (rust-embed) was split into follow-up `dotfiles-4o6t`.
