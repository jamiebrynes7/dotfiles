# Renders dotfiles.programs.paseo.repoSkills (skill -> repositories) into one Claude
# Code plugin per repository, plus the config the repo-skills Paseo plugin reads to
# map a repository key to its plugin. Library code, not a module: the paseo module
# wires it into home.file, and the flake check renders a fixture through it directly.
{ lib, pkgs }:
let
  aiSkills = import ../ai/skills { inherit lib pkgs; };

  # The plugin matches git remotes normalised to this form: lowercase host with no
  # user or port, then owner and repo with no trailing `.git`. A key in any other
  # shape (a pasted clone URL, say) could never match, so it is rejected at eval.
  isNormalisedKey =
    key:
    builtins.match "[a-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+" key != null
    && !(lib.hasSuffix ".git" key);

  # `github.com/samsara-dev/backend` -> `samsara-dev-backend`. Only meaningful for a
  # normalised key.
  pluginName =
    key:
    let
      parts = lib.splitString "/" key;
    in
    "${builtins.elemAt parts 1}-${builtins.elemAt parts 2}";

  # skills: <skill> -> source directory
  mkPlugin =
    name: key: skills:
    let
      manifest = pkgs.writeText "${name}-plugin.json" (
        builtins.toJSON {
          inherit name;
          version = "1.0.0";
          description = "Repository skills for ${key}, declared in dotfiles.programs.paseo.repoSkills.";
          author.name = "dotfiles";
        }
      );
    in
    pkgs.runCommand "paseo-repo-skills-${name}" { } ''
      mkdir -p $out/.claude-plugin $out/skills
      cp ${manifest} $out/.claude-plugin/plugin.json
      ${lib.concatStrings (
        lib.mapAttrsToList (skill: source: ''
          cp -r ${aiSkills.processSkill "cc" skill source} "$out/skills/${skill}"
        '') skills
      )}
    '';
in
{
  # Arguments:
  #   repoSkills: the option value, <skill> -> { source, repositories }
  #   dataDir: absolute directory the plugins are linked under
  #
  # Returns: {
  #   plugins: <plugin name> -> plugin derivation, to link at "${dataDir}/<name>"
  #   config: the config.json contents, repository key -> stable plugin path
  #   errors: messages for assertions; the rest is only meaningful when empty
  # }
  render =
    { repoSkills, dataDir }:
    let
      keys = lib.unique (lib.concatMap (skill: skill.repositories) (lib.attrValues repoSkills));
      badKeys = lib.filter (key: !isNormalisedKey key) keys;
      goodKeys = lib.filter isNormalisedKey keys;

      skillsFor =
        key: lib.mapAttrs (_: s: s.source) (lib.filterAttrs (_: s: lib.elem key s.repositories) repoSkills);

      keysByName = lib.groupBy pluginName goodKeys;
      # Case-folded, since owner/repo keep their case and the plugins are linked side
      # by side on what may be a case-insensitive filesystem (macOS by default).
      collisions = lib.filterAttrs (_: ks: lib.length ks > 1) (
        lib.groupBy (key: lib.toLower (pluginName key)) goodKeys
      );

      # The name is the `<plugin>:<skill>` identifier and a path in a build script,
      # so it is held to Claude Code's own skill-name rule.
      badSkills = lib.filter (skill: builtins.match "[a-z0-9-]{1,64}" skill == null) (
        lib.attrNames repoSkills
      );
      missingSkillMd = lib.attrNames (
        lib.filterAttrs (_: s: !builtins.pathExists (s.source + "/SKILL.md")) repoSkills
      );
    in
    {
      plugins = lib.mapAttrs (
        name: ks:
        let
          key = lib.head ks;
        in
        mkPlugin name key (skillsFor key)
      ) keysByName;

      config = {
        version = 1;
        repositories = lib.genAttrs goodKeys (key: "${dataDir}/${pluginName key}");
      };

      errors =
        map (
          key:
          "dotfiles.programs.paseo.repoSkills: repository key \"${key}\" is not normalised host/owner/repo (e.g. github.com/owner/repo, no scheme, user, port or .git)."
        ) badKeys
        ++ map (
          skill:
          "dotfiles.programs.paseo.repoSkills: skill name \"${skill}\" must be 1-64 lowercase letters, digits or hyphens."
        ) badSkills
        ++ map (skill: "dotfiles.programs.paseo.repoSkills.${skill}.source has no SKILL.md.") missingSkillMd
        ++ lib.mapAttrsToList (
          name: ks:
          "dotfiles.programs.paseo.repoSkills: repository keys ${
            lib.concatMapStringsSep " and " (k: "\"${k}\"") ks
          } produce the same plugin name \"${name}\" (compared case-insensitively)."
        ) collisions;
    };
}
