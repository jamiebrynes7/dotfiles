---
# dotfiles-cdo2
title: Warn when the desktop app can clobber a managed config
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:28:17Z
updated_at: 2026-09-21T17:30:07Z
parent: dotfiles-khsx
---

**Files:**
- Modify: `home/programs/paseo.nix:275` — add `warnings` beside the existing `assertions`, in the unconditional first element of `config = lib.mkMerge [ ... ]`

The `postPatch` guard in `packages/paseo` protects the daemon this repo builds. `passthru.desktop` is a signed upstream zip bundling its own unpatched daemon, which takes over when no service daemon is running — so `enable` + `desktop.enable` without `service.enable` is the one combination where a managed config.json is unprotected. A warning, not an assertion: starting the daemon by hand is legitimate.

- [ ] **Step 1: Add the warning**

```nix
      warnings = lib.optional (cfg.enable && cfg.desktop.enable && !cfg.service.enable) ''
        dotfiles.programs.paseo: config.json is managed by Nix, but nothing on this host
        runs the patched daemon. The desktop app bundles its own unpatched daemon, which
        takes over when no service daemon is running and can overwrite the managed file.
        Set service.enable = true, or expect activation to move clobbered files aside.
      '';
```

- [ ] **Step 2: Format**

Run: `nixfmt home/programs/paseo.nix`

- [ ] **Step 3: Verify it fires only for that combination**

```bash
nix eval --impure --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
    mk = extra: (flake.lib.mkHomeManagerSystem {
      system = builtins.currentSystem;
      user = "test";
      directory = "/home/test";
      home = { ... }: {
        home.stateVersion = "25.05";
        dotfiles.profiles.base = false;
        dotfiles.programs.paseo = { enable = true; } // extra;
      };
    }).config.warnings;
  in {
    desktopNoService = mk { desktop.enable = true; };
    desktopWithService = mk { desktop.enable = true; service.enable = true; };
    plain = mk { };
  }
'
```

Expected: `desktopNoService` holds one warning naming the desktop app; `desktopWithService` and `plain` are empty. Note `desktop.enable` is Darwin-only (there is an assertion for it), so run this on macOS.

- [ ] **Step 4: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: warn when the desktop daemon can clobber config" -m "Bean: dotfiles-cdo2"
```
