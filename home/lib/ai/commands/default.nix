# Shared utilities for AI assistant command file management.
# Used by claude-code and cursor modules.
{ lib, pkgs }:
let
  # The directory containing the built-in command files (same dir as this file)
  commandsDir = ./.;

  # Python with PyYAML for frontmatter processing
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  processScript = ./process-frontmatter.py;

  # Read .md files from a directory, returning an attrset of name -> path
  readCommandDir = dir:
    let
      files = builtins.readDir dir;
    in
    lib.mapAttrs (name: _: dir + "/${name}")
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".md" name)
        files);

  localCommands = readCommandDir commandsDir;
in
{
  # Build command files for home.file, checking for conflicts.
  #
  # Arguments:
  #   variant: Target variant ("cc" or "cursor") for frontmatter filtering
  #   targetDir: Target directory relative to home (e.g., ".claude/commands")
  #   extraCommandsDir: Optional path to additional command files (null or path)
  #
  # Returns: {
  #   files: Attribute set suitable for home.file
  #   conflicts: List of conflicting command names (for assertions)
  # }
  mkCommandFiles = { variant, targetDir, extraCommandsDir }:
    let
      extraCommands =
        if extraCommandsDir != null
        then readCommandDir extraCommandsDir
        else { };

      localNames = builtins.attrNames localCommands;
      extraNames = builtins.attrNames extraCommands;
      conflicts = builtins.filter (name: builtins.elem name localNames) extraNames;

      # Process a single command file through the frontmatter filter
      processFile = name: path:
        pkgs.runCommand "cmd-${variant}-${name}" { } ''
          ${python}/bin/python3 ${processScript} ${variant} ${path} > $out
        '';

      allCommands = localCommands // extraCommands;

      commandFiles = lib.mapAttrs'
        (name: path:
          lib.nameValuePair "${targetDir}/${name}" {
            source = processFile name path;
          })
        allCommands;
    in
    {
      files = commandFiles;
      inherit conflicts;
    };
}
