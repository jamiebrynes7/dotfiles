# Shared utilities for AI assistant command file management.
# Used by claude-code and cursor modules.
{ lib, pkgs }:
let
  commandsDir = ./.;

  inherit (import ../tools { inherit pkgs; }) processFrontmatter;

  # Read .md files from a directory, returning an attrset of name -> path
  readCommandDir = dir:
    let files = builtins.readDir dir;
    in lib.mapAttrs (name: _: dir + "/${name}")
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name)
      files);

  localCommands = readCommandDir commandsDir;
in {
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
      extraCommands = if extraCommandsDir != null then
        readCommandDir extraCommandsDir
      else
        { };

      localNames = builtins.attrNames localCommands;
      extraNames = builtins.attrNames extraCommands;
      conflicts =
        builtins.filter (name: builtins.elem name localNames) extraNames;

      # Process a single command file through the frontmatter filter
      processFile = name: path:
        pkgs.runCommand "cmd-${variant}-${name}" { } ''
          ${processFrontmatter}/bin/process-frontmatter ${variant} ${path} > $out
        '';

      allCommands = localCommands // extraCommands;

      commandFiles = lib.mapAttrs' (name: path:
        lib.nameValuePair "${targetDir}/${name}" {
          source = processFile name path;
        }) allCommands;
    in {
      files = commandFiles;
      inherit conflicts;
    };
}
