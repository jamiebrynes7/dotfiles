---
# dotfiles-36nb
title: Remove the per-assistant skillsDirs options
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:17:06Z
updated_at: 2026-08-02T12:17:06Z
parent: dotfiles-u1q7
blocked_by:
    - dotfiles-0ivn
    - dotfiles-vjte
---

With every consumer moved to `dotfiles.ai.plugins`, the per-assistant `skillsDirs` options have no remaining setters. Remove them so there is exactly one way to contribute skills — leaving both mechanisms alive would invite new code to pick the wrong one.

**Files:**
- Modify: `home/programs/claude-code/default.nix`, `home/programs/codex/default.nix`, `home/programs/cursor/default.nix`

- [ ] **Step 1: Confirm nothing sets the options any more**

Run: `grep -rn "skillsDirs" home/`

Expected: matches only inside the three module files (their own `mkOption` declaration and their `mkSkillFiles`/`mkPluginFiles` call sites). If any other file still assigns `skillsDirs`, convert it to a plugin before continuing.

- [ ] **Step 2: Remove the option from the claude-code module**

In `home/programs/claude-code/default.nix`, delete the `skillsDirs = mkOption { ... };` block, and delete the now-unused `skills` binding and its `aiSkills` import together with the assertion and `home.file` entry that reference them:

- delete the `aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };` binding
- delete the `skills = aiSkills.mkSkillFiles { ... };` binding
- delete the assertion whose message begins `claude-code: skill name conflicts`
- in `home.file`, drop the `// skills.files` term, leaving `// plugins.files`

Claude Code now receives skills exclusively as plugin content.

- [ ] **Step 3: Remove the option from the codex module**

In `home/programs/codex/default.nix`, delete the `skillsDirs = mkOption { ... };` block and simplify the `skills` binding to use the plugin-derived list only:

```nix
  skills = aiSkills.mkSkillFiles {
    variant = "codex";
    targetDir = ".codex/skills";
    skillsDirs = pluginSkillDirs;
    # Codex follows symlinked skill directories but ignores symlinked SKILL.md
    # files, so symlink the directory itself rather than recreating the tree.
    recursive = false;
  };
```

Keep the existing assertion on `skills.conflicts`: Codex flattens every plugin's skills into one directory, so cross-plugin name collisions are still real failures there.

- [ ] **Step 4: Remove the option from the cursor module**

Apply the same edit to `home/programs/cursor/default.nix`:

```nix
  skills = aiSkills.mkSkillFiles {
    variant = "cursor";
    targetDir = ".cursor/skills";
    skillsDirs = pluginSkillDirs;
  };
```

Keep its `skills.conflicts` assertion for the same reason.

- [ ] **Step 5: Verify eval and compare the file set**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: passes. `cat` the path and confirm the set is unchanged from the previous task — `.claude/skills/df-base`, `.claude/skills/df-plannotator`, `.claude/skills/df-beans`, plus the flattened `.codex/skills/*` and `.cursor/skills/*` entries including `plannotator-user-code-review`.

- [ ] **Step 6: Verify the cross-plugin collision assertion still bites**

Temporarily add a second `skillDirs` entry to `checks/home-eval.nix` that duplicates an existing skill name:

```nix
  dotfiles.ai.plugins.probe = {
    enable = true;
    description = "probe";
    skillDirs = [ ../home/lib/ai/skills ];
  };
```

Run: `nix build .#checks.x86_64-linux.home-eval --no-link`

Expected: FAIL, with the codex or cursor message `skill name conflicts between built-in skills and provided skills: brainstorming, ...`. This confirms the flattened assertion survived the refactor. Remove the probe block and re-run to confirm it passes again.

- [ ] **Step 7: Format and commit**

```bash
nixfmt home/programs/claude-code/default.nix home/programs/codex/default.nix home/programs/cursor/default.nix
git add home/programs/claude-code/default.nix home/programs/codex/default.nix home/programs/cursor/default.nix
git commit -m "home/programs: drop the per-assistant skillsDirs options

dotfiles.ai.plugins is now the only way to contribute skills.

Bean: dotfiles-36nb"
```
