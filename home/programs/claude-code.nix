{ config, lib, pkgs, ... }:
with lib;
let cfg = config.dotfiles.programs.claude-code;
in {
  options.dotfiles.programs.claude-code = {
    enable = mkEnableOption "Enable claude-code";
    automaticPermissionPreservation = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkMerge [
    (mkIf cfg.enable { packages = [ pkgs.claude-code ]; })
    (mkIf (cfg.enable && cfg.automaticPermissionPreservation) {
      activation.claudeStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        rm -f $HOME/.local/bin/claude
        ln -s ${pkgs.claude-code}/bin/claude $HOME/.local/bin/claude
      '';

      # Add to PATH
      sessionPath = [ "$HOME/.local/bin" ];

      # Preserve config during switches
      activation.preserveClaudeConfig =
        lib.hm.dag.entryBefore [ "writeBoundary" ] ''
          [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
        '';

      activation.restoreClaudeConfig =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
        '';
    })
  ];
}
