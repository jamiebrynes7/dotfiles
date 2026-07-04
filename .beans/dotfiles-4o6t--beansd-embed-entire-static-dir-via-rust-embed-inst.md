---
# dotfiles-4o6t
title: '[beansd] Embed entire static/ dir via rust-embed instead of per-asset routes'
status: todo
type: task
priority: low
created_at: 2026-07-04T20:56:23Z
updated_at: 2026-07-04T20:56:23Z
---

The beansd web UI hand-wires every static asset three ways: a `const … = include_str!/include_bytes!`, a `serve_*` handler with a hard-coded content-type, and a `.route(...)` line (see `crates/beansd/src/web/routes/assets.rs`). At three assets (htmx.min.js, app.css, favicon.svg) it's already repetitive and easy to forget a content-type when adding the next one.

Replace it with a `go:embed`-style whole-directory embed:

- Add `rust-embed` (`#[derive(RustEmbed)] #[folder = "src/web/static"]`) — the closest analog to Go's `go:embed`.
- Serve via `axum-embed`'s `ServeEmbed` handler (or a thin hand-rolled equivalent) mounted at `/static/*path`, deriving content-type automatically via `mime_guess`. One route replaces the three per-asset handlers.
- Keep the single-binary property: assets stay embedded at compile time, not read from disk (so `tower-http` `ServeDir` is NOT suitable).
- Update / consolidate the asset tests accordingly.

## Notes

- Introduces new workspace dependencies (`rust-embed`, `axum-embed`). Per `crates/CLAUDE.md`, new deps should be added to `[workspace.dependencies]` and were flagged with the user first — user has approved rust-embed as the direction.
- Split out of `dotfiles-ytfy` (favicon) to keep that cosmetic change dependency-free.

## Tasks

- [ ] Add `rust-embed` + `axum-embed` to `[workspace.dependencies]` and the beansd crate
- [ ] Embed `src/web/static` and mount a single `/static/*path` route with mime-derived content-types
- [ ] Remove the per-asset consts/handlers/routes from `assets.rs`
- [ ] Update asset tests to cover the wildcard route (js, css, svg content-types)
- [ ] Validate with `nix flake check`
