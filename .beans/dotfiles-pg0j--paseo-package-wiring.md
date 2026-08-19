---
# dotfiles-pg0j
title: paseo package wiring
status: todo
type: feature
created_at: 2026-08-19T10:54:38Z
updated_at: 2026-08-19T10:54:38Z
parent: dotfiles-7043
---

Brings paseo into the flake as a patched package at `pkgs.dotfiles.paseo`.

Owns:
- `flake.nix` — the `paseo` input and its entry in `defaultOverlays`
- `overlays/paseo.nix` — NEW top-level directory; the overlay fragment carrying both upstream patches

Upstream does not build as tagged, so two patches ride along, both re-verified against v0.3.1 and v0.4.0 (whose `nix/package.nix` files are byte-identical):

1. A stale `nix/npm-deps.hash` at every release tag.
2. Missing `node-pty` prebuilds in `$out`, which breaks every terminal pane.

Landing at `pkgs.dotfiles.paseo` deliberately pulls paseo into `mkPackages`, and therefore into `packages.*` and `checks.*`, so `nix flake check` builds it. That is the only thing that catches a stale hash after a nixpkgs or paseo bump.
