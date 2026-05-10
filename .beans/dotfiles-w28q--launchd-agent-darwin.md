---
# dotfiles-w28q
title: launchd agent (Darwin)
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-10T15:53:02Z
parent: dotfiles-ottn
---

**Files:**
- Modify: `home/programs/beans-daemon.nix`

- [ ] **Step 1: Append the launchd block to the `config = lib.mkIf cfg.enable { ... }` body**

```nix
    launchd.agents.beans-daemon = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${beans-daemon}/bin/beansd" ];
        KeepAlive        = true;
        RunAtLoad        = true;
        StandardOutPath  = "${config.home.homeDirectory}/Library/Logs/beans-daemon.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/beans-daemon.log";
        EnvironmentVariables = {
          # XDG isn't a thing on macOS; the daemon's default_socket_path uses
          # ~/Library/Caches/beans-daemon/sock on Darwin so no env var is needed.
        };
      };
    };
```

- [ ] **Step 2: Verify the module evaluates**

Run: `nix flake check`
Expected: no evaluation errors.

- [ ] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: launchd agent for Darwin'
```
