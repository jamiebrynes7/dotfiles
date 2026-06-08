---
# dotfiles-3eue
title: Create top-level plannotator module and remove the claude-code one
status: completed
type: task
priority: normal
created_at: 2026-06-04T12:58:09Z
updated_at: 2026-06-04T13:12:18Z
parent: dotfiles-bvj4
blocked_by:
    - dotfiles-s98h
---

Invert plannotator into one shared module and delete the claude-code-specific one. Done as a single commit so there is never an intermediate state where two modules both contribute the plannotator skill/hook (which would trip the skills-conflict assertion). Depends on the codex `hooks` attrset option existing.

**Files:**
- Move: `home/programs/claude-code/plannotator/skills/` -> `home/programs/plannotator/skills/`
- Create: `home/programs/plannotator/default.nix`
- Delete: `home/programs/claude-code/plannotator/default.nix`
- Modify: `home/programs/claude-code/default.nix` (drop `./plannotator` from imports)

- [x] **Step 1: Move the skill directory under the new module**

```bash
mkdir -p home/programs/plannotator
git mv home/programs/claude-code/plannotator/skills home/programs/plannotator/skills
```

- [x] **Step 2: Create the top-level module**

`home/programs/plannotator/default.nix`:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.dotfiles.programs.plannotator;

  plannotatorWrapper = pkgs.writeShellScriptBin "plannotator" ''
    ${lib.optionalString cfg.remote "export PLANNOTATOR_REMOTE=1"}
    ${lib.optionalString (cfg.port != null)
    "export PLANNOTATOR_PORT=${toString cfg.port}"}
    exec ${pkgs.dotfiles.plannotator}/bin/plannotator "$@"
  '';

  # Plannotator is one tool; only the plan-review hook event differs per
  # assistant (claude-code fires on the ExitPlanMode permission prompt; codex
  # fires on Stop). The command references the wrapper by store path so neither
  # assistant depends on the other being enabled.
  plannotatorHook = event: matcher: {
    enable = true;
    inherit event matcher;
    hooks = [{
      type = "command";
      command = "${plannotatorWrapper}/bin/plannotator";
      timeout = 345600;
    }];
  };
in {
  options.dotfiles.programs.plannotator = {
    remote = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Enable plannotator remote mode (sets PLANNOTATOR_REMOTE=1)";
    };
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Port for plannotator remote mode (sets PLANNOTATOR_PORT)";
    };
    claude-code.enable = lib.mkEnableOption "plannotator for claude-code";
    codex.enable = lib.mkEnableOption "plannotator for codex";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.claude-code.enable || cfg.codex.enable) {
      home.packages = [ plannotatorWrapper ];
    })
    (lib.mkIf cfg.claude-code.enable {
      dotfiles.programs.claude-code.skillsDirs = [ ./skills ];
      dotfiles.programs.claude-code.hooks.plannotator-review =
        plannotatorHook "PermissionRequest" "ExitPlanMode";
    })
    (lib.mkIf cfg.codex.enable {
      dotfiles.programs.codex.skillsDirs = [ ./skills ];
      dotfiles.programs.codex.hooks.plannotator-review =
        plannotatorHook "Stop" null;
    })
  ];
}
```

- [x] **Step 3: Delete the old claude-code plannotator module**

```bash
git rm home/programs/claude-code/plannotator/default.nix
```

(The directory is now empty and removed by git.)

- [x] **Step 4: Drop it from claude-code's imports**

In `home/programs/claude-code/default.nix`, change:

```nix
  imports = [ ./hooks ./plannotator ./cship ];
```

to:

```nix
  imports = [ ./hooks ./cship ];
```

- [x] **Step 5: Format**

Run: `nixfmt home/programs/plannotator/default.nix home/programs/claude-code/default.nix`

- [x] **Step 6: Validate**

Run: `nix flake check`
Expected: PASS. Nothing in-repo enables plannotator (it is enabled downstream), so both assistant toggles default off; the module just defines options. The moved skill is no longer contributed twice.

- [x] **Step 7: Commit (note the breaking migration in the body)**

```bash
git add -A home/programs/plannotator home/programs/claude-code
git commit -m "home/programs/plannotator: invert into one top-level module

Move plannotator out of claude-code into a shared module exposing
dotfiles.programs.plannotator.{remote,port,claude-code.enable,codex.enable}.
It injects the plan-review hook per enabled assistant (claude-code:
PermissionRequest/ExitPlanMode; codex: Stop) and owns the wrapper and the
plannotator-user-code-review skill.

BREAKING (downstream repos): dotfiles.programs.claude-code.plannotator.{enable,
remote,port} -> dotfiles.programs.plannotator.{claude-code.enable,remote,port};
enable codex via dotfiles.programs.plannotator.codex.enable. No alias provided.

Bean: <this-task-id>"
```

## Summary of Changes

Inverted plannotator into a single top-level module home/programs/plannotator/default.nix exposing dotfiles.programs.plannotator.{remote,port,claude-code.enable,codex.enable}. It owns the remote/port-aware wrapper, the plannotator package, and the plannotator-user-code-review skill (moved here from claude-code), and injects the plan-review hook per enabled assistant: claude-code on PermissionRequest/ExitPlanMode, codex on Stop (timeout 345600). Removed home/programs/claude-code/plannotator/ and dropped it from claude-code imports. No stale references remain; nix flake check passes.

BREAKING (downstream repos): dotfiles.programs.claude-code.plannotator.{enable,remote,port} becomes dotfiles.programs.plannotator.{claude-code.enable,remote,port}; enable codex via dotfiles.programs.plannotator.codex.enable. No alias provided.
