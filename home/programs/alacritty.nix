{ config, osConfig, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.alacritty;

  # When we are using brew, we are installing Alacritty via brew.
  useDummyPkg = osConfig.dotfiles.darwin.brew.enable;
in {
  options.dotfiles.programs.alacritty = {
    enable = mkEnableOption "Enable alacritty config";
    fontSize = mkOption {
      type = types.int;
      default = 9;
    };
    fontFamily = mkOption {
      type = types.str;
      default = "JetBrainsMono Nerd Font";
    };
  };

  config.programs.alacritty = mkIf cfg.enable {
    enable = true;
    package = mkIf useDummyPkg pkgs.emptyDirectory;
    settings = {
      window = {
        dimensions = {
          columns = 150;
          lines = 50;
        };

        decorations = "buttonless";
        padding = {
          x = 10;
          y = 10;
        };
      };

      font = {
        size = cfg.fontSize;
        normal.family = cfg.fontFamily;
        bold.family = cfg.fontFamily;
        italic.family = cfg.fontFamily;
      };

      general.import = [ pkgs.alacritty-theme.tokyo_night ];
      show_startup_tips = false;
    };
  };
}
