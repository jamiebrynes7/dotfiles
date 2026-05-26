---
# dotfiles-ottn
title: home-manager module (`home/programs/beans-daemon.nix`)
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-26T16:58:16Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-lfly
---

Module exposing `dotfiles.programs.beans-daemon` options (enable, launcherPort, lruCap, heartbeatSecs, enableZshIntegration). Wires launchd agent on Darwin, systemd-user service on Linux, renders `xdg.configFile."beans-daemon/config.toml"` (including the absolute Nix store path of `beans-serve`), and appends the zsh `chpwd` hook to `programs.zsh.initContent`. Owns: `home/programs/beans-daemon.nix`.

## Summary of Changes

Delivered `home/programs/beans-daemon.nix` exposing `dotfiles.programs.beans-daemon` with options `enable`, `launcherPort`, `lruCap`, `heartbeatSecs`, `enableZshIntegration`. Renders `xdg.configFile."beans-daemon/config.toml"` (pointing `beans_serve_path` at `pkgs.dotfiles.beans`), wires `launchd.agents.beans-daemon` on Darwin and `systemd.user.services.beans-daemon` on Linux, and appends a zsh `chpwd_functions` hook that fires `beansctl cd "$PWD"`.

The original blocker `dotfiles-lfly` was scrapped (folded into the workspace split work in `dotfiles-7zn7`), so this feature shipped against the already-existing `packages/beans-daemon/default.nix`. The module follows the `pkgs.dotfiles.<name>` overlay convention from `home/programs/beans.nix` rather than the `pkgs.callPackage ../../packages/...` form sketched in the original sub-task drafts.

No host enables this yet — that wiring lives downstream in host configs and is not in scope here.

Sub-tasks:
- dotfiles-xm8c — module scaffold + options
- dotfiles-w28q — launchd agent (Darwin)
- dotfiles-ta5k — systemd-user service (Linux)
- dotfiles-go1u — zsh chpwd hook integration
