---
# dotfiles-ta5k
title: systemd-user service (Linux)
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-26T16:57:28Z
parent: dotfiles-ottn
---

**Files:**
- Modify: `home/programs/beans-daemon.nix`

- [x] **Step 1: Append the systemd block to the `config = lib.mkIf cfg.enable { ... }` body**

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

- [x] **Step 2: Verify**

Run: `nix flake check`
Expected: no evaluation errors.

- [x] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: systemd-user service for Linux'
```

## Summary of Changes

Added `systemd.user.services.beans-daemon` (gated on `pkgs.stdenv.isLinux`) to `home/programs/beans-daemon.nix`. ExecStart runs `${pkgs.dotfiles.beans-daemon}/bin/beansd`; `Restart = always` with 2s backoff; wanted by `default.target`.

Dropped the inline comment about journald — the behavior is journald-by-default for any systemd unit that doesn't redirect stdout, not something specific worth calling out here.

`nix flake check` on aarch64-darwin evaluated clean (the Linux-gated block is a no-op on Darwin).
