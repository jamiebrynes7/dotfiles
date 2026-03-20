# Shared utilities for AI assistant skill file management.
# Used by claude-code and cursor modules.
{ lib, pkgs }:
let
  inherit (import ../tools { inherit pkgs; }) processFrontmatter;

  # Read skill subdirectories from a directory, returning an attrset of name -> path.
  # A valid skill is a subdirectory containing a SKILL.md file.
  readSkillDir = dir:
    let entries = builtins.readDir dir;
    in lib.mapAttrs (name: _: dir + "/${name}") (lib.filterAttrs (name: type:
      type == "directory" && builtins.pathExists (dir + "/${name}/SKILL.md"))
      entries);
in {
  # Path to the built-in skills directory, for consumers to include in skillsDirs.
  builtinSkillsDir = ./.;

  # Build skill files for home.file, checking for conflicts.
  #
  # Arguments:
  #   variant: Target variant ("cc" or "cursor") for frontmatter filtering
  #   targetDir: Target directory relative to home (e.g., ".claude/skills")
  #   skillsDirs: List of paths to skill directories
  #
  # Returns: {
  #   files: Attribute set suitable for home.file
  #   conflicts: List of conflicting skill names (for assertions)
  # }
  mkSkillFiles = { variant, targetDir, skillsDirs }:
    let
      merged = builtins.foldl' (acc: dir:
        let
          dirSkills = readSkillDir dir;
          dirNames = builtins.attrNames dirSkills;
          newConflicts =
            builtins.filter (name: builtins.hasAttr name acc.skills) dirNames;
        in {
          skills = acc.skills // dirSkills;
          conflicts = acc.conflicts ++ newConflicts;
        }) {
          skills = { };
          conflicts = [ ];
        } skillsDirs;

      # Process a single skill directory: copy all files, then overwrite SKILL.md
      # with the variant-filtered version.
      processSkill = name: path:
        pkgs.runCommand "skill-${variant}-${name}" { } ''
          mkdir -p $out
          cp -r ${path}/* $out/
          chmod -R u+w $out
          ${processFrontmatter}/bin/process-frontmatter ${variant} ${path}/SKILL.md > $out/SKILL.md
        '';

      skillFiles = lib.mapAttrs' (name: path:
        lib.nameValuePair "${targetDir}/${name}" {
          source = processSkill name path;
          recursive = true;
        }) merged.skills;
    in {
      files = skillFiles;
      inherit (merged) conflicts;
    };
}
