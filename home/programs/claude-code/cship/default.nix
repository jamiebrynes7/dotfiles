{ config, lib, pkgs, ... }:
let
  cship = pkgs.callPackage ../../../../packages/cship { };
  cfg = config.dotfiles.programs.claude-code.cship;
in {
  options.dotfiles.programs.claude-code.cship = {
    enable = lib.mkEnableOption "Enable cship statusline for Claude Code";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cship ];

    home.file.".config/cship.toml".source = ./cship.toml;

    dotfiles.programs.claude-code.statusLine = {
      type = "command";
      command = "${cship}/bin/cship";
    };
  };
}
