---
# dotfiles-xm8c
title: Module scaffold + options for `dotfiles.programs.beans-daemon`
status: todo
type: task
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-03T14:42:39Z
parent: dotfiles-ottn
---

**Files:**
- Create: `home/programs/beans-daemon.nix`

This module is auto-discovered by `home/default.nix` (which imports every file in `home/programs/`). The user opts in via `dotfiles.programs.beans-daemon.enable = true` in their host config.

- [ ] **Step 1: Write the module skeleton**

`home/programs/beans-daemon.nix`:
```nix
{ config, lib, pkgs, ... }:
let
  beans = pkgs.callPackage ../../packages/beans { };
  beans-daemon = pkgs.callPackage ../../packages/beans-daemon { };
  cfg = config.dotfiles.programs.beans-daemon;
in {
  options.dotfiles.programs.beans-daemon = {
    enable = lib.mkEnableOption "Enable the beans daemon";
    launcherPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "TCP port for the unified web launcher.";
    };
    lruCap = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Maximum number of beans-serve children warm at once.";
    };
    heartbeatSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Browser heartbeat interval in seconds.";
    };
    enableZshIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the zsh chpwd hook that pings the daemon on each cd.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ beans-daemon ];

    xdg.configFile."beans-daemon/config.toml".text = ''
      launcher_port    = ${toString cfg.launcherPort}
      lru_cap          = ${toString cfg.lruCap}
      heartbeat_secs   = ${toString cfg.heartbeatSecs}
      log_level        = "info"
      beans_serve_path = "${beans}/bin/beans-serve"
    '';
  };
}
```

- [ ] **Step 2: Verify the module evaluates**

Run from the repo root: `nix flake check`
Expected: no evaluation errors. (No host has the option enabled yet, so this is just an option-evaluation smoke check.)

- [ ] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: module scaffold + options'
```
