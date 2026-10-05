---
# dotfiles-t17y
title: Render config.json unconditionally with the daemon's creation defaults
status: completed
type: task
priority: normal
created_at: 2026-09-21T17:28:17Z
updated_at: 2026-10-05T12:25:15Z
parent: dotfiles-khsx
---

**Files:**
- Modify: `home/programs/paseo.nix:109` — add `creationDefaults` and `renderedSettings` to the `let` block, after `dataDirRelative`
- Modify: `home/programs/paseo.nix:297-299` — replace the gated `home.file` block
- Modify: `home/programs/paseo.nix:285` — make the dataDir assertion unconditional
- Modify: `home/programs/paseo.nix:160` — rewrite the `settings` description

Why unconditional: any non-empty `settings` already made the daemon's own writes futile, so the `settings != { }` gate bought an ownership model the module cannot deliver. Plugins are only expressible through this file, so the module has to own it.

- [x] **Step 1: Add the let bindings**

After `dataDirRelative`:

```nix
  # The daemon writes DEFAULT_PERSISTED_CONFIG only when config.json is absent
  # (persisted-config.ts:347,421), and it never is once home-manager links one. Every
  # field in PersistedConfigSchema is optional with no zod-level default, so these two
  # have to come from here or every host silently loses them.
  creationDefaults = {
    daemon.cors.allowedOrigins = [ "https://app.paseo.sh" ];
    app.baseUrl = "https://app.paseo.sh";
  };

  renderedSettings = lib.recursiveUpdate creationDefaults cfg.settings;
```

- [x] **Step 2: Write the file unconditionally**

Replace:

```nix
      home.file = lib.mkIf (cfg.settings != { }) {
        "${dataDirRelative}/config.json".source = configFormat.generate "paseo-config.json" cfg.settings;
      };
```

with:

```nix
      # Nix owns this file whenever the module is enabled; the daemon is patched to
      # throw rather than overwrite it (packages/paseo). The old `settings != { }`
      # gate only chose between two flavours of the same clobbering.
      home.file."${dataDirRelative}/config.json".source =
        configFormat.generate "paseo-config.json" renderedSettings;
```

Leave the existing comment about the daemon's best-effort chmod in place above it.

- [x] **Step 3: Make the dataDir assertion unconditional**

Replace the `cfg.settings == { }` assertion with:

```nix
        {
          assertion = !cfg.enable || (lib.hasPrefix "${config.home.homeDirectory}/" cfg.dataDir);
          message = "dotfiles.programs.paseo requires dataDir to be inside the home directory, since config.json is written with home.file.";
        }
```

- [x] **Step 4: Rewrite the `settings` description**

Replace the "Leave this empty (the default) to let the daemon create and own the file..." paragraph with:

```
        Extra keys merged into `$PASEO_HOME/config.json`, which this module always
        writes and links from the store.

        Nix owns that file whenever `enable` is set: the daemon is patched to throw
        rather than overwrite it, so `paseo daemon set-password`, `paseo onboard` and
        Settings writes fail by design. Set a daemon password with `PASEO_PASSWORD`
        via `environmentCommand` instead — it is read as plaintext and hashed at
        startup.

        These keys are applied last, so they win over the module's own defaults.
```

Keep the closing sentence pointing at `PersistedConfigSchema`.

- [x] **Step 5: Format**

Run: `nixfmt home/programs/paseo.nix`

- [x] **Step 6: Verify the rendered config**

```bash
nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    hm = flake.lib.mkHomeManagerSystem {
      system = builtins.currentSystem;
      user = "test";
      directory = "/home/test";
      home = { ... }: {
        home.stateVersion = "25.05";
        dotfiles.profiles.base = false;
        dotfiles.programs.paseo.enable = true;
      };
    };
  in builtins.readFile hm.config.home.file.".paseo/config.json".source
'
```

Expected: a config containing `daemon.cors.allowedOrigins` = `["https://app.paseo.sh"]` and `app.baseUrl`, with no `settings` set at all. Before this change the same command fails with a missing-attribute error, which is the point.

- [x] **Step 7: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: always write config.json from the store" -m "Bean: dotfiles-t17y"
```

## Summary of Changes

`home/programs/paseo.nix` now always writes `config.json` from the store when `enable` is set: `recursiveUpdate creationDefaults cfg.settings`, where `creationDefaults` restores `daemon.cors.allowedOrigins` and `app.baseUrl` from the daemon's DEFAULT_PERSISTED_CONFIG. The dataDir assertion is gated on `enable` instead of `settings`, and the `settings` description now explains Nix ownership and points at PASEO_PASSWORD. The comment cites `loadPersistedConfig` rather than the bean's v0.8.0 line numbers, which have drifted.
