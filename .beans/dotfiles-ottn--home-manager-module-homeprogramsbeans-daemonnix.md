---
# dotfiles-ottn
title: home-manager module (`home/programs/beans-daemon.nix`)
status: todo
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-03T14:43:17Z
parent: dotfiles-nzsd
blocked_by:
    - dotfiles-lfly
---

Module exposing `dotfiles.programs.beans-daemon` options (enable, launcherPort, lruCap, heartbeatSecs, enableZshIntegration). Wires launchd agent on Darwin, systemd-user service on Linux, renders `xdg.configFile."beans-daemon/config.toml"` (including the absolute Nix store path of `beans-serve`), and appends the zsh `chpwd` hook to `programs.zsh.initContent`. Owns: `home/programs/beans-daemon.nix`.
