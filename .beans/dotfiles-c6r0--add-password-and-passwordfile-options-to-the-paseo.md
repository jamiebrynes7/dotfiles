---
# dotfiles-c6r0
title: Add password and passwordFile options to the paseo module
status: todo
type: task
priority: normal
created_at: 2026-08-19T10:57:58Z
updated_at: 2026-08-19T10:59:18Z
parent: dotfiles-ltuq
blocked_by:
    - dotfiles-oelc
---

**Files:**
- Modify: `home/programs/paseo.nix` — options block, `launcher`, `serviceEnv`, `assertions`
- Modify: `flake.nix` — the scratch config inside `mkPaseoModuleCheck`

Background: paseo reads `PASEO_PASSWORD` as **plaintext** and bcrypt-hashes it at startup (`packages/server/src/server/config.ts:409` upstream). There is no hashed-input variable, so a declarative password either lands in the world-readable Nix store (`password`) or is read from a file outside it at process start (`passwordFile`).

`passwordFile` is read inside the shared launcher rather than via systemd's `EnvironmentFile=`, because launchd has no file-based equivalent — the launcher is the only mechanism that behaves identically on both platforms.

- [ ] **Step 1: Extend the check's scratch config**

In `flake.nix`, inside `mkPaseoModuleCheck`'s `dotfiles.programs.paseo` block, add:

```nix
                passwordFile = "/run/secrets/paseo-password";
```

and add these lines to the `runCommandLocal` script, before `touch $out`:

```bash
          grep -F '/run/secrets/paseo-password' ${launcher}
          # The secret must be read at start, never baked into the unit.
          ! grep -F 'PASEO_PASSWORD' ${unit}
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link 2>&1 | tail -5`
Expected: FAIL with `The option 'dotfiles.programs.paseo.passwordFile' does not exist`.

- [ ] **Step 3: Add the options**

In `home/programs/paseo.nix`, add to `options.dotfiles.programs.paseo` after `allowAnyHostname`:

```nix
    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Daemon password, in plaintext. Paseo hashes it at startup; there is no
        hashed-input variable to use instead.

        This value is written into the Nix store, which is world-readable on the
        host, and into whatever config declares it. Prefer `passwordFile`.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/paseo-password";
      description = ''
        Path to a file outside the Nix store containing the plaintext daemon
        password and nothing else.

        Read by the launcher at each service start, so rotating the secret needs
        only a service restart, not a home-manager switch. An unreadable file is
        a startup failure rather than a silently unauthenticated daemon.
      '';
    };
```

- [ ] **Step 4: Thread them through**

In `launcher`, insert the read between the `chmod` and the `exec` — **not** after the `exec`, which would never run. The launcher body reads, in full:

```nix
  launcher = pkgs.writeShellScript "paseo-launcher" ''
    set -euo pipefail

    export PATH="${servicePath}"

    # home-manager has no systemd.tmpfiles equivalent; upstream's NixOS module
    # creates PASEO_HOME with the same 0700 mode.
    mkdir -p "$PASEO_HOME"
    chmod 700 "$PASEO_HOME"
    ${lib.optionalString (cfg.passwordFile != null) ''
      # Read at start, not at switch. `set -e` above turns an unreadable file
      # into a loud failure rather than a silently unauthenticated daemon.
      PASEO_PASSWORD="$(cat ${cfg.passwordFile})"
      export PASEO_PASSWORD
    ''}
    exec ${cfg.package}/bin/paseo-server --no-relay
  '';
```

In `serviceEnv`, add the plain-password case **before** the `cfg.environment` merge:

```nix
  // lib.optionalAttrs (cfg.password != null) { PASEO_PASSWORD = cfg.password; }
  // cfg.environment;
```

Add a second entry to `assertions`:

```nix
      {
        assertion = !(cfg.password != null && cfg.passwordFile != null);
        message = ''
          dotfiles.programs.paseo: password and passwordFile are mutually
          exclusive -- set one or the other.
        '';
      }
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link`
Expected: PASS (no output, exit 0).

- [ ] **Step 6: Verify the assertion fires**

```bash
nix eval --impure --expr '
let f = builtins.getFlake (toString ./.);
in (f.lib.mkHomeManagerSystem {
  system = "aarch64-darwin";
  user = "t";
  directory = "/Users/t";
  home = {
    home.stateVersion = "23.05";
    dotfiles.profiles.base = false;
    dotfiles.programs.paseo = {
      enable = true;
      password = "hunter2";
      passwordFile = "/run/secrets/paseo-password";
    };
  };
}).config.home.activationPackage' 2>&1 | tail -5
```

Expected: FAIL with `mutually exclusive` in the message.

- [ ] **Step 7: Run the whole check suite**

Run: `nix flake check --print-build-logs`
Expected: PASS. Note this builds `pkgs.dotfiles.paseo` for real (a full npm + node-gyp build), so allow several minutes on a cold store.

- [ ] **Step 8: Format check**

Run: `nixfmt --check flake.nix home/programs/paseo.nix`
Expected: no output, exit 0.

- [ ] **Step 9: Commit**

```bash
git add flake.nix home/programs/paseo.nix
git commit -m "home/programs/paseo: add password and passwordFile options

Bean: dotfiles-c6r0"
```
