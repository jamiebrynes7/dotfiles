---
# dotfiles-dqnt
title: Update flake to 26.05 nixpkgs/darwin/home-manager
status: completed
type: task
priority: normal
created_at: 2026-06-01T16:36:29Z
updated_at: 2026-06-01T20:32:08Z
---

Bump the flake's stable channel inputs from 25.11 to 26.05 once 26.05 is released.

Inputs to update in `flake.nix`:

- [x] `nixpkgs.url` → `github:nixos/nixpkgs/nixos-26.05`
- [x] `nixpkgs-darwin.url` → `github:nixos/nixpkgs/nixpkgs-26.05-darwin`
- [x] `darwin.url` → `github:LnL7/nix-darwin/nix-darwin-26.05`
- [x] `home-manager.url` → `github:nix-community/home-manager/release-26.05`
- [x] `nix flake update` to refresh `flake.lock` (also pulls follows-pinned overlays/tools)
- [x] `nix flake check` passes (builds + Rust workspace tests)
- [x] Review 26.05 release notes for breaking changes affecting nix-darwin / home-manager modules

## Notes

Overlay/tool inputs (alacritty-themes, rust-overlay, claude-code, sprites-cli) follow `nixpkgs` so they pick up the bump automatically, but verify nothing breaks after the lock update.

## Summary of Changes

Bumped the flake's four stable-channel inputs from 25.11 to 26.05:

- `nixpkgs` → `nixos-26.05`
- `nixpkgs-darwin` → `nixpkgs-26.05-darwin`
- `darwin` → `nix-darwin-26.05`
- `home-manager` → `release-26.05`

Ran `nix flake update` to regenerate `flake.lock` (overlay/tool inputs — alacritty-themes, rust-overlay, claude-code, sprites-cli — follow nixpkgs and updated automatically). `nix flake check` passes (builds + Rust workspace tests, no eval warnings).

Reviewed the 26.05 release notes for breaking changes; none are actionable for this repo: `programs.zsh.dotDir` is already pinned to `~/.config/zsh` and `programs.neovim.withPython3/withRuby` are already set to `false`, so the changed defaults are no-ops here. The repo targets aarch64-darwin/x86_64-linux, so the x86_64-darwin deprecation does not apply.
