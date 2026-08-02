---
# dotfiles-0ivn
title: Convert plannotator to the df-plannotator plugin
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:17:06Z
updated_at: 2026-08-02T12:17:06Z
parent: dotfiles-u1q7
blocked_by:
    - dotfiles-e4zf
---

Converts plannotator from two hand-wired entries (a `skillsDirs` append plus a `hooks` append on the claude-code module) into a single `dotfiles.ai.plugins.plannotator` declaration.

Its Codex hook stays where it is: the two assistants fire plannotator on different events (`PermissionRequest`/`ExitPlanMode` for Claude Code, `Stop` for Codex), so it is not shared plugin content under this design.

**Files:**
- Modify: `home/programs/plannotator/default.nix`

- [ ] **Step 1: Declare the plugin in the shared branch**

`config` is a `lib.mkMerge` of three branches. The plugin's skill is wanted whenever either assistant is on, so declare it in the first (shared) branch alongside the package and config file:

```nix
    (lib.mkIf (cfg.claude-code.enable || cfg.codex.enable) {
      home.packages = [ plannotatorWrapper ];
      home.file.".plannotator/config.json".source = configJson;

      dotfiles.ai.plugins.plannotator = {
        enable = true;
        description = "Plan and code review gates via plannotator";
        defaultEnabled = true;
        skillDirs = [ ./skills ];
      };
    })
```

- [ ] **Step 2: Move each assistant's hook onto its own surface**

Replace the `claude-code` branch:

```nix
    (lib.mkIf cfg.claude-code.enable {
      dotfiles.programs.claude-code.skillsDirs = [ ./skills ];
      dotfiles.programs.claude-code.hooks.plannotator-review =
        plannotatorHook "PermissionRequest" "ExitPlanMode";
    })
```

with a branch that contributes only the hook, into the plugin declared in Step 1:

```nix
    (lib.mkIf cfg.claude-code.enable {
      dotfiles.ai.plugins.plannotator.hooks.plannotator-review =
        plannotatorHook "PermissionRequest" "ExitPlanMode";
    })
```

`plannotatorHook` already returns exactly the shape `hooks` expects (`{ enable, event, matcher, hooks }`), so it is reused unchanged, and `mkMerge` combines this branch's `hooks` with Step 1's `skillDirs`.

In the `codex` branch, delete only this line — the skill now reaches Codex through the flattened plugin `skillDirs` wired up in the previous task:

```nix
      dotfiles.programs.codex.skillsDirs = [ ./skills ];
```

Its hook stays module-level and unchanged:

```nix
      dotfiles.programs.codex.hooks.plannotator-review = plannotatorHook "Stop" null;
```

Update the comment above `plannotatorHook` to say that the Claude Code hook now ships inside the plugin while the Codex one stays on the module, because the events differ.

- [ ] **Step 3: Verify eval**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: passes. `cat` the path and confirm `.claude/skills/df-plannotator` is present and `.claude/skills/plannotator-user-code-review` is gone, while `.codex/skills/plannotator-user-code-review` remains.

- [ ] **Step 4: Validate the rendered plugin**

```bash
nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (toString ./.);
    hm = flake.lib.mkHomeManagerSystem {
      system = "x86_64-linux";
      user = "check";
      directory = "/home/check";
      home = ./checks/home-eval.nix;
    };
  in
  hm.config.home.file.".claude/skills/df-plannotator".source'
```

With that path as `$P`:

```bash
HOME=$(mktemp -d) claude plugin validate $P
cat $P/hooks/hooks.json
```

Expected: validation passes; `hooks.json` has a `PermissionRequest` entry with `"matcher":"ExitPlanMode"`, a command ending in `/bin/plannotator`, and `"timeout":345600`.

- [ ] **Step 5: Confirm the skill is namespaced as expected**

```bash
T=$(mktemp -d); mkdir -p $T/.claude/skills
cp -r $P $T/.claude/skills/df-plannotator
HOME=$T claude plugin details df-plannotator@skills-dir
```

Expected: `Skills (1)  plannotator-user-code-review` and `Hooks (1)`. In a real session it is invoked as `df-plannotator:plannotator-user-code-review`.

- [ ] **Step 6: Format and commit**

```bash
nixfmt home/programs/plannotator/default.nix
git add home/programs/plannotator/default.nix
git commit -m "home/programs/plannotator: ship as the df-plannotator plugin

Replaces the separate skillsDirs and hooks wiring with one plugin
declaration. The codex hook stays module-level; its event differs.

Bean: dotfiles-0ivn"
```
