# Renders dotfiles.programs.paseo.repoProfiles (repository -> profile) into the files
# the repo-profiles Paseo plugin hands to Claude agents, plus the config it reads to
# map a repository key to them. Library code, not a module: the paseo module wires it
# into xdg files, and the flake check renders a fixture through it directly.
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
  profileName =
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
          description = "Repository skills for ${key}, declared in dotfiles.programs.paseo.repoProfiles.";
          author.name = "dotfiles";
        }
      );
    in
    pkgs.runCommand "paseo-repo-profiles-${name}" { } ''
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
  # The option's type, shared with the flake check so it can evaluate how
  # declarations from several modules merge.
  profilesType = lib.types.attrsOf (
    lib.types.submodule {
      options.skills = lib.mkOption {
        # types.path merges only equal values, so two modules giving one repository
        # the same skill name with different sources conflict at eval.
        type = lib.types.attrsOf lib.types.path;
        default = { };
        description = "Skill name -> directory containing the skill's `SKILL.md`.";
      };
    }
  );

  # Arguments:
  #   repoProfiles: the option value, <repository key> -> { skills }
  #   dataDir: absolute directory the links are installed under
  #
  # Returns: {
  #   links: <path relative to dataDir> -> store path to link there
  #   config: the config.json contents, repository key -> profile of stable paths
  #   errors: messages for assertions; the rest is only meaningful when empty
  # }
  render =
    { repoProfiles, dataDir }:
    let
      keys = lib.attrNames repoProfiles;
      badKeys = lib.filter (key: !isNormalisedKey key) keys;
      goodKeys = lib.filter isNormalisedKey keys;
      withSkills = lib.filter (key: repoProfiles.${key}.skills != { }) goodKeys;

      # Case-folded, since owner/repo keep their case and the links sit side by
      # side on what may be a case-insensitive filesystem (macOS by default). Over
      # every key, empty profiles included, so adding to a profile later can't
      # introduce a collision.
      collisions = lib.filterAttrs (_: ks: lib.length ks > 1) (
        lib.groupBy (key: lib.toLower (profileName key)) goodKeys
      );

      skillEntries = lib.concatMap (
        key: lib.mapAttrsToList (skill: source: { inherit key skill source; }) repoProfiles.${key}.skills
      ) keys;
      # The name is the `<plugin>:<skill>` identifier and a path in a build script,
      # so it is held to Claude Code's own skill-name rule.
      badSkills = lib.unique (
        map (e: e.skill) (lib.filter (e: builtins.match "[a-z0-9-]{1,64}" e.skill == null) skillEntries)
      );
      missingSkillMd = lib.filter (e: !builtins.pathExists (e.source + "/SKILL.md")) skillEntries;

      pluginPath = key: "${profileName key}/plugin";
    in
    {
      links = lib.listToAttrs (
        map (
          key: lib.nameValuePair (pluginPath key) (mkPlugin (profileName key) key repoProfiles.${key}.skills)
        ) withSkills
      );

      config = {
        version = 1;
        # Only profiles with something to load: the plugin takes the first key a
        # checkout's remotes match, so an empty profile listed here would shadow a
        # real one matched by a later remote.
        repositories = lib.genAttrs withSkills (key: {
          pluginDir = "${dataDir}/${pluginPath key}";
        });
      };

      errors =
        map (
          key:
          "dotfiles.programs.paseo.repoProfiles: repository key \"${key}\" is not normalised host/owner/repo (e.g. github.com/owner/repo, no scheme, user, port or .git)."
        ) badKeys
        ++ map (
          skill:
          "dotfiles.programs.paseo.repoProfiles: skill name \"${skill}\" must be 1-64 lowercase letters, digits or hyphens."
        ) badSkills
        ++ map (
          e: "dotfiles.programs.paseo.repoProfiles.\"${e.key}\".skills.${e.skill} has no SKILL.md."
        ) missingSkillMd
        ++ lib.mapAttrsToList (
          name: ks:
          "dotfiles.programs.paseo.repoProfiles: repository keys ${
            lib.concatMapStringsSep " and " (k: "\"${k}\"") ks
          } produce the same profile name \"${name}\" (compared case-insensitively)."
        ) collisions;
    };
}
