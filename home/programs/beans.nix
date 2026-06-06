{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.programs.beans;
in
{
  options.dotfiles.programs.beans = {
    enable = lib.mkEnableOption "Enable beans";
    enableClaudeCodeIntegration = lib.mkEnableOption "Wire beans into Claude Code: SessionStart/PreCompact prime hooks plus Bash(beans *) in the permission allowlist";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.dotfiles.beans ];

    dotfiles.programs.claude-code.permissions.allow = lib.mkIf cfg.enableClaudeCodeIntegration [
      "Bash(beans *)"
    ];

    dotfiles.programs.claude-code.hooks = lib.mkIf cfg.enableClaudeCodeIntegration {
      beans-prime-session-start = {
        enable = true;
        event = "SessionStart";
        hooks = [
          {
            type = "command";
            command = "${pkgs.dotfiles.beans}/bin/beans prime";
          }
        ];
      };
      beans-prime-pre-compact = {
        enable = true;
        event = "PreCompact";
        hooks = [
          {
            type = "command";
            command = "${pkgs.dotfiles.beans}/bin/beans prime";
          }
        ];
      };
    };
  };
}
