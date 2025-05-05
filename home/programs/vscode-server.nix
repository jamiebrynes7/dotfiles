{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.vscode-server;

  jsonFormat = pkgs.formats.json { };
in {
  options.dotfiles.programs.vscode-server = {
    enable = mkEnableOption "Enable vscode-server";
    settings = mkOption {
      type = jsonFormat.type;
      default = { };
    };
  };

  config = mkIf cfg.enable {
    programs.vscode-likes.vscode-server = {
      enable = cfg.enable;
      remote = true;
      kind = "vscode";
      userSettings = cfg.settings;
    };
  };
}
