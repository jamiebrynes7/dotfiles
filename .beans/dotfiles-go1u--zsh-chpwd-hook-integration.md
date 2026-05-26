---
# dotfiles-go1u
title: zsh chpwd hook integration
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-26T16:57:59Z
parent: dotfiles-ottn
---

**Files:**
- Modify: `home/programs/beans-daemon.nix`

- [x] **Step 1: Append the zsh integration to the `config = lib.mkIf cfg.enable { ... }` body**

```nix
    programs.zsh.initContent = lib.mkIf
      (cfg.enableZshIntegration && config.programs.zsh.enable)
      (lib.mkAfter ''
        beans_daemon_chpwd() {
          (${beans-daemon}/bin/beansctl cd "$PWD" &) >/dev/null 2>&1
        }
        chpwd_functions+=(beans_daemon_chpwd)
      '');
```

- [x] **Step 2: Verify**

Run: `nix flake check`
Expected: no evaluation errors.

- [x] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: zsh chpwd hook integration'
```

## Summary of Changes

Added `programs.zsh.initContent` block (gated on `cfg.enableZshIntegration && config.programs.zsh.enable`) appending a `chpwd_functions` hook that fires `beansctl cd "$PWD"` as a backgrounded, silenced fire-and-forget.

`nix flake check` evaluated clean on aarch64-darwin.
