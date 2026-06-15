---
# dotfiles-040q
title: Install bubblewrap with codex on Linux
status: completed
type: task
priority: normal
created_at: 2026-06-11T10:18:01Z
updated_at: 2026-06-11T10:19:24Z
---

Codex looks for the bwrap sandbox on Linux. The codex home-manager module should ensure nixpkgs.bubblewrap is available on PATH (like rg) when codex is enabled on Linux.

- [x] Add pkgs.bubblewrap to home.packages on Linux in home/programs/codex/default.nix
- [x] Validate with nix flake check / build

## Summary of Changes

Added `home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.bubblewrap ]` to `home/programs/codex/default.nix`, so `bwrap` is on PATH when codex is enabled on Linux (macOS uses Seatbelt and does not need it). Verified with `nix flake check` (darwin; Linux branch evaluates cleanly).
