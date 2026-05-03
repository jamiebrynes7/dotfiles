---
# dotfiles-go1u
title: zsh chpwd hook integration
status: todo
type: task
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-03T14:42:39Z
parent: dotfiles-ottn
---

**Files:**
- Modify: `home/programs/beans-daemon.nix`

- [ ] **Step 1: Append the zsh integration to the `config = lib.mkIf cfg.enable { ... }` body**

```nix
    programs.zsh.initContent = lib.mkIf
      (cfg.enableZshIntegration && config.programs.zsh.enable)
      (lib.mkAfter ''
        beans_daemon_chpwd() {
          (${beans-daemon}/bin/beansd cd "$PWD" &) >/dev/null 2>&1
        }
        chpwd_functions+=(beans_daemon_chpwd)
      '');
```

- [ ] **Step 2: Verify**

Run: `nix flake check`
Expected: no evaluation errors.

- [ ] **Step 3: Commit**

```
git add home/programs/beans-daemon.nix
git commit -m 'home/programs/beans-daemon: zsh chpwd hook integration'
```
