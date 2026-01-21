{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;
  claudeWrapper = pkgs.writeShellScript "claude-wrapper" ''
    ${cfg.extraScript}
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';

  # Build attribute set for command files
  commandFiles = let
    commandsDir = ./commands;
    files = builtins.readDir commandsDir;
  in lib.mapAttrs' (name: type:
    lib.nameValuePair ".claude/commands/${name}" {
      source = commandsDir + "/${name}";
    }) (lib.filterAttrs (name: type: type == "regular") files);
in {
  options.dotfiles.programs.claude-code = {
    enable = mkEnableOption "Enable claude-code";
    extraScript = mkOption {
      type = types.lines;
      default = "";
      description =
        "Shell lines to run before execing claude-code (e.g. env tweaks).";
    };
  };

  config = mkIf cfg.enable {
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
