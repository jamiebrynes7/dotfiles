---
# dotfiles-vjte
title: Convert beans prime hooks to the df-beans plugin
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:17:06Z
updated_at: 2026-08-02T12:17:06Z
parent: dotfiles-u1q7
blocked_by:
    - dotfiles-e4zf
---

Moves the beans `SessionStart`/`PreCompact` prime hooks into a `df-beans` plugin with `defaultEnabled = false`. This is the change the whole epic exists for: today those hooks fire in every project regardless of whether it has a beans database; afterwards they fire only where the plugin is switched on.

The `Bash(beans *)` permission entry stays on the module — plugins cannot carry a permission allowlist, and the entry is inert when the plugin is off.

`task-implementer` and `whats-next` stay in this repository's `.claude/skills/` for now. `whats-next` hands off to `task-implementer`, so shipping one without the other would break that handoff in other repositories. They move once `task-implementer` is generalised (follow-up bean).

**Files:**
- Modify: `home/programs/beans.nix`

- [ ] **Step 1: Replace the hook wiring with a plugin declaration**

Delete the whole `dotfiles.programs.claude-code.hooks = lib.mkIf cfg.enableClaudeCodeIntegration { ... };` block and put this in its place:

```nix
    dotfiles.ai.plugins.beans = lib.mkIf cfg.enableClaudeCodeIntegration {
      enable = true;
      description = "Primes sessions with the beans issue-tracker workflow";
      # Off unless a project opts in: these hooks are only useful in a repository
      # that actually has a beans database.
      defaultEnabled = false;
      hooks = {
        beans-prime-session-start = {
          enable = true;
          event = "SessionStart";
          hooks = [
            {
              type = "command";
              command = "${pkgs.dotfiles.beans}/bin/beans prime";
            }
          ];
        };
        beans-prime-pre-compact = {
          enable = true;
          event = "PreCompact";
          hooks = [
            {
              type = "command";
              command = "${pkgs.dotfiles.beans}/bin/beans prime";
            }
          ];
        };
      };
    };
```

Leave the `dotfiles.programs.claude-code.permissions.allow` block untouched.

- [ ] **Step 2: Verify eval**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: passes, and the printed file list contains `.claude/skills/df-beans`.

- [ ] **Step 3: Verify the hooks left settings.json**

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
  hm.config.home.file.".claude/settings.json".source'
```

Then: `jq '.hooks | keys' $(that path)`

Expected: no `SessionStart` or `PreCompact` entries remain from beans. `jq '.permissions.allow' ...` should still list `"Bash(beans *)"`.

- [ ] **Step 4: Verify the plugin is off by default and can be switched on**

Build the plugin path the same way (`hm.config.home.file.".claude/skills/df-beans".source`), then with it as `$P`:

```bash
T=$(mktemp -d); mkdir -p $T/.claude/skills
cp -r $P $T/.claude/skills/df-beans
HOME=$T claude plugin list
```

Expected: `df-beans@skills-dir` with `Status: ✘ disabled`.

```bash
echo '{ "enabledPlugins": { "df-beans@skills-dir": true } }' > $T/.claude/settings.json
HOME=$T claude plugin list
```

Expected: the same plugin now reports `Status: ✔ loaded`. This is the per-project switch the epic is built around.

- [ ] **Step 5: Format and commit**

```bash
nixfmt home/programs/beans.nix
git add home/programs/beans.nix
git commit -m "home/programs/beans: ship prime hooks as the df-beans plugin

Off by default, so beans priming only runs in projects that opt in rather
than in every session.

Bean: dotfiles-vjte"
```
