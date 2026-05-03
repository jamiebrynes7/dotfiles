---
# dotfiles-lfly
title: Nix package (`packages/beans-daemon/default.nix`)
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-5h2f
---

`rustPlatform.buildRustPackage` derivation with pinned `Cargo.lock`. No frontend build step — askama compiles templates into the binary; `htmx.min.js` and `app.css` are embedded via `include_bytes!`/`include_str!` from the source tree. Owns: `packages/beans-daemon/default.nix`.
