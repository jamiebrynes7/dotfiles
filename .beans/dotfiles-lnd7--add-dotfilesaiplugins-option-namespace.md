---
# dotfiles-lnd7
title: Add dotfiles.ai.plugins option namespace
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:14:11Z
updated_at: 2026-08-02T12:14:11Z
parent: dotfiles-jali
blocked_by:
    - dotfiles-nx0d
---

Declares the `dotfiles.ai.plugins.<name>` option namespace — the single place a feature declares its skills and hooks, replacing today's split between `skillsDirs` on three assistant modules and hand-wired `hooks` entries.

Options only in this task: nothing reads them yet, so there is no behaviour change. The renderer comes next.

**Files:**
- Create: `home/lib/ai/plugins/module.nix`
- Modify: `home/default.nix` (add the module to `imports`)

- [ ] **Step 1: Write the options module**

`home/lib/ai/plugins/module.nix`. Note this is a real home-manager module (uses `imports`/`options`), unlike the sibling `default.nix` files under `home/lib/ai/`, which are plain functions:

```nix
# Option namespace for AI assistant plugins. A plugin bundles skills and hooks
# under one name that can be enabled or disabled as a unit — globally via
# `defaultEnabled`, per project via Claude Code's `enabledPlugins` setting.
#
# Consumers project these declarations per assistant: claude-code renders real
# plugin directories, codex and cursor flatten `skillDirs` into loose skills.
{ lib, ... }:
let
  hookTypes = import ./hook-types.nix { inherit lib; };

  pluginType = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "this plugin";

      description = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable summary, written to the plugin manifest.";
      };

      version = lib.mkOption {
        type = lib.types.str;
        default = "0.1.0";
        description = "Plugin version, written to the plugin manifest.";
      };

      defaultEnabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether the plugin is active when no `enabledPlugins` entry decides
          otherwise. Written to the manifest as `defaultEnabled`; any entry in
          user, project or local settings takes precedence over it.
        '';
      };

      skillDirs = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Directories containing <skill>/SKILL.md subdirectories.";
      };

      hooks = lib.mkOption {
        type = lib.types.attrsOf hookTypes.hookType;
        default = { };
        description = "Named hook definitions, rendered to the plugin's hooks/hooks.json.";
      };
    };
  };
in
{
  options.dotfiles.ai.plugins = lib.mkOption {
    type = lib.types.attrsOf pluginType;
    default = { };
    description = ''
      AI assistant plugins, keyed by short name. The on-disk plugin name is the
      key prefixed with `df-`, so `plannotator` installs as `df-plannotator` and
      is referenced in settings as `df-plannotator@skills-dir`.
    '';
  };
}
```

- [ ] **Step 2: Import it from the home entrypoint**

`home/default.nix` currently has:

```nix
  imports = [
    home
    ./profiles.nix
  ]
  ++ programs;
```

Change to:

```nix
  imports = [
    home
    ./profiles.nix
    ./lib/ai/plugins/module.nix
  ]
  ++ programs;
```

It is imported explicitly rather than picked up by the `./programs` scan because it is infrastructure, not a program.

- [ ] **Step 3: Verify the option exists and eval is clean**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: passes. An option-type error (for example a typo in `lib.types`) fails here.

- [ ] **Step 4: Verify the option accepts a declaration**

Temporarily append to `checks/home-eval.nix`, inside the top-level attribute set:

```nix
  dotfiles.ai.plugins.probe = {
    enable = true;
    description = "probe";
  };
```

Run: `nix build .#checks.x86_64-linux.home-eval --no-link`

Expected: passes — proving the submodule accepts a minimal declaration and that `description` is the only required field. Then remove those lines again and re-run to confirm.

- [ ] **Step 5: Format and commit**

```bash
nixfmt home/lib/ai/plugins/module.nix home/default.nix
git add home/lib/ai/plugins/module.nix home/default.nix
git commit -m "home/lib/ai: add dotfiles.ai.plugins options

Single declaration point for assistant plugins; no consumers yet.

Bean: dotfiles-lnd7"
```
