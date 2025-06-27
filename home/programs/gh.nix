{ lib, config, ... }:
with lib;
let cfg = config.dotfiles.programs.gh;
in {
  options.dotfiles.programs.gh = { enable = mkEnableOption "Enable gh"; };

  config.programs.gh = mkIf cfg.enable {
    enable = true;
    gitCredentialHelper.enable = true;
    settings = { git-protocol = "ssh"; };
  };

  config.programs.gh-dash = mkIf cfg.enable {
    enable = true;
    settings = {
      theme = {
        colors = {
          text = {
            primary = "#c0caf5"; # TokyoNight foreground - main text
            secondary = "#a9b1d6"; # TokyoNight normal white - secondary text
            inverted = "#1a1b26"; # TokyoNight background - inverted text
            faint = "#414868"; # TokyoNight bright black - dim text
            warning = "#e0af68"; # TokyoNight yellow - warnings
            success = "#9ece6a"; # TokyoNight green - success
          };
          background = {
            selected = "#414868";
          }; # TokyoNight bright black - selected items
          border = {
            primary = "#7aa2f7"; # TokyoNight blue - primary borders
            secondary = "#414868"; # TokyoNight bright black - secondary borders
            faint = "#15161e"; # TokyoNight normal black - subtle borders
          };
        };
      };
    };
  };
}
