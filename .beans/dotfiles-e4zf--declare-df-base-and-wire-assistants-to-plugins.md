---
# dotfiles-e4zf
title: Declare df-base and wire assistants to plugins
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:17:06Z
updated_at: 2026-08-02T12:17:06Z
parent: dotfiles-u1q7
blocked_by:
    - dotfiles-d7u9
---

Declares the first plugin, `df-base`, and makes all three assistant modules consume `dotfiles.ai.plugins`. Claude Code renders real plugin directories; Codex and Cursor flatten the same `skillDirs` through the existing `mkSkillFiles`.

The per-assistant `skillsDirs` options stay in place and keep working in this task, so `plannotator` and `beans` are unaffected. They are removed once every consumer has moved (later task).

After this lands, `brainstorming` is invoked as `df-base:brainstorming` in Claude Code, and unchanged as `brainstorming` in Codex and Cursor.

**Files:**
- Create: `home/lib/ai/plugins/base.nix` (via `git mv` of the skill-reinforcement hook)
- Delete: `home/programs/claude-code/hooks/skill-reinforcement.nix`
- Modify: `home/default.nix`, `home/programs/claude-code/hooks/default.nix`, `home/programs/claude-code/default.nix`, `home/programs/codex/default.nix`, `home/programs/cursor/default.nix`

- [ ] **Step 1: Move the skill-reinforcement module into the plugin library**

```bash
git mv home/programs/claude-code/hooks/skill-reinforcement.nix home/lib/ai/plugins/base.nix
```

Then rewrite it as the `df-base` declaration. Keep the `script` binding — the whole `pkgs.writeShellScript "skill-reinforcement-hook" '' ... ''` block — exactly as it is; only the header and the trailing attribute set change:

```nix
# The `df-base` plugin: the assistant-agnostic skills from `home/lib/ai/skills`
# plus the hook that reinforces skill activation. Always declared — each assistant
# module decides whether to render it.
{ lib, pkgs, ... }:
let
  aiSkills = import ../skills { inherit lib pkgs; };

  script = pkgs.writeShellScript "skill-reinforcement-hook" ''
    ... unchanged, keep the existing heredoc verbatim ...
  '';
in
{
  dotfiles.ai.plugins.base = {
    enable = true;
    description = "Core assistant skills and the skill-activation reinforcement hook";
    defaultEnabled = true;
    skillDirs = [ aiSkills.builtinSkillsDir ];
    hooks.skill-reinforcement = {
      enable = true;
      event = "UserPromptSubmit";
      hooks = [
        {
          type = "command";
          command = "${script}";
        }
      ];
    };
  };
}
```

The old file gated the hook on `config.dotfiles.programs.claude-code.enable`. That gate is gone because rendering is now what gates it: the claude-code module only emits plugin files when it is enabled.

- [ ] **Step 2: Drop the deleted import and add the new one**

`home/programs/claude-code/hooks/default.nix` becomes:

```nix
{ ... }:
{
  imports = [
    ./debug.nix
  ];
}
```

`home/default.nix` gains `./lib/ai/plugins/base.nix` in `imports`, next to the `./lib/ai/plugins/module.nix` entry added earlier:

```nix
  imports = [
    home
    ./profiles.nix
    ./lib/ai/plugins/module.nix
    ./lib/ai/plugins/base.nix
  ]
  ++ programs;
```

- [ ] **Step 3: Render plugins from the claude-code module**

In `home/programs/claude-code/default.nix`, alongside the existing `aiSkills` binding:

```nix
  aiPlugins = import ../../lib/ai/plugins { inherit lib pkgs; };
  plugins = aiPlugins.mkPluginFiles {
    variant = "cc";
    targetDir = ".claude/skills";
    plugins = config.dotfiles.ai.plugins;
  };
```

In its `config` block, delete this line — `df-base` now owns the built-in skills:

```nix
    dotfiles.programs.claude-code.skillsDirs = [ aiSkills.builtinSkillsDir ];
```

Add a second assertion beside the existing one:

```nix
      {
        assertion = plugins.conflicts == [ ];
        message = "claude-code: skill names defined twice within one plugin: ${builtins.concatStringsSep ", " plugins.conflicts}";
      }
```

And merge the plugin files into `home.file`:

```nix
    home.file = {
      ".claude/CLAUDE.md".source = ../../lib/ai/global-instructions.md;
      ".claude/settings.json".source = settingsJson;
    }
    // skills.files
    // plugins.files;
```

- [ ] **Step 4: Add the enabledPlugins option**

Still in `home/programs/claude-code/default.nix`, add an option beside `skillOverrides`:

```nix
    enabledPlugins = mkOption {
      type = types.attrsOf types.bool;
      default = { };
      description = ''
        Plugin enablement written to settings.json as `enabledPlugins`, keyed by
        `<plugin>@<marketplace>` (for example `df-beans@skills-dir`). Left empty by
        default: each plugin's own `defaultEnabled` carries the global default, and
        per-project overrides belong in that project's settings.
      '';
    };
```

and extend `settingsJson` with a matching `optionalAttrs`, following the `skillOverrides` pattern:

```nix
      // lib.optionalAttrs (cfg.enabledPlugins != { }) {
        inherit (cfg) enabledPlugins;
      }
```

- [ ] **Step 5: Flatten plugin skill dirs for Codex and Cursor**

In `home/programs/codex/default.nix`, change the `skills` binding to append the plugins' skill directories to the module's own list:

```nix
  pluginSkillDirs = lib.concatMap (plugin: plugin.skillDirs) (
    lib.attrValues (lib.filterAttrs (_: plugin: plugin.enable) config.dotfiles.ai.plugins)
  );
  skills = aiSkills.mkSkillFiles {
    variant = "codex";
    targetDir = ".codex/skills";
    skillsDirs = cfg.skillsDirs ++ pluginSkillDirs;
    # Codex follows symlinked skill directories but ignores symlinked SKILL.md
    # files, so symlink the directory itself rather than recreating the tree.
    recursive = false;
  };
```

and delete its `dotfiles.programs.codex.skillsDirs = [ aiSkills.builtinSkillsDir ];` line.

Apply the identical change to `home/programs/cursor/default.nix` with `variant = "cursor"`, `targetDir = ".cursor/skills"`, no `recursive` argument, and delete its `dotfiles.programs.cursor.skillsDirs = [ aiSkills.builtinSkillsDir ];` line.

- [ ] **Step 6: Verify eval and inspect the rendered file set**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: passes. `cat` the resulting path and confirm it contains `.claude/skills/df-base` and no longer contains `.claude/skills/brainstorming`, while `.codex/skills/brainstorming` and `.cursor/skills/brainstorming` are still present.

- [ ] **Step 7: Build the rendered plugin and validate it**

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
  hm.config.home.file.".claude/skills/df-base".source'
```

Then, with that store path as `$P`:

```bash
HOME=$(mktemp -d) claude plugin validate $P
cat $P/hooks/hooks.json
```

Expected: validation passes, and `hooks.json` contains a `UserPromptSubmit` entry whose command points at the `skill-reinforcement-hook` store path.

- [ ] **Step 8: Confirm discovery end to end**

```bash
T=$(mktemp -d); mkdir -p $T/.claude/skills
cp -r $P $T/.claude/skills/df-base
HOME=$T claude plugin list
```

Expected: `df-base@skills-dir` listed with `Status: ✔ loaded` (its `defaultEnabled` is `true`). `HOME=$T claude plugin details df-base@skills-dir` should report 10 skills and 1 hook.

- [ ] **Step 9: Format and commit**

```bash
nixfmt home/lib/ai/plugins/base.nix home/default.nix home/programs/claude-code/default.nix home/programs/claude-code/hooks/default.nix home/programs/codex/default.nix home/programs/cursor/default.nix
git add -A home/
git commit -m "home: render built-in skills as the df-base plugin

Claude Code now loads them as df-base@skills-dir with the skill-reinforcement
hook bundled in; codex and cursor flatten the same declaration into loose
skills as before.

Bean: dotfiles-e4zf"
```
