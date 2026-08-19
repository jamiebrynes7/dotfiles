---
# dotfiles-oelc
title: Add hostnames and allowAnyHostname options to the paseo module
status: todo
type: task
priority: normal
created_at: 2026-08-19T10:57:32Z
updated_at: 2026-08-19T10:57:37Z
parent: dotfiles-ltuq
blocked_by:
    - dotfiles-p1pz
---

**Files:**
- Modify: `home/programs/paseo.nix` — options block, `serviceEnv`, new `assertions`
- Modify: `flake.nix` — the scratch config inside `mkPaseoModuleCheck`

Background, because the semantics are surprising: paseo's allowlist matches the **`Host` header**, not the bind address (`packages/server/src/server/hostnames.ts` upstream). The built-in defaults allow `localhost`, `*.localhost`, and any literal IP. So with `listenAddress = "0.0.0.0"`, reaching the daemon at `http://192.168.1.5:6767` needs no config, but `http://warbird.lan:6767` is **rejected** — the websocket upgrade fails with `403 Host not allowed`, which usually presents as "the UI loads but never connects".

Upstream also accepts `PASEO_HOSTNAMES=true` to disable the check. We expose that as a separate boolean rather than mirroring upstream's `either (enum [ true ]) (listOf str)` union.

- [ ] **Step 1: Extend the check's scratch config**

In `flake.nix`, inside `mkPaseoModuleCheck`'s `dotfiles.programs.paseo` block, add:

```nix
                hostnames = [ "warbird.lan" ];
```

and add this line to the `runCommandLocal` script, before `touch $out`:

```bash
          grep -F 'warbird.lan' ${unit}
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link 2>&1 | tail -5`
Expected: FAIL with `The option 'dotfiles.programs.paseo.hostnames' does not exist`.

- [ ] **Step 3: Add the options**

In `home/programs/paseo.nix`, add to `options.dotfiles.programs.paseo` after `port`:

```nix
    hostnames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "warbird.lan"
        ".example.com"
      ];
      description = ''
        Hostnames the daemon accepts in the Host header (DNS rebinding
        protection). Matched against the Host header, NOT the bind address, so
        `listenAddress` has no bearing on it.

        Added to the built-in defaults, never a replacement for them: localhost,
        *.localhost and any literal IP address are always allowed. Reaching the
        daemon at http://192.168.1.5:6767 therefore needs nothing here, while
        http://warbird.lan:6767 needs `[ "warbird.lan" ]`. A leading dot matches
        a domain and all its subdomains.

        A rejected host fails the websocket upgrade with 403 Host not allowed,
        which typically looks like the UI loading but never connecting.
      '';
    };

    allowAnyHostname = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Accept any Host header, disabling DNS rebinding protection entirely.
        Any web page you visit can then reach the daemon by name. Prefer listing
        the names you actually use in `hostnames`.
      '';
    };
```

- [ ] **Step 4: Thread them into the environment and add the assertion**

In `serviceEnv`, insert both `optionalAttrs` blocks **before** the `cfg.environment` merge, so the escape hatch still wins:

```nix
  serviceEnv = {
    PASEO_HOME = cfg.dataDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
  }
  // lib.optionalAttrs cfg.allowAnyHostname { PASEO_HOSTNAMES = "true"; }
  // lib.optionalAttrs (cfg.hostnames != [ ]) {
    PASEO_HOSTNAMES = lib.concatStringsSep "," cfg.hostnames;
  }
  // cfg.environment;
```

In `config`, add an `assertions` attribute (first entry in the block):

```nix
    assertions = [
      {
        assertion = !(cfg.allowAnyHostname && cfg.hostnames != [ ]);
        message = ''
          dotfiles.programs.paseo: allowAnyHostname and hostnames are mutually
          exclusive -- allowAnyHostname accepts every Host header, which makes
          the hostnames list dead config.
        '';
      }
    ];
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link`
Expected: PASS (no output, exit 0).

- [ ] **Step 6: Verify the assertion actually fires**

Run:

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
      hostnames = [ "a.lan" ];
      allowAnyHostname = true;
    };
  };
}).config.home.activationPackage' 2>&1 | tail -5
```

Expected: FAIL with `mutually exclusive` in the message. (`assertions` are only enforced when the activation package is built, which is why this evaluates that attribute rather than the config directly.)

- [ ] **Step 7: Format check**

Run: `nixfmt --check flake.nix home/programs/paseo.nix`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add flake.nix home/programs/paseo.nix
git commit -m "home/programs/paseo: add hostname allowlist options

Bean: dotfiles-oelc"
```
