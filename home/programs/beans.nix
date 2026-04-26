{ config, lib, pkgs, ... }:
let
  beans = pkgs.callPackage ../../packages/beans { };
  cfg = config.dotfiles.programs.beans;
in {
  options.dotfiles.programs.beans = {
    enable = lib.mkEnableOption "Enable beans";
    claudeCodeHooks = lib.mkEnableOption
      "Register beans prime as Claude Code SessionStart/PreCompact hooks";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ beans ];

    dotfiles.programs.claude-code.hooks = lib.mkIf cfg.claudeCodeHooks {
      beans-prime-session-start = {
        enable = true;
        event = "SessionStart";
        hooks = [{
          type = "command";
          command = "${beans}/bin/beans prime";
        }];
      };
      beans-prime-pre-compact = {
        enable = true;
        event = "PreCompact";
        hooks = [{
          type = "command";
          command = "${beans}/bin/beans prime";
        }];
      };
    };
  };
}
