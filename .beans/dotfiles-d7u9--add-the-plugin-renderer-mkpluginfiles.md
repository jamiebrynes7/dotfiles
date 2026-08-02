---
# dotfiles-d7u9
title: Add the plugin renderer (mkPluginFiles)
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:14:11Z
updated_at: 2026-08-02T12:14:11Z
parent: dotfiles-jali
blocked_by:
    - dotfiles-lnd7
---

The renderer: turns a `dotfiles.ai.plugins` declaration into a Claude Code skills-directory plugin directory. Mirrors `home/lib/ai/skills/default.nix`, reusing the same `process-frontmatter` tool for variant filtering and the same skill-discovery helper.

Layout produced per plugin (verified against Claude Code 2.1.220):

```
df-<name>/
  .claude-plugin/plugin.json
  skills/<skill>/SKILL.md       + any supporting files
  hooks/hooks.json              only when hooks are declared
```

**Files:**
- Create: `home/lib/ai/plugins/default.nix`
- Modify: `home/lib/ai/skills/default.nix` (export the existing private `readSkillDir`)

- [ ] **Step 1: Export `readSkillDir` from the skills library**

`home/lib/ai/skills/default.nix` defines `readSkillDir` in its `let` block. Leave the definition alone and add it to the returned attribute set, next to `builtinSkillsDir`:

```nix
{
  # Path to the built-in skills directory, for consumers to include in skillsDirs.
  builtinSkillsDir = ./.;

  # Exported so the plugin renderer discovers skills the same way.
  inherit readSkillDir;
```

- [ ] **Step 2: Write the renderer**

`home/lib/ai/plugins/default.nix`:

```nix
# Renders `dotfiles.ai.plugins` declarations into Claude Code skills-directory
# plugins. A plugin folder under ~/.claude/skills containing
# `.claude-plugin/plugin.json` is discovered in place as `<name>@skills-dir`, with
# no marketplace and no install step.
{ lib, pkgs }:
let
  inherit (import ../tools { inherit pkgs; }) processFrontmatter;
  inherit (import ../skills { inherit lib pkgs; }) readSkillDir;

  hookTypes = import ./hook-types.nix { inherit lib; };

  # `claude plugin validate` warns when a manifest has no author.
  pluginAuthor = {
    name = "Jamie Brynes";
  };

  # On-disk plugin names are prefixed so they cannot collide with plugins from
  # any marketplace. Applied once, here, so the directory name and the
  # `<name>@skills-dir` id used in settings can never drift apart.
  prefix = name: "df-${name}";

  # Merge one plugin's skillDirs into { skills, conflicts }. Conflicts are names
  # defined in more than one of that plugin's directories.
  collectSkills =
    skillDirs:
    builtins.foldl'
      (
        acc: dir:
        let
          dirSkills = readSkillDir dir;
          newConflicts = builtins.filter (name: builtins.hasAttr name acc.skills) (
            builtins.attrNames dirSkills
          );
        in
        {
          skills = acc.skills // dirSkills;
          conflicts = acc.conflicts ++ newConflicts;
        }
      )
      {
        skills = { };
        conflicts = [ ];
      }
      skillDirs;

  mkPlugin =
    variant: name: plugin:
    let
      manifest = pkgs.writeText "plugin.json" (
        builtins.toJSON {
          name = prefix name;
          author = pluginAuthor;
          inherit (plugin) version description defaultEnabled;
        }
      );

      mergedHooks = hookTypes.mergeHooks plugin.hooks;
      hooksJson = pkgs.writeText "hooks.json" (builtins.toJSON { hooks = mergedHooks; });

      # Copy the whole skill directory, then overwrite SKILL.md with the
      # variant-filtered version — the same shape as `processSkill` in the skills
      # library, so supporting files (references/, scripts/) come along.
      copySkill = skillName: path: ''
        mkdir -p $out/skills/${skillName}
        cp -r ${path}/. $out/skills/${skillName}/
        chmod -R u+w $out/skills/${skillName}
        ${processFrontmatter}/bin/process-frontmatter ${variant} ${path}/SKILL.md \
          > $out/skills/${skillName}/SKILL.md
      '';
    in
    pkgs.runCommand "plugin-${variant}-${prefix name}" { } ''
      mkdir -p $out/.claude-plugin
      cp ${manifest} $out/.claude-plugin/plugin.json
      ${lib.concatStrings (lib.mapAttrsToList copySkill (collectSkills plugin.skillDirs).skills)}
      ${lib.optionalString (mergedHooks != { }) ''
        mkdir -p $out/hooks
        cp ${hooksJson} $out/hooks/hooks.json
      ''}
    '';
in
{
  # Build plugin directories for home.file.
  #
  # Arguments:
  #   variant: frontmatter variant to keep ("cc", "cursor", or "codex")
  #   targetDir: directory relative to home (e.g. ".claude/skills")
  #   plugins: the `dotfiles.ai.plugins` attrset
  #
  # Returns:
  #   files: attrset for home.file
  #   conflicts: "<plugin>:<skill>" strings for skill names defined twice within
  #     one plugin (for assertions). Collisions *between* plugins are harmless —
  #     Claude Code namespaces plugin skills as `<plugin>:<skill>`.
  mkPluginFiles =
    {
      variant,
      targetDir,
      plugins,
    }:
    let
      enabled = lib.filterAttrs (_: plugin: plugin.enable) plugins;
    in
    {
      files = lib.mapAttrs' (
        name: plugin:
        lib.nameValuePair "${targetDir}/${prefix name}" {
          source = mkPlugin variant name plugin;
          recursive = true;
        }
      ) enabled;

      conflicts = lib.concatLists (
        lib.mapAttrsToList (
          name: plugin: map (skill: "${name}:${skill}") (collectSkills plugin.skillDirs).conflicts
        ) enabled
      );
    };
}
```

- [ ] **Step 3: Build a plugin from the renderer directly**

Nothing declares a plugin yet, so exercise the renderer standalone. Run from the repository root:

```bash
nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    plugins = import ./home/lib/ai/plugins/default.nix { inherit (pkgs) lib; inherit pkgs; };
  in
  (plugins.mkPluginFiles {
    variant = "cc";
    targetDir = ".claude/skills";
    plugins.probe = {
      enable = true;
      description = "probe";
      version = "0.1.0";
      defaultEnabled = false;
      skillDirs = [ ./home/lib/ai/skills ];
      hooks = { };
    };
  }).files.".claude/skills/df-probe".source'
```

Expected: a store path. Inspect it:

```bash
ls $(!!)/.claude-plugin $(!!)/skills
```

Expected: `plugin.json` in the first, and the ten skill directories (`brainstorming`, `coding-effectively`, …) in the second. No `hooks/` directory, since no hooks were declared.

- [ ] **Step 4: Validate the built plugin with Claude Code**

Using the store path from the previous step as `$P`:

```bash
HOME=$(mktemp -d) claude plugin validate $P
```

Expected: `✔ Validation passed` with no warnings (the `author` field suppresses the only warning the CLI emits for a minimal manifest).

- [ ] **Step 5: Verify frontmatter filtering actually ran**

```bash
head -20 $P/skills/comment-cleanup/SKILL.md
```

Expected: the frontmatter contains no `cc:`, `cursor:` or `codex:` prefixed keys — `process-frontmatter` strips the non-matching ones and unprefixes the rest.

- [ ] **Step 6: Verify hooks render when declared**

Re-run the Step 3 command with `hooks` replaced by:

```nix
      hooks.probe-hook = {
        enable = true;
        event = "SessionStart";
        matcher = null;
        hooks = [
          {
            type = "command";
            command = "/bin/true";
            timeout = null;
          }
        ];
      };
```

Then: `cat $P/hooks/hooks.json`

Expected: `{"hooks":{"SessionStart":[{"hooks":[{"command":"/bin/true","type":"command"}]}]}}` — the same shape the claude-code module writes into `settings.json` today.

- [ ] **Step 7: Verify eval of the whole config is still clean**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link`

Expected: passes. Nothing consumes the renderer yet, so this only proves the `readSkillDir` export did not break the skills library.

- [ ] **Step 8: Format and commit**

```bash
nixfmt home/lib/ai/plugins/default.nix home/lib/ai/skills/default.nix
git add home/lib/ai/plugins/default.nix home/lib/ai/skills/default.nix
git commit -m "home/lib/ai: add plugin renderer

mkPluginFiles builds one skills-directory plugin per declaration, with a
manifest, variant-filtered skills and optional hooks.json.

Bean: dotfiles-d7u9"
```
