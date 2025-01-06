{ config, lib, pkgs, ... }:
with lib;
let cfg = config.dotfiles.programs.bat;
in {
  options.dotfiles.programs.bat = { enable = mkEnableOption "Enable bat"; };

  config.programs.bat = mkIf cfg.enable {
    enable = true;
    config = { theme = "tokyonight-night"; };

    themes = {
      tokyonight-night = {
        src = pkgs.fetchFromGitHub {
          owner = "folke";
          repo = "tokyonight.nvim";
          rev = "v3.0.1";
          sha256 = "QKqCsPxUyTur/zOUZdiT1cOMSotmTsnOl/3Sn2/NlUI=";
        };
        file = "extras/sublime/tokyonight_night.tmTheme";
      };
    };
  };
}
