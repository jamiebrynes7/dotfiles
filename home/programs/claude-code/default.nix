{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;
  claudeWrapper = pkgs.writeShellScript "claude-wrapper" ''
    ${cfg.extraScript}
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';

  # Read .md files from a directory, returning an attrset of name -> path
  readCommandDir = dir:
    let files = builtins.readDir dir;
    in lib.mapAttrs (name: _: dir + "/${name}")
    (lib.filterAttrs
      (name: type: type == "regular" && lib.hasSuffix ".md" name)
      files);

  localCommands = readCommandDir ../../lib/ai/commands;
  extraCommands =
    if cfg.commandsDir != null then readCommandDir cfg.commandsDir else { };

  # Check for name conflicts
  localNames = builtins.attrNames localCommands;
  extraNames = builtins.attrNames extraCommands;
  conflicts = builtins.filter (name: builtins.elem name localNames) extraNames;

  # Build the final command files attribute set
  commandFiles = lib.mapAttrs' (name: path:
    lib.nameValuePair ".claude/commands/${name}" { source = path; })
    (localCommands // extraCommands);
in {
  options.dotfiles.programs.claude-code = {
    enable = mkEnableOption "Enable claude-code";
    extraScript = mkOption {
      type = types.lines;
      default = "";
      description =
        "Shell lines to run before execing claude-code (e.g. env tweaks).";
    };
    commandsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description =
        "Path to a directory of additional command files to symlink into ~/.claude/commands.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = conflicts == [ ];
      message =
        "claude-code: command name conflicts between built-in commands and provided commands: ${
          builtins.concatStringsSep ", " conflicts
        }";
    }];

    home.file = { ".claude/CLAUDE.md".source = ./CLAUDE.md; } // commandFiles;
    home.activation.claudeStableLink =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        install -m755 ${claudeWrapper} "$HOME/.local/bin/claude"
      '';

    # Add to PATH
    home.sessionPath = [ "$HOME/.local/bin" ];

    # Preserve config during switches
    home.activation.preserveClaudeConfig =
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
      '';

    home.activation.restoreClaudeConfig =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
      '';
  };
}
