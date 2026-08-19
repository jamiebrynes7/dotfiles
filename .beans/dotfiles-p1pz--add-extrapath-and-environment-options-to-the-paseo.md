---
# dotfiles-p1pz
title: Add extraPath and environment options to the paseo module
status: todo
type: task
priority: normal
created_at: 2026-08-19T10:57:04Z
updated_at: 2026-08-19T10:57:08Z
parent: dotfiles-ltuq
blocked_by:
    - dotfiles-lpk0
---

**Files:**
- Modify: `home/programs/paseo.nix` — options block, `servicePath`, `serviceEnv`
- Modify: `flake.nix` — the scratch config inside `mkPaseoModuleCheck`

These are the two escape hatches. `environment` is how a host sets things like `BROWSER` for agent hooks; `extraPath` is how it prepends a directory the computed default does not cover.

**Important asymmetry to preserve:** `environment` is merged **last** so it can override any `PASEO_*` variable — but it cannot override `PATH`, because the launcher `export`s the computed PATH *after* the unit environment is applied. `extraPath` is the supported knob for PATH, and the `environment` description must say so.

- [ ] **Step 1: Extend the check's scratch config**

In `flake.nix`, inside `mkPaseoModuleCheck`'s `dotfiles.programs.paseo` block, add:

```nix
                environment.BROWSER = "/bin/true";
                extraPath = [ "/opt/paseo/bin" ];
```

and add these two lines to the `runCommandLocal` script, before `touch $out`:

```bash
          grep -F 'BROWSER' ${unit}
          grep -F '/opt/paseo/bin' ${launcher}
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link 2>&1 | tail -5`
Expected: FAIL with `The option 'dotfiles.programs.paseo.environment' does not exist`.

- [ ] **Step 3: Add the options**

In `home/programs/paseo.nix`, add to `options.dotfiles.programs.paseo` after `port`:

```nix
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''{ BROWSER = "\''${pkgs.wsl-open}/bin/wsl-open"; }'';
      description = ''
        Extra environment variables for the daemon, and so for every agent
        process it spawns. Merged last, so these override the PASEO_* variables
        the module derives from the other options.

        PATH is the exception: the launcher exports the computed PATH after this
        environment is applied, so a PATH set here is silently overwritten. Use
        `extraPath` instead.
      '';
    };

    extraPath = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/opt/homebrew/bin" ];
      description = ''
        Directories prepended to the daemon's PATH, ahead of `~/.local/bin` and
        the Nix profile directories. The list is de-duplicated, order preserved.
      '';
    };
```

- [ ] **Step 4: Thread them through**

In the same file, prepend `cfg.extraPath` in `servicePath`:

```nix
  servicePath = lib.concatStringsSep ":" (
    lib.unique (
      cfg.extraPath
      ++ [ "${config.home.homeDirectory}/.local/bin" ]
      ++ config.home.sessionPath
      ++ [ "${config.home.profileDirectory}/bin" ]
      ++ systemPaths
    )
  );
```

and merge `cfg.environment` last in `serviceEnv`:

```nix
  serviceEnv = {
    PASEO_HOME = cfg.dataDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
  }
  // cfg.environment;
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link`
Expected: PASS (no output, exit 0).

- [ ] **Step 6: Format check**

Run: `nixfmt --check flake.nix home/programs/paseo.nix`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add flake.nix home/programs/paseo.nix
git commit -m "home/programs/paseo: add extraPath and environment options

Bean: dotfiles-p1pz"
```
