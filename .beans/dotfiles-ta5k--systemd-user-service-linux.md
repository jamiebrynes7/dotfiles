---
# dotfiles-ta5k
title: systemd-user service (Linux)
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-10T15:53:02Z
parent: dotfiles-ottn
---

**Files:**
- Modify: `home/programs/beans-daemon.nix`

- [ ] **Step 1: Append the systemd block to the `config = lib.mkIf cfg.enable { ... }` body**

```nix
    systemd.user.services.beans-daemon = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Beans daemon — multiplexes beans-serve across projects";
        After       = [ "default.target" ];
      };
      Service = {
        ExecStart  = "${beans-daemon}/bin/beansd";
        Restart    = "always";
        RestartSec = 2;
        # Daemon writes to stdout/stderr; systemd captures via journald.
      };
      Install.WantedBy = [ "default.target" ];
    };
```

- [ ] **Step 2: Verify**

Run: `nix flake check`
Expected: no evaluation errors.

- [ ] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: systemd-user service for Linux'
```
