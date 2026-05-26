---
# dotfiles-lfly
title: Nix package (`packages/beans-daemon/default.nix`)
status: scrapped
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-10T15:52:56Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-5h2f
---

`rustPlatform.buildRustPackage` derivation with pinned `Cargo.lock`. No frontend build step — askama compiles templates into the binary; `htmx.min.js` and `app.css` are embedded via `include_bytes!`/`include_str!` from the source tree. Owns: `packages/beans-daemon/default.nix`.

## Reasons for Scrapping

Superseded by `dotfiles-qwfb` (Workspace split). The Nix derivation work is folded into Task `dotfiles-7zn7`, which produces a workspace-aware `default.nix` building both `beansd` and `beansctl` from the workspace root.
