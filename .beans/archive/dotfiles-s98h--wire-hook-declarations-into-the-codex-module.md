---
# dotfiles-s98h
title: Wire hook declarations into the codex module
status: completed
type: task
priority: normal
created_at: 2026-06-04T12:57:43Z
updated_at: 2026-06-04T13:09:58Z
parent: dotfiles-5gsf
blocked_by:
    - dotfiles-rzxu
    - dotfiles-aa5a
---

Consume the new types: rename the bool `hooks` option to `enableHooks`, add a `hooks` attrset of named hook definitions, render ~/.codex/hooks.json from them (only when non-empty), and assert that declaring hooks requires `enableHooks = true`. All edits are in `home/programs/codex/default.nix`.

**Files:**
- Modify: `home/programs/codex/default.nix`

- [x] **Step 1: Import the types and wire the merge into the `let` block**

Find:

```nix
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.hooks;
  };
```

Replace with:

```nix
  hookTypes = import ./hooks/types.nix { inherit lib; };
  mergedHooks = hookTypes.mergeHooks cfg.hooks;
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.enableHooks;
  };
```

- [x] **Step 2: Rename the bool option and add the `hooks` attrset option**

Find:

```nix
    hooks = mkOption {
      type = types.bool;
      default = true;
      description =
        "Enable Codex lifecycle hooks ([features].hooks) via the dotfiles profile overlay.";
    };
```

Replace with:

```nix
    enableHooks = mkOption {
      type = types.bool;
      default = true;
      description =
        "Enable Codex lifecycle hooks ([features].hooks) via the dotfiles profile overlay.";
    };
    hooks = mkOption {
      type = types.attrsOf hookTypes.hookType;
      default = { };
      description =
        "Named Codex hook definitions rendered to ~/.codex/hooks.json.";
    };
```

- [x] **Step 3: Add the declared-but-disabled assertion**

Find the existing single-element assertions list:

```nix
    assertions = [{
      assertion = skills.conflicts == [ ];
      message =
        "codex: skill name conflicts between built-in skills and provided skills: ${
          builtins.concatStringsSep ", " skills.conflicts
        }";
    }];
```

Replace with:

```nix
    assertions = [
      {
        assertion = skills.conflicts == [ ];
        message =
          "codex: skill name conflicts between built-in skills and provided skills: ${
            builtins.concatStringsSep ", " skills.conflicts
          }";
      }
      {
        assertion = cfg.hooks == { } || cfg.enableHooks;
        message =
          "codex: hooks are declared but dotfiles.programs.codex.enableHooks is false; they will never fire.";
      }
    ];
```

- [x] **Step 4: Render ~/.codex/hooks.json when any hook is enabled**

Find:

```nix
    home.file = skills.files // {
      ".codex/AGENTS.md".source = ../../lib/ai/global-instructions.md;
      ".codex/dotfiles.config.toml".source = codexConfig;
    };
```

Replace with:

```nix
    home.file = skills.files // {
      ".codex/AGENTS.md".source = ../../lib/ai/global-instructions.md;
      ".codex/dotfiles.config.toml".source = codexConfig;
    } // lib.optionalAttrs (mergedHooks != { }) {
      ".codex/hooks.json".source = pkgs.writeText "codex-hooks.json"
        (builtins.toJSON { hooks = mergedHooks; });
    };
```

- [x] **Step 5: Format**

Run: `nixfmt home/programs/codex/default.nix`

- [x] **Step 6: Validate**

Run: `nix flake check`
Expected: PASS. With no hooks declared in-repo, `cfg.hooks` defaults to `{}`, so `mergedHooks == {}`, no hooks.json is written, and the assertion holds.

- [x] **Step 7: Commit**

```bash
git add home/programs/codex/default.nix
git commit -m "home/programs/codex: declare hooks and render hooks.json

Rename the bool hooks option to enableHooks and add a hooks attrset of
named declarations rendered to ~/.codex/hooks.json (only when non-empty).
Assert declared hooks require enableHooks=true.

Bean: <this-task-id>"
```

## Summary of Changes

Wired hook declarations into home/programs/codex/default.nix: imported the local hook types, renamed the bool hooks option to enableHooks (still feeding [features].hooks), added a hooks attrset of named definitions, and rendered ~/.codex/hooks.json from mergeHooks only when at least one hook is enabled. Per user review, the declared-but-disabled guard is a non-fatal home-manager warning rather than a hard assertion. Verified the mergeHooks output shape via nix eval; nix flake check passes.
