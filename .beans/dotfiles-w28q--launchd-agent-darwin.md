---
# dotfiles-w28q
title: launchd agent (Darwin)
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-26T16:56:58Z
parent: dotfiles-ottn
---

**Files:**
- Modify: `home/programs/beans-daemon.nix`

- [x] **Step 1: Append the launchd block to the `config = lib.mkIf cfg.enable { ... }` body**

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

- [x] **Step 2: Verify the module evaluates**

Run: `nix flake check`
Expected: no evaluation errors.

- [x] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: launchd agent for Darwin'
```

## Summary of Changes

Added `launchd.agents.beans-daemon` (gated on `pkgs.stdenv.isDarwin`) to `home/programs/beans-daemon.nix`. Runs `${pkgs.dotfiles.beans-daemon}/bin/beansd` with `KeepAlive` + `RunAtLoad`; stdout/stderr go to `~/Library/Logs/beans-daemon.log`.

Omitted the empty `EnvironmentVariables` block from the original plan — there are no env vars to set, and an empty attrset with only a comment is noise.

`nix flake check` evaluated clean on aarch64-darwin.
