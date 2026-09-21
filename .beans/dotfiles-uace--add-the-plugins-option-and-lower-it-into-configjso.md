---
# dotfiles-uace
title: Add the plugins option and lower it into config.json
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:28:17Z
updated_at: 2026-09-21T17:30:07Z
parent: dotfiles-khsx
blocked_by:
    - dotfiles-t17y
---

**Files:**
- Modify: `home/programs/paseo.nix:160` — add the `plugins` option after `settings`
- Modify: `home/programs/paseo.nix:109` — add `pluginEntries` to the `let` block and fold it into `renderedSettings`
- Modify: `home/programs/paseo.nix:275` — add the plugin id assertion

Depends on the unconditional-rendering task: this folds into the `renderedSettings` binding that task introduces.

- [ ] **Step 1: Add the option**

```nix
    plugins = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            package = lib.mkOption {
              type = lib.types.path;
              description = "Directory holding the plugin's `paseo-plugin.json` and entry points.";
            };
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether the daemon should load this plugin.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        { catppuccin-theme.package = pkgs.dotfiles.paseo-plugin-catppuccin-theme; }
      '';
      description = ''
        Plugins to configure, keyed by plugin id. Each becomes a `directory` source
        in `config.json` — the only source the persisted schema accepts. `github:`,
        `git:` and `npm:` are install-time syntax the daemon resolves into a local
        directory, so there is nothing else worth expressing here.

        The attribute name is the id the daemon uses. It is deliberately not read
        from the plugin's `paseo-plugin.json`: that read would be
        import-from-derivation, and `packages/paseo` stays the only IFD package.

        `enable = false` keeps a plugin configured but stopped — the declarative
        replacement for the Settings toggle, which a managed config.json reverts.

        `types.path` accepts a derivation or a `"''${src}/plugins/foo"` string, so an
        inline `fetchFromGitHub` works without a `packages/` entry.
      '';
    };
```

- [ ] **Step 2: Lower it into the rendered config**

Add to the `let` block, above `renderedSettings`:

```nix
  pluginEntries = lib.optionalAttrs (cfg.plugins != { }) {
    pluginsEnabled = true;
    plugins = lib.mapAttrs (_: plugin: {
      source = "directory";
      path = toString plugin.package;
      enabled = plugin.enable;
    }) cfg.plugins;
  };
```

and change `renderedSettings` to:

```nix
  # cfg.settings last: an explicit `pluginsEnabled = false` stays expressible.
  renderedSettings = lib.recursiveUpdate creationDefaults (pluginEntries // cfg.settings);
```

- [ ] **Step 3: Add the id assertion**

In the `assertions` list:

```nix
        {
          assertion = lib.all (id: builtins.match "[a-z][a-z0-9-]*" id != null) (lib.attrNames cfg.plugins);
          message =
            "dotfiles.programs.paseo.plugins ids must match upstream's PluginIdSchema (^[a-z][a-z0-9-]*$): "
            + lib.concatStringsSep ", " (
              lib.filter (id: builtins.match "[a-z][a-z0-9-]*" id == null) (lib.attrNames cfg.plugins)
            );
        }
```

`builtins.match` anchors the whole string, so no `^`/`$` needed. This fails at switch instead of at daemon start, where a bad id surfaces as a zod parse error in the log.

- [ ] **Step 4: Format**

Run: `nixfmt home/programs/paseo.nix`

- [ ] **Step 5: Verify a plugin renders**

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
        dotfiles.programs.paseo = {
          enable = true;
          plugins.catppuccin-theme.package = "/nix/store/fake-plugin";
        };
      };
    };
  in builtins.readFile hm.config.home.file.".paseo/config.json".source
'
```

Expected: `"pluginsEnabled": true` and a `plugins` object with `catppuccin-theme` = `{ "enabled": true, "path": "/nix/store/fake-plugin", "source": "directory" }`.

- [ ] **Step 6: Verify the assertion fires on a bad id**

Run the same command with `plugins.catppuccin-theme` replaced by `plugins."Bad_Id"`.

Expected: evaluation fails with the `PluginIdSchema` message naming `Bad_Id`.

- [ ] **Step 7: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: add a declarative plugins option" -m "Bean: dotfiles-uace"
```
