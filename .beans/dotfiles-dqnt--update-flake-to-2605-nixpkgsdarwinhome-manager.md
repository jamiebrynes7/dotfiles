---
# dotfiles-dqnt
title: Update flake to 26.05 nixpkgs/darwin/home-manager
status: todo
type: task
created_at: 2026-06-01T16:36:29Z
updated_at: 2026-06-01T16:36:29Z
---

Bump the flake's stable channel inputs from 25.11 to 26.05 once 26.05 is released.

Inputs to update in `flake.nix`:

- [ ] `nixpkgs.url` → `github:nixos/nixpkgs/nixos-26.05`
- [ ] `nixpkgs-darwin.url` → `github:nixos/nixpkgs/nixpkgs-26.05-darwin`
- [ ] `darwin.url` → `github:LnL7/nix-darwin/nix-darwin-26.05`
- [ ] `home-manager.url` → `github:nix-community/home-manager/release-26.05`
- [ ] `nix flake update` to refresh `flake.lock` (also pulls follows-pinned overlays/tools)
- [ ] `nix flake check` passes (builds + Rust workspace tests)
- [ ] Review 26.05 release notes for breaking changes affecting nix-darwin / home-manager modules

## Notes

Overlay/tool inputs (alacritty-themes, rust-overlay, claude-code, sprites-cli) follow `nixpkgs` so they pick up the bump automatically, but verify nothing breaks after the lock update.
