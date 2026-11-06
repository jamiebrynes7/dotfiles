---
# dotfiles-2sbi
title: Scheduled Nix GC keeping the last N generations
status: completed
type: feature
priority: normal
created_at: 2026-11-05T13:47:29Z
updated_at: 2026-11-06T10:11:36Z
---

Weekly job on nix-darwin, NixOS and standalone home-manager: prune each profile to its last N generations, collect garbage, optimise the store. Works with or without Determinate Nix, and disables Determinate Nixd's own collector where Determinate manages the system.

- [x] Shared prune/gc/optimise script and options under modules/nix-gc/
- [x] nix-darwin launchd daemon (+ disable Determinate GC when nix.enable = false)
- [x] NixOS systemd timer (+ disable Determinate GC when determinate.enable)
- [x] Standalone home-manager user agent/timer
- [x] Wire into mkDarwin / mkNixosSystem / mkHomeManagerSystem
- [x] Verify script against a scratch profile and eval each platform
- [x] Update CLAUDE.md

## Summary of Changes

Added `modules/nix-gc/`: a shared script that prunes each profile to its last `dotfiles.nix.gc.keepGenerations` (default 5), collects garbage and optimises the store, using whichever `nix` is on PATH. Weekly wrappers for nix-darwin (root launchd daemon), NixOS (systemd timer) and standalone home-manager (user launchd agent / systemd user timer), wired into mkDarwin / mkNixosSystem / mkHomeManagerSystem. Disables Determinate Nixd's collector on darwin when `nix.enable = false` and on NixOS when `determinate.enable`. Documented in CLAUDE.md.
